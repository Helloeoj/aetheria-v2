extends Node
const Protocol = preload("res://network/world_protocol.gd")
const SnapshotTransport = preload("res://network/snapshot_transport.gd")
const EncryptedClient = preload("res://network/encrypted_enet_client.gd")
const BetaProfile = preload("res://network/beta_profile.gd")
## Shared RPC contract; world simulation and durable saves live in the host.
signal status_changed
signal joined
signal snapshot_received(snapshot: Dictionary)
signal action_result(sequence: int, result: Dictionary)
signal command_received(peer_id: int, command: Dictionary)
signal join_requested(peer_id: int, ticket: String)
signal peer_departed(peer_id: int)
signal logout_requested(peer_id: int)
enum Mode { OFFLINE, CLIENT, SERVER }
var mode := Mode.OFFLINE
var world_id := "world-1"
var status := "Not connected"
var authenticated := false
var character_id := ""
var username := ""
var region_id := "outskirts"
var saved_state: Dictionary = {}
var latest_snapshot: Dictionary = {}
var revision := -1
var sequence := 0
var account_token := ""
var account_url := "http://127.0.0.1:8780"
var beta_profile: Dictionary = {}
var release_id := ""
var _encrypted_client: RefCounted
var auto_scene := true
var game: Node
var _ticket := ""
var _pending: Dictionary = {}
var _incoming_sequences: Dictionary = {}
var _budget: Dictionary = {}
var _moving_elapsed := 0.0
var _snapshot_sequence := -1
var _snapshot_transport := SnapshotTransport.new()
var _scene_loading := false
var _last_direction := Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("tester_client"):
		beta_profile = BetaProfile.read_profile()
		if beta_profile.is_empty():
			status = "This tester installation is incomplete. Reinstall using the launcher."
		else:
			account_url = String(beta_profile.account_url)
			world_id = String(beta_profile.world_id)
			release_id = String(beta_profile.release_id)
	elif not OS.has_feature("dedicated_server") and not OS.get_cmdline_user_args().has("--world-server"):
		_configure_local_transport()
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_lost.bind("The world server could not be reached."))
	multiplayer.server_disconnected.connect(_lost.bind("Connection lost. Your character remains on the server while it saves."))
	multiplayer.peer_disconnected.connect(_departed)
	multiplayer.peer_connected.connect(func(id: int) -> void:
		if mode == Mode.SERVER:
			_pending[id] = Time.get_ticks_msec())
	if OS.get_cmdline_user_args().has("--world-server"):
		mode = Mode.SERVER

func _configure_local_transport() -> void:
	# The owner can keep playing from the editor while this PC hosts encrypted beta.
	var path := OS.get_environment("LOCALAPPDATA").path_join("Aetheria/online/world.json")
	if not FileAccess.file_exists(path):
		return
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not config is Dictionary or not config.has("tls_certificate") or not config.has("release_id"):
		return
	release_id = String(config.release_id)
	world_id = String(config.get("world_id", "world-1"))
	beta_profile = {"world_host": "127.0.0.1", "world_port": int(config.get("port", 24567)),
		"tls_certificate": String(config.tls_certificate), "tls_name": String(config.get("tls_name", "aetheria-beta"))}

func host(port: int, max_players: int, bind_address: String = "127.0.0.1", tls_options: TLSOptions = null) -> Error:
	if OS.has_feature("tester_client"):
		return ERR_UNAUTHORIZED
	if max_players < 1 or max_players > 4079 or (bind_address != "127.0.0.1" and (tls_options == null or (bind_address != "*" and not bind_address.is_valid_ip_address()))):
		return ERR_INVALID_PARAMETER
	mode = Mode.SERVER
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip(bind_address)
	var error := peer.create_server(port, max_players + 16, 3)
	if error == OK and tls_options != null:
		error = peer.host.dtls_server_setup(tls_options)
	if error == OK:
		multiplayer.multiplayer_peer = peer
	else:
		peer.close()
	return error

