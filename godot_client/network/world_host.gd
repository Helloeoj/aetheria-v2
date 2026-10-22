extends Node
const AccountHTTP = preload("res://network/account_http.gd")
const CharacterCodec = preload("res://network/character_codec.gd")
const WorldProtocol = preload("res://network/world_protocol.gd")
const SpatialIndex = preload("res://network/spatial_relevance.gd")
const MOVEMENT_COMMANDS := ["walk", "target", "attack", "cast", "travel"]
## One authoritative world; regions have separate physics spaces and stable IDs.
var regions: Dictionary = {}
var sessions: Dictionary = {}
var joining: Dictionary = {}
var max_players := 50
var snapshot_hz := 10.0
var interest_radius := 32.0
var port := 24567
var _http: AccountHTTP
var _key := ""
var _step_elapsed := 0.0
var _snapshot_elapsed := 0.0
var _snapshot_id := 0
var _stopping := false
var _data_dir := ""

func _ready() -> void:
	Network.mode = Network.Mode.SERVER
	_data_dir = OS.get_environment("LOCALAPPDATA").path_join("Aetheria/online")
	_key = FileAccess.get_file_as_string(_data_dir.path_join("server.key")).strip_edges()
	var config_path := _data_dir.path_join("world.json")
	if FileAccess.file_exists(config_path):
		var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path))
		if not config is Dictionary or not _configure(config):
			printerr("[World] Invalid world configuration; no server was started.")
			get_tree().quit(1)
			return
	_http = AccountHTTP.new()
	add_child(_http)
	if _key.length() < 32:
		printerr("[World] Start the local account service first.")
		get_tree().quit(1)
		return
	Network.join_requested.connect(_join)
	Network.command_received.connect(_command)
	Network.peer_departed.connect(_departed)
	Network.logout_requested.connect(_logout)
	var error := Network.host(port, max_players)
	if error != OK:
		printerr("[World] Could not bind the configured local world port.")
		get_tree().quit(1)
		return
	await _get_region("outskirts")
	var ready_file := FileAccess.open(_data_dir.path_join("world-ready.json"), FileAccess.WRITE)
	if ready_file != null:
		ready_file.store_string(JSON.stringify({"pid": OS.get_process_id(), "port": port, "max_players": max_players, "world_id": Network.world_id}))
	print("[World] ready; configured capacity=%d, simulation=30Hz" % max_players)

func _configure(config: Dictionary) -> bool:
	var raw: Variant = config.get("max_players", 50)
	if not (raw is int or raw is float) or not is_finite(float(raw)) or floor(float(raw)) != float(raw) or float(raw) < 1 or float(raw) > 4079:
		return false
	max_players = int(raw)
	var configured_port: Variant = config.get("port", 24567)
	if not (configured_port is int or configured_port is float) or not is_finite(float(configured_port)) or floor(float(configured_port)) != float(configured_port) or float(configured_port) < 1024 or float(configured_port) > 65535:
		return false
	port = int(configured_port)
	var frequency: Variant = config.get("snapshot_hz", 10)
	var radius: Variant = config.get("interest_radius", 32)
	if not (frequency is int or frequency is float) or not (radius is int or radius is float):
		return false
	if not is_finite(float(frequency)) or float(frequency) < 1 or float(frequency) > 30 or not is_finite(float(radius)) or float(radius) < 8 or float(radius) > 128:
		return false
	snapshot_hz = float(frequency)
	interest_radius = float(radius)
	var id: Variant = config.get("world_id", "world-1")
	if not id is String or RegEx.create_from_string("^[A-Za-z0-9_-]{1,64}$").search(id) == null:
		return false
	Network.world_id = id
	return true

