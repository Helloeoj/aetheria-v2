extends Node
## Real maps and portal rules; account persistence is a local deterministic double.
class TestHost extends "res://network/world_host.gd":
	var retire_during_destination := ""
	var retire_session: Dictionary = {}
	func _ready() -> void:
		set_physics_process(false)
	func _get_region(id: String) -> AuthoritativeRegion:
		var region: AuthoritativeRegion = await super._get_region(id)
		if id == retire_during_destination:
			retire_during_destination = ""
			await get_tree().process_frame
			_retire(retire_session,"Isolated travel ownership changed")
		return region

class FakeAccountHTTP extends "res://network/account_http.gd":
	var requests: Array[Dictionary] = []
	func request_json(route: String, data: Dictionary = {}, _bearer: String = "", _key: String = "", _method: int = HTTPClient.METHOD_POST) -> Dictionary:
		requests.append({"route":route,"body":data.duplicate(true)})
		await get_tree().process_frame
		return {"ok":true,"revision":int(data.get("expected_revision",0))+1}

var checks := 0
var failures := 0
var host: TestHost
var http: FakeAccountHTTP
var spectator: PlayerState
var spectator_position := Vector2.ZERO

func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(90).timeout.connect(func() -> void:
		printerr("[Online region travel FAIL] Timed out")
		get_tree().quit(1))

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("[Online region travel FAIL] ",message)

func _run() -> void:
	host = TestHost.new()
	add_child(host)
	http = FakeAccountHTTP.new()
	host.add_child(http)
	host._http = http
	host._key = "isolated-travel-fixture"
	var outskirts: AuthoritativeRegion = await host._get_region("outskirts")
	check(outskirts != null,"Actual outskirts map creates an authoritative region")
	if outskirts == null:
		_finish()
		return
	var traveler := PlayerState.new("Portal traveler")
	traveler.x = outskirts.geometry_game.player.x
	traveler.y = outskirts.geometry_game.player.y
	traveler.add_item("Beginner Rod",1)
	traveler.gold = 17
	outskirts.add_player("portal-traveler",traveler)
	var session := _session(14001,traveler,"outskirts")
	host.sessions[14001] = session
	spectator = PlayerState.new("Peer remaining in source")
	spectator.x = traveler.x
	spectator.y = traveler.y
	outskirts.add_player("source-spectator",spectator)
	spectator_position = spectator.get_position()
	var entrance := _portal(outskirts,"golem")
	check(entrance != null,"Actual outskirts cave portal is approved for Golem Kingdom")
	if entrance != null:
		var portal_id := str(outskirts.geometry_game.get_parent().get_path_to(entrance))
		var distant: Dictionary = await host._travel(session,portal_id)
		check(not distant.get("ok",false),"Portal travel checks actual range before moving a character")
	check(not (await host._travel(session,"forged/client-scene.tscn")).get("ok",false),"Unregistered client portal paths are rejected")
	await _travel_and_check(session,"golem")
	await _travel_and_check(session,"outskirts")
	await _travel_and_check(session,"tavern")
	await _travel_and_check(session,"outskirts")
	check(host.regions.size() == 3,"Travel reuses one shared region per approved map")
	check(http.requests.size() == 4,"Each successful travel persists exactly one destination state")
	await _retirement_during_destination_load(outskirts)
	host.queue_free()
	await get_tree().process_frame
	_finish()

func _session(peer: int, player: PlayerState, region_id: String) -> Dictionary:
	return {"peer":peer,"character_id":player.entity_id,"username":player.name,
		"lease_token":"isolated-lease-"+str(peer),"revision":0,"region_id":region_id,
		"player":player,"state":{},"hash":"","busy":false,"queue":[],"pending":{},
		"last_save":0,"heartbeat":0,"disconnected":0,"closing":false,
		"last_sequence":-1,"saving":false}

func _portal(region: AuthoritativeRegion, destination: String) -> CavePortal:
	var map: Node = region.geometry_game.get_parent()
	for candidate: Node in get_tree().get_nodes_in_group("cave_portal"):
		if candidate is CavePortal and map.is_ancestor_of(candidate) and preload("res://network/world_protocol.gd").region_for_scene(candidate.destination_scene) == destination:
			return candidate
	return null

func _simulation_position(geometry: Node, global_point: Vector2) -> Vector2:
	var local: Vector2 = geometry.to_local(global_point)
	return Vector2((local.x-geometry.map_origin.x)/32.0,(geometry.map_origin.y+geometry.map_height-local.y)/32.0)