func join_world(ticket: String, address: String = "127.0.0.1", port: int = 24567) -> Error:
	if OS.has_feature("tester_client") and beta_profile.is_empty():
		return ERR_UNCONFIGURED
	if not beta_profile.is_empty():
		address = String(beta_profile.world_host)
		port = int(beta_profile.world_port)
	elif address not in ["127.0.0.1", "localhost", "::1"]:
		status = "A verified encrypted world profile is required."
		status_changed.emit()
		return ERR_UNAUTHORIZED
	mode = Mode.CLIENT
	authenticated = false
	_ticket = ticket
	_snapshot_sequence = -1
	_snapshot_transport.reset()
	_last_direction = Vector2.ZERO
	_scene_loading = false
	var error := OK
	if not beta_profile.is_empty():
		var certificate := X509Certificate.new()
		error = certificate.load(String(beta_profile.tls_certificate))
		if error == OK:
			_encrypted_client = EncryptedClient.new()
			error = _encrypted_client.start(address, port, String(beta_profile.tls_name), certificate)
	else:
		var peer := ENetMultiplayerPeer.new()
		error = peer.create_client(address, port, 3)
		if error == OK:
			multiplayer.multiplayer_peer = peer
	if error == OK:
		status = "Connecting to world…"
	else:
		status = "The world could not be reached."
	status_changed.emit()
	return error

func _connected() -> void:
	if mode == Mode.CLIENT and not _ticket.is_empty():
		_request.rpc_id(1, Protocol.pack({"v": 1, "type": "join", "ticket": _ticket, "world_id": world_id}))
		_ticket = ""

func bind_game(value: Node) -> void:
	if mode == Mode.CLIENT:
		game = value
		if authenticated and not saved_state.is_empty():
			game.call("apply_online_snapshot", latest_snapshot)

func online() -> bool:
	return mode == Mode.CLIENT

func open_developer_sandbox() -> bool:
	if OS.has_feature("tester_client"):
		return false
	# Online progress must finish its authoritative save/logout before testing.
	if authenticated:
		return false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_revoke_account_session(account_token)
	account_token = ""
	_ticket = ""
	character_id = ""
	username = ""
	region_id = "outskirts"
	saved_state = {}
	latest_snapshot = {}
	revision = -1
	sequence = 0
	_snapshot_sequence = -1
	_snapshot_transport.reset()
	_scene_loading = false
	_last_direction = Vector2.ZERO
	_moving_elapsed = 0.0
	game = null
	mode = Mode.OFFLINE
	status = "Developer sandbox — progress is not saved online."
	var travel := get_node_or_null("/root/SceneTravel")
	if travel != null:
		travel.call("clear_online_binding")
	var social := get_node_or_null("/root/Social")
	if social != null and social.panel != null:
		social.panel.show()
	status_changed.emit()
	get_tree().call_deferred("change_scene_to_file", "res://scenes/EastOutskirtsLayered.tscn")
	return true

func send_action(command: Dictionary) -> bool:
	if not online() or not authenticated:
		return false
	if command.get("type") in ["walk", "attack", "travel", "mine_start", "fish_start", "cook_start"]:
		replace_keyboard_intent()
	sequence += 1
	var data := command.duplicate(true)
	data["v"] = 1
	data["sequence"] = sequence
	if is_instance_valid(game) and game.get("online_view") != null:
		game.online_view.record_command(sequence, command)
	if data.get("type", "") == "move":
		_movement.rpc_id(1, Protocol.pack(data))
	else:
		_request.rpc_id(1, Protocol.pack(data))
	return true

func replace_keyboard_intent() -> void:
	# The reliable intent already stops keyboard movement on the host. A later
	# synthetic release must not overtake that intent on the movement channel.
	if is_instance_valid(game):
		game._reset_held_movement()
	_last_direction = Vector2.ZERO
	_moving_elapsed = 0.0

func request_logout() -> void:
	if authenticated:
		send_action({"type": "logout"})
		status = "Saving character…"
		status_changed.emit()

func send_control(peer_id: int, response: Dictionary) -> void:
	if mode == Mode.SERVER and multiplayer.get_peers().has(peer_id):
		var data := response.duplicate(true)
		data["v"] = 1
		_response.rpc_id(peer_id, Protocol.pack(data))