func _get_region(id: String) -> AuthoritativeRegion:
	if regions.has(id):
		return regions[id]
	if not WorldProtocol.REGIONS.has(id) or not ResourceLoader.exists(WorldProtocol.REGIONS[id]):
		return null
	# Each region has independent map collision even when hosted in one process.
	var viewport := SubViewport.new()
	viewport.name = "Region_" + id
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var map := (load(WorldProtocol.REGIONS[id]) as PackedScene).instantiate()
	var geometry: Node = map.get_node_or_null("Combat")
	if geometry == null:
		viewport.queue_free()
		return null
	geometry.set_meta("online_server_geometry", true)
	viewport.add_child(map)
	geometry.set_physics_process(false)
	geometry.set_process_input(false)
	geometry.set_process_unhandled_input(false)
	geometry.get_node("UI").process_mode = Node.PROCESS_MODE_DISABLED
	if geometry.cooking_controller != null:
		geometry.cooking_controller.set_process(false)
	if geometry.actor_sprites.has("player"):
		geometry.actor_sprites["player"].queue_free()
		geometry.actor_sprites.erase("player")
	var region := AuthoritativeRegion.new()
	region.configure(id, geometry)
	regions[id] = region
	await get_tree().physics_frame
	return region

func _join(peer_id: int, ticket: String) -> void:
	if joining.has(peer_id) or sessions.has(peer_id) or _stopping:
		return
	if sessions.size() + joining.size() >= max_players:
		Network.send_control(peer_id, {"type": "error", "code": "world_full", "message": "This world is full. Please try again later."})
		return
	joining[peer_id] = true
	var claim := await _http.request_json("/internal/claim", {"ticket": ticket, "world_id": Network.world_id}, "", _key)
	if not claim.get("ok", false):
		joining.erase(peer_id)
		Network.send_control(peer_id, {"type": "error", "message": claim.get("message", "World admission was rejected.")})
		return
	var state: Dictionary = claim.get("state", {})
	var region_id := String(state.get("region_id", "outskirts"))
	var region := await _get_region(region_id)
	if region == null:
		joining.erase(peer_id)
		Network.send_control(peer_id, {"type": "error", "message": "The saved region is unavailable. Your save has not been replaced."})
		return
	var decoded := CharacterCodec.initial(String(claim.username), String(claim.character_id), region_id) if state.is_empty() else CharacterCodec.decode(state, String(claim.username), String(claim.character_id))
	if not decoded.ok:
		joining.erase(peer_id)
		Network.send_control(peer_id, {"type": "error", "message": decoded.message})
		return
	var player: PlayerState = decoded.player
	# A successful claim fences every earlier generation, including one whose
	# heartbeat expired while the account service was unavailable.
	for previous: Dictionary in sessions.values():
		if previous.character_id == String(claim.character_id):
			_retire(previous, "Character ownership moved to a new session.")
	if region.players.has(String(claim.character_id)):
		region.remove_player(String(claim.character_id))
	if state.is_empty() and region.geometry_game != null:
		player.x = region.geometry_game.player.x
		player.y = region.geometry_game.player.y
	var session := {"peer": peer_id, "character_id": String(claim.character_id), "username": String(claim.username), "lease_token": String(claim.lease_token), "revision": int(claim.revision), "region_id": region_id, "player": player, "state": state, "hash": "", "busy": false, "queue": [], "pending": {}, "last_save": Time.get_ticks_msec(), "heartbeat": Time.get_ticks_msec(), "disconnected": 0, "closing": false, "last_sequence": -1, "saving": false}
	region.add_player(session.character_id, player)
	if region.players.get(session.character_id) != player:
		joining.erase(peer_id)
		Network.send_control(peer_id, {"type": "error", "message": "A safe character spawn is unavailable."})
		return
	sessions[peer_id] = session
	joining.erase(peer_id)
	if not await _persist(session):
		return
	if not multiplayer.get_peers().has(peer_id):
		_departed(peer_id)
		return
	Network.mark_admitted(peer_id)
	Network.send_control(peer_id, {"type": "joined", "character_id": session.character_id, "username": session.username, "region_id": region_id, "state": session.state, "revision": session.revision})

func _command(peer_id: int, raw: Dictionary) -> void:
	if not sessions.has(peer_id) or _stopping:
		return
	var session: Dictionary = sessions[peer_id]
	if session.closing or session.get("retired", false) or session.get("ownership_paused", false):
		return
	if not session.pending.is_empty() and (not session.saving or session.get("pending_release", false)):
		return
	var command := raw.duplicate(true)
	command.erase("v")
	var serial: Variant = command.get("sequence", -1)
	command.erase("sequence")
	if not (serial is int or serial is float) or not is_finite(float(serial)) or floor(float(serial)) != float(serial) or float(serial) < 0 or float(serial) > 9007199254740991.0:
		return
	if command.get("type") == "move":
		if int(serial) <= int(session.get("movement_sequence", -1)):
			return
		var region: AuthoritativeRegion = regions[session.region_id]
		var result := region.submit(session.character_id, command)
		if result.get("ok", false):
			session.movement_sequence = int(serial)
			session.movement_ack = int(serial)
			session.movement_at = region._clock
		return
	if int(serial) <= int(session.last_sequence):
		return
	session.last_sequence = int(serial)
	if session.queue.size() >= 8:
		return
	# Keep the serial until execution: HTTP saves can let newer keyboard intent
	# overtake a queued click on its separate network channel.
	command["sequence"] = int(serial)
	session.queue.append(command)
	if not session.busy:
		_process_commands(session)