func _seed_at_portal(region: AuthoritativeRegion, player: PlayerState, portal: CavePortal) -> void:
	# Test fixture setup occurs on the authoritative actor, never through a client command.
	var point := _simulation_position(region.geometry_game,portal.approach_position())
	player.x = point.x
	player.y = point.y
	player.current_target = ""
	player.in_combat = false
	var actor: CombatActor = region.world.combat.actors[player.entity_id]
	actor.x = point.x
	actor.y = point.y
	actor.current_target_id = ""
	region._sync_body(player.entity_id)

func _travel_and_check(session: Dictionary, destination: String) -> void:
	var source_id: String = session.region_id
	var source: AuthoritativeRegion = host.regions[source_id]
	var portal := _portal(source,destination)
	check(portal != null,"Real %s portal leads to %s" % [source_id,destination])
	if portal == null:
		return
	var player: PlayerState = session.player
	_seed_at_portal(source,player,portal)
	var portal_id := str(source.geometry_game.get_parent().get_path_to(portal))
	var result: Dictionary = await host._travel(session,portal_id)
	check(result.get("ok",false),"Server accepts real in-range portal %s to %s" % [source_id,destination])
	if not result.get("ok",false):
		return
	var target: AuthoritativeRegion = host.regions[destination]
	check(session.region_id == destination and session.player == player and player.entity_id == "portal-traveler","Travel keeps persistent character identity and the same PlayerState")
	check(target.players.get(player.entity_id) == player and target.world.players.get(player.entity_id) == player,"Destination is the only authoritative world owner")
	check(not source.players.has(player.entity_id) and not source.world.combat.actors.has(player.entity_id),"Source map retains no departed actor")
	var marker := target.geometry_game.get_parent().get_node("SpawnPoints/"+portal.destination_spawn_id) as Node2D
	var expected := _simulation_position(target.geometry_game,marker.global_position)
	check(player.get_position().distance_to(expected) <= 0.001,"Destination uses the real server-authored spawn marker")
	check(target.geometry_game.has_meta("online_server_geometry"),"Destination map runs in dedicated server geometry mode")
	check(await host._persist(session),"Fake account service durably acknowledges the travel snapshot")
	check(session.state.region_id == destination and session.state.x == player.x and session.state.y == player.y,"Acknowledged save contains destination region and marker coordinates")
	check(int(session.state.gold) == 17 and session.state.inventory.size() == 1,"Travel preserves gold and inventory")
	var owner_count := 0
	for region: AuthoritativeRegion in host.regions.values():
		if region.players.has(player.entity_id):
			owner_count += 1
	check(owner_count == 1,"Exactly one shared region owns the traveler after persistence")
	var outskirts: AuthoritativeRegion = host.regions.outskirts
	check(outskirts.players.get(spectator.entity_id) == spectator and spectator.get_position() == spectator_position,"Peer remaining in outskirts is unaffected by another player's travel")
	await get_tree().process_frame
	check(not source.geometry_game.actor_sprites.has(player.entity_id) and target.geometry_game.actor_sprites.has(player.entity_id),"Collision body registry follows travel without an orphan source body")

func _retirement_during_destination_load(outskirts: AuthoritativeRegion) -> void:
	var player := PlayerState.new("Retired traveler")
	player.x = outskirts.geometry_game.player.x
	player.y = outskirts.geometry_game.player.y
	outskirts.add_player("retired-traveler",player)
	var session := _session(14002,player,"outskirts")
	host.sessions[14002] = session
	var portal := _portal(outskirts,"tavern")
	_seed_at_portal(outskirts,player,portal)
	host.retire_during_destination = "tavern"
	host.retire_session = session
	var before := http.requests.size()
	var result: Dictionary = await host._travel(session,str(outskirts.geometry_game.get_parent().get_path_to(portal)))
	check(not result.get("ok",false) and session.get("retired",false),"Ownership loss during awaited destination load rejects stale travel")
	check(not host.sessions.has(14002),"Stale travel leaves no retired host session")
	for region: AuthoritativeRegion in host.regions.values():
		check(not region.players.has(player.entity_id) and not region.world.combat.actors.has(player.entity_id),"Stale travel cannot install a destination or orphan source actor")
	check(http.requests.size() == before,"Rejected stale travel never persists a replacement state")
	check(outskirts.players.get(spectator.entity_id) == spectator,"Stale travel does not affect the other source peer")

func _finish() -> void:
	print("[Online region travel] %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