func send_snapshot(peer_id: int, data: Dictionary) -> void:
	if mode == Mode.SERVER and multiplayer.get_peers().has(peer_id):
		var payload := data.duplicate(true)
		payload["v"] = 1
		payload["type"] = "snapshot"
		for packet: PackedByteArray in SnapshotTransport.chunk(payload):
			_state.rpc_id(peer_id, packet)

func _process(delta: float) -> void:
	if _encrypted_client != null:
		var error: Error = _encrypted_client.poll()
		if error == OK:
			multiplayer.multiplayer_peer = _encrypted_client.multiplayer_peer
			error = _encrypted_client.attach_server()
			if error != OK:
				_encrypted_client.close()
				_encrypted_client = null
				_lost("The encrypted world connection could not be attached.")
				return
			_encrypted_client = null
			_connected()
		elif error != ERR_BUSY:
			_encrypted_client = null
			_ticket = ""
			_lost("The encrypted world connection could not be verified. Retry from the launcher.")
	if mode == Mode.SERVER:
		for id: int in _pending.keys():
			if Time.get_ticks_msec() - int(_pending[id]) > 15000:
				_pending.erase(id)
				(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id)
	elif online() and authenticated and is_instance_valid(game):
		_moving_elapsed += delta
		var direction := movement_direction()
		# Send changes on this frame; 30 Hz refresh only keeps held input alive.
		if not direction.is_equal_approx(_last_direction) or _moving_elapsed >= 1.0 / 30.0:
			_moving_elapsed = 0.0
			if not direction.is_zero_approx() or not direction.is_equal_approx(_last_direction):
				send_action({"type": "move", "direction": [direction.x, direction.y]})
			_last_direction = direction

func movement_direction() -> Vector2:
	if not authenticated or not is_instance_valid(game) or _scene_loading:
		return Vector2.ZERO
	if bool(game.call("_ui_is_editing")) or game.inventory_menu.visible:
		return Vector2.ZERO
	return game.movement_controller.get_move_vector()

func mark_admitted(peer_id: int) -> void:
	_pending.erase(peer_id)

func _departed(id: int) -> void:
	if mode == Mode.CLIENT and id == 1:
		_lost("Connection lost. Your character remains on the server while it saves.")
	_pending.erase(id)
	_incoming_sequences.erase(id)
	_budget.erase(id)
	if mode == Mode.SERVER:
		peer_departed.emit(id)

func _lost(message: String) -> void:
	authenticated = false
	status = message
	status_changed.emit()
	if is_instance_valid(game):
		game.set_process_unhandled_input(false)
		game.set_physics_process(false)
		if auto_scene:
			game = null
			saved_state = {}
			latest_snapshot = {}
			_snapshot_transport.reset()
			if multiplayer.multiplayer_peer != null:
				multiplayer.multiplayer_peer.close()
			get_tree().call_deferred("change_scene_to_file", "res://scenes/Login.tscn")

func _allow(peer_id: int) -> bool:
	var now := Time.get_ticks_msec()
	var bucket: Dictionary = _budget.get(peer_id, {"at": now, "tokens": 120.0})
	bucket.tokens = minf(120.0, float(bucket.tokens) + float(now - int(bucket.at)) * 0.060)
	bucket.at = now
	if float(bucket.tokens) < 1.0:
		_budget[peer_id] = bucket
		return false
	bucket.tokens = float(bucket.tokens) - 1.0
	_budget[peer_id] = bucket
	return true

@rpc("any_peer", "call_remote", "reliable", 0)
func _request(payload: PackedByteArray) -> void:
	if mode != Mode.SERVER or payload.size() > 8192:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _allow(sender):
		return
	var command := Protocol.unpack(payload)
	if command.is_empty():
		return
	if command.type == "join":
		if _pending.has(sender) and command.get("ticket") is String and String(command.ticket).length() <= 256 and command.get("world_id") == world_id:
			join_requested.emit(sender, command.ticket)
	elif not _pending.has(sender):
		if command.type == "logout":
			logout_requested.emit(sender)
		else:
			command_received.emit(sender, command)