func _process_commands(session: Dictionary) -> void:
	session.busy = true
	while not session.queue.is_empty() and not session.closing and not session.get("retired", false):
		while session.saving:
			await get_tree().process_frame
		if session.get("retired", false) or session.closing or not session.pending.is_empty():
			break
		var command: Dictionary = session.queue.pop_front()
		var serial := int(command.get("sequence", -1))
		command.erase("sequence")
		var changes_movement: bool = command.get("type") in MOVEMENT_COMMANDS
		if changes_movement and serial <= int(session.get("movement_sequence", -1)):
			continue
		var result: Dictionary
		if command.get("type") == "travel":
			result = await _travel(session, String(command.get("portal_id", "")))
		else:
			result = regions[session.region_id].submit(session.character_id, command)
		if result.get("ok", false) and changes_movement:
			# Destination loading may have yielded while newer source input arrived.
			session.movement_sequence = maxi(serial, int(session.get("movement_sequence", -1)))
			session.movement_ack = -1
			session.erase("movement_at")
		if result.get("ok", false) and not await _persist(session):
			break
		Network.send_control(session.peer, {"type": "result", "code": result.get("code", ""), "message": result.get("message", "")})
	session.busy = false

func _physics_process(delta: float) -> void:
	if _http == null or _key.is_empty():
		return
	_step_elapsed += minf(delta, 0.25)
	var steps := 0
	while _step_elapsed >= 1.0 / 30.0 and steps < 4:
		_step_elapsed -= 1.0 / 30.0
		steps += 1
		for region: AuthoritativeRegion in regions.values():
			region.advance(1.0 / 30.0)
	_snapshot_elapsed += delta
	if _snapshot_elapsed >= 1.0 / snapshot_hz:
		_snapshot_elapsed = 0.0
		_snapshot_id += 1
		_service_sessions()
	if not _stopping and FileAccess.file_exists(_data_dir.path_join("world-stop.request")):
		_shutdown()

func _service_sessions() -> void:
	var now := Time.get_ticks_msec()
	var public_regions := {}
	var indexes := {}
	for id: String in regions:
		public_regions[id] = regions[id].snapshot("")
		var index := SpatialIndex.new()
		index.update(public_regions[id].actors)
		indexes[id] = index
	for session: Dictionary in sessions.values():
		var region: AuthoritativeRegion = regions[session.region_id]
		if not session.closing and not session.saving and session.pending.is_empty():
			var state := CharacterCodec.encode(session.player, session.region_id)
			if state != session.state and (_critical_hash(state) != session.hash or now - int(session.last_save) >= 5000):
				_persist(session)
		if now - int(session.heartbeat) >= 10000:
			session.heartbeat = now
			_heartbeat(session)
		if int(session.disconnected) > 0 and now - int(session.disconnected) > 30000 and not session.closing:
			_finalize(session)
		var snapshot: Dictionary = public_regions[session.region_id].duplicate()
		snapshot["actors"] = indexes[session.region_id].nearby(session.player.get_position(), interest_radius)
		snapshot["activity"] = region.activities.snapshot(session.character_id)
		snapshot["snapshot_id"] = _snapshot_id
		snapshot["revision"] = session.revision
		snapshot["state"] = session.state
		snapshot["saving"] = session.saving or not session.pending.is_empty()
		snapshot["population"] = sessions.size()
		snapshot["capacity"] = max_players
		snapshot["in_combat"] = session.player.in_combat
		snapshot.merge(_movement_snapshot(session, region))
		Network.send_snapshot(session.peer, snapshot)

func _movement_snapshot(session: Dictionary, region: AuthoritativeRegion) -> Dictionary:
	var actor: CombatActor = region.world.combat.actors.get(session.character_id)
	var ack := int(session.get("movement_ack", -1))
	var pending_blocked: bool = not session.pending.is_empty() and (not session.saving or session.get("pending_release", false))
	return {"server_time": region._clock, "snapshot_interval": 1.0 / snapshot_hz,
		"movement_ack": ack,
		"movement_age": maxf(0.0, region._clock - float(session.get("movement_at", region._clock))) if ack >= 0 else 0.0,
		"movement_enabled": actor != null and actor.is_alive and not region.frozen.has(session.character_id)
			and not session.closing and not session.get("retired", false)
			and not session.get("ownership_paused", false) and not pending_blocked}

func _persist(session: Dictionary, release: bool = false) -> bool:
	while session.saving:
		await get_tree().process_frame
	if session.get("retired", false):
		return false
	var region: AuthoritativeRegion = regions[session.region_id]
	# Retry the identical operation and endpoint after an uncertain response. A
	# final release always captures a fresh state after an earlier save is settled.
	while true:
		session.saving = true
		if session.pending.is_empty():
			session.pending_release = release
			session.pending_checkpoint = region.mutation_checkpoint(session.character_id)
			session.pending_region = session.region_id
			session.pending = {"lease_token": session.lease_token, "character_id": session.character_id, "expected_revision": session.revision, "operation_id": Crypto.new().generate_random_bytes(16).hex_encode(), "state": CharacterCodec.encode(session.player, session.region_id)}
		var operation: Dictionary = session.pending.duplicate(true)
		var operation_release := bool(session.get("pending_release", false))
		var result := await _http.request_json("/internal/release" if operation_release else "/internal/save", operation, "", _key)
		session.saving = false
		if session.get("retired", false):
			return false
		if not result.get("ok", false):
			if result.get("code", "") == "stale_lease":
				_retire(session, "Character ownership expired. Log in again to restore your saved progress.")
			else:
				region.frozen[session.character_id] = true
				Network.send_control(session.peer, {"type": "error", "code": "save_pending", "message": "Saving is temporarily unavailable. Your character is paused while the server recovers the transaction."})
			return false
		session.revision = int(result.revision)
		session.state = operation.state
		session.hash = _critical_hash(operation.state)
		session.last_save = Time.get_ticks_msec()
		session.pending = {}
		var mutation_region: AuthoritativeRegion = regions.get(session.get("pending_region", session.region_id))
		if mutation_region != null:
			mutation_region.commit_mutations(session.character_id, int(session.get("pending_checkpoint", -1)))
		if release and not operation_release:
			continue
		if operation_release:
			_complete_release(session)
			return true
		if not session.closing and not session.get("ownership_paused", false):
			region.frozen.erase(session.character_id)
		return true
	return false

func _heartbeat(session: Dictionary) -> void:
	var result := await _http.request_json("/internal/heartbeat", {"lease_token": session.lease_token, "character_id": session.character_id}, "", _key)
	if session.get("retired", false):
		return
	if not result.get("ok", false):
		if result.get("code", "") == "stale_lease":
			_retire(session, "Character ownership expired. Log in again to restore your saved progress.")
			return
		session.ownership_paused = true
		regions[session.region_id].frozen[session.character_id] = true
		Network.send_control(session.peer, {"type": "error", "message": "Character ownership could not be renewed; gameplay is paused."})
	else:
		session.ownership_paused = false
		if not session.pending.is_empty() and not session.saving and not session.closing:
			await _persist(session)
		elif not session.saving and not session.closing and session.pending.is_empty():
			regions[session.region_id].frozen.erase(session.character_id)

func _retire(session: Dictionary, message: String) -> void:
	if session.get("retired", false):
		return
	session.retired = true
	session.closing = true
	session.queue.clear()
	var region: AuthoritativeRegion = regions.get(session.region_id)
	if region != null and region.players.get(session.character_id) == session.player:
		region.discard_mutations(session.character_id)
		region.remove_player(session.character_id)
	if sessions.has(session.peer) and sessions[session.peer].lease_token == session.lease_token:
		sessions.erase(session.peer)
	Network.send_control(session.peer, {"type": "logout", "message": message})