@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _movement(payload: PackedByteArray) -> void:
	if mode != Mode.SERVER or payload.size() > 512:
		return
	var sender := multiplayer.get_remote_sender_id()
	if _pending.has(sender) or not _allow(sender):
		return
	var command := Protocol.unpack(payload)
	var serial: Variant = command.get("sequence", -1)
	if command.get("type") != "move" or not (serial is int or serial is float) or not is_finite(float(serial)) or floor(float(serial)) != float(serial) or float(serial) <= float(_incoming_sequences.get(sender, -1)) or float(serial) > 9007199254740991.0:
		return
	_incoming_sequences[sender] = int(serial)
	command_received.emit(sender, command)

@rpc("authority", "call_remote", "reliable", 0)
func _response(payload: PackedByteArray) -> void:
	if mode != Mode.CLIENT or multiplayer.get_remote_sender_id() != 1:
		return
	var response := Protocol.unpack(payload)
	match response.get("type", ""):
		"joined":
			character_id = String(response.character_id)
			username = String(response.username)
			region_id = String(response.region_id)
			saved_state = response.state
			revision = int(response.revision)
			latest_snapshot = {"state": saved_state, "region_id": region_id, "actors": []}
			authenticated = true
			status = "Connected — " + world_id
			joined.emit()
			if auto_scene:
				_load_region(region_id)
		"logout":
			authenticated = false
			_revoke_account_session(account_token)
			account_token = ""
			if multiplayer.multiplayer_peer != null:
				multiplayer.multiplayer_peer.close()
			game = null
			status = String(response.get("message", "Character saved."))
			if auto_scene:
				saved_state = {}
				latest_snapshot = {}
				get_tree().change_scene_to_file("res://scenes/Login.tscn")
		"error", "notice", "result":
			status = String(response.get("message", response.get("code", "")))
			if response.get("type") == "result" and response.has("sequence"):
				action_result.emit(int(response.sequence),response.duplicate(true))
	status_changed.emit()

@rpc("authority", "call_remote", "unreliable", 1)
func _state(payload: PackedByteArray) -> void:
	if mode != Mode.CLIENT or not authenticated or multiplayer.get_remote_sender_id() != 1:
		return
	var snapshot := _snapshot_transport.accept(payload)
	if snapshot.is_empty():
		return
	var serial := int(snapshot.get("snapshot_id", -1))
	if serial <= _snapshot_sequence:
		return
	_snapshot_sequence = serial
	if snapshot.get("state") is Dictionary:
		saved_state = snapshot.state
		revision = int(snapshot.get("revision", revision))
	latest_snapshot = snapshot
	latest_snapshot["state"] = saved_state
	var next_region := String(snapshot.get("region_id", region_id))
	if next_region != region_id:
		region_id = next_region
		if auto_scene:
			_load_region(region_id)
	elif is_instance_valid(game) and not _scene_loading:
		game.call("apply_online_snapshot", latest_snapshot)
	snapshot_received.emit(latest_snapshot)

func _load_region(id: String) -> void:
	if not Protocol.REGIONS.has(id) or not ResourceLoader.exists(Protocol.REGIONS[id]):
		_lost("The server selected an unavailable game area.")
		return
	_scene_loading = true
	replace_keyboard_intent()
	if is_instance_valid(game) and game.has_method("prepare_area_exit"):
		game.prepare_area_exit()
	game = null
	var travel := get_node_or_null("/root/SceneTravel")
	if travel != null:
		travel.call("clear_online_binding")
	get_tree().change_scene_to_file(Protocol.REGIONS[id])
	await get_tree().scene_changed
	_scene_loading = false
	if is_instance_valid(game):
		game.call("apply_online_snapshot", latest_snapshot)

func _revoke_account_session(token: String) -> void:
	if token.is_empty():
		return
	var http := preload("res://network/account_http.gd").new()
	add_child(http)
	http.endpoint = account_url
	await http.request_json("/api/logout", {}, token)
	http.queue_free()