func _complete_release(session: Dictionary) -> void:
	# A release retried by the heartbeat has the same terminal behavior as one
	# confirmed directly by logout. A released lease must never resume gameplay.
	session.retired = true
	session.closing = true
	session.queue.clear()
	var region: AuthoritativeRegion = regions.get(session.region_id)
	if region != null and region.players.get(session.character_id) == session.player:
		region.remove_player(session.character_id)
	if sessions.has(session.peer) and sessions[session.peer].lease_token == session.lease_token:
		sessions.erase(session.peer)
	Network.send_control(session.peer, {"type": "logout", "message": "Character saved."})

func _departed(peer_id: int) -> void:
	if sessions.has(peer_id):
		var session: Dictionary = sessions[peer_id]
		session.disconnected = Time.get_ticks_msec()
		regions[session.region_id].submit(session.character_id, {"type": "move", "direction": [0.0, 0.0]})

func _logout(peer_id: int) -> void:
	if not sessions.has(peer_id):
		return
	var session: Dictionary = sessions[peer_id]
	if session.player.in_combat:
		Network.send_control(peer_id, {"type": "notice", "message": "Finish combat before logging out."})
		return
	_finalize(session)

func _finalize(session: Dictionary) -> void:
	if session.closing or session.get("retired", false):
		return
	session.closing = true
	var region: AuthoritativeRegion = regions[session.region_id]
	region.activities.close(session.character_id)
	region.frozen[session.character_id] = true
	while session.busy:
		await get_tree().process_frame
	if not await _persist(session, true):
		if not session.get("retired", false):
			session.closing = false
		return

func _travel(session: Dictionary, portal_id: String) -> Dictionary:
	var region: AuthoritativeRegion = regions[session.region_id]
	var geometry: Node = region.geometry_game
	var portal: Node
	for candidate: Node in get_tree().get_nodes_in_group("cave_portal"):
		if geometry.get_parent().is_ancestor_of(candidate) and str(geometry.get_parent().get_path_to(candidate)) == portal_id:
			portal = candidate
			break
	if portal == null or not portal is CavePortal or not portal.enabled or session.player.in_combat:
		return {"ok": false, "message": "That entrance is unavailable."}
	var point: Vector2 = geometry._screen_position(session.player.x, session.player.y)
	if geometry.to_global(point).distance_to(portal.approach_position()) > portal.interaction_radius:
		return {"ok": false, "message": "Move closer to the entrance."}
	var destination := WorldProtocol.region_for_scene(portal.destination_scene)
	if destination.is_empty():
		return {"ok": false, "message": "The destination is not approved."}
	var next := await _get_region(destination)
	if session.closing or session.get("retired", false) or sessions.get(session.peer, {}).get("lease_token") != session.lease_token or region.players.get(session.character_id) != session.player:
		return {"ok": false, "message": "Character ownership changed during travel."}
	if next == null:
		return {"ok": false, "message": "The destination is unavailable."}
	region.activities.close(session.character_id)
	region.remove_player(session.character_id)
	var next_geometry: Node = next.geometry_game
	var marker := next_geometry.get_parent().get_node_or_null("SpawnPoints/" + portal.destination_spawn_id) as Node2D
	if marker != null:
		var local_point: Vector2 = next_geometry.to_local(marker.global_position)
		session.player.x = (local_point.x - next_geometry.map_origin.x) / next_geometry.TILE_SIZE
		session.player.y = (next_geometry.map_origin.y + next_geometry.map_height - local_point.y) / next_geometry.TILE_SIZE
	session.region_id = destination
	next.add_player(session.character_id, session.player)
	return {"ok": true, "message": "Entered " + destination + "."}

func _shutdown() -> void:
	_stopping = true
	for session: Dictionary in sessions.values():
		await _finalize(session)
	if sessions.is_empty():
		DirAccess.remove_absolute(_data_dir.path_join("world-ready.json"))
		DirAccess.remove_absolute(_data_dir.path_join("world-stop.request"))
		get_tree().quit()
	else:
		_stopping = false

static func _critical_hash(state: Dictionary) -> String:
	var important := state.duplicate(true)
	for field: String in ["x", "y", "hp", "food_cooldown_seconds", "food_attack_cooldown_seconds", "food_attack_interval_seconds"]:
		important.erase(field)
	return JSON.stringify(important).sha256_text()
