extends Node
## Real portal input, character continuity and authoritative mine admission.
const MINE := "res://scenes/ValtherianMines.tscn"
const OUTSKIRTS := "res://scenes/EastOutskirtsLayered.tscn"
const Protocol := preload("res://network/world_protocol.gd")

class TestHost extends "res://network/world_host.gd":
	func _ready() -> void:
		set_physics_process(false)

class FakeAccountHTTP extends "res://network/account_http.gd":
	var requests: Array[Dictionary] = []
	func request_json(route: String, data: Dictionary = {}, _bearer: String = "", _key: String = "", _method: int = HTTPClient.METHOD_POST) -> Dictionary:
		requests.append({"route": route, "body": data.duplicate(true)})
		await get_tree().process_frame
		return {"ok": true, "revision": int(data.get("expected_revision", 0)) + 1}

var checks := 0
var failures: Array[String] = []
var game: Node
var travel: Node
var player_ref: PlayerState
var training_ref: SkillTrainingSession
var expected := {}
var capture_directory := ""

func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(150).timeout.connect(func() -> void:
		printerr("[Valtherian travel FAIL] Timed out")
		get_tree().quit(1))

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("[Valtherian travel FAIL] " + label)

func _run() -> void:
	_check(ResourceLoader.exists(MINE, "PackedScene"), "approved Valtherian Mines is a loadable playable scene")
	_check(Protocol.region_for_scene(MINE) == "valtherian_mines", "server recognizes the mine destination")
	if not ResourceLoader.exists(MINE, "PackedScene"):
		_finish()
		return
	if not _ore_probe_definitions_present():
		_finish()
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			capture_directory = argument.trim_prefix("--output=")
	if not capture_directory.is_empty():
		DirAccess.make_dir_recursive_absolute(capture_directory)
	get_tree().root.size = Vector2i(1280, 720)
	travel = get_node("/root/SceneTravel")
	var scene := (load(OUTSKIRTS) as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await _settle_map(scene)
	var door := game.get_node_or_null("ValtherianMinesEntrance") as CavePortal
	_check(door != null, "outskirts provides the new mine entrance")
	if door == null:
		_finish()
		return
	_check(door.destination_scene == MINE and door.destination_spawn_id == "Entrance", "mine entrance resolves to the mine arrival")
	var golem := game.get_node("GolemCaveEntrance") as CavePortal
	_check(golem.destination_scene == "res://scenes/GolemKingdom.tscn" and golem.global_position == Vector2(128, -2520), "existing Golem entrance and destination remain intact")
	var original_mine := game.get_node("BrackenMineEntrance") as CavePortal
	_check(original_mine.destination_scene == "res://scenes/BrackenMine.tscn" and original_mine.global_position == Vector2(672,-96), "existing Bracken entrance remains exact")
	_check(scene.get_node("SpawnPoints/BrackenMineReturn").global_position == Vector2(672,0), "existing Bracken return remains exact")
	var native_prop: Node2D = scene.get_node("PlayableMapContent/ValtherianMinesEntranceProp")
	var native_art: Sprite2D = native_prop.get_node("Artwork")
	_check(native_prop.global_position == Vector2(320,-1) and native_art.global_position == Vector2(173,-140), "east-facing entrance retains the reviewed native placement and anchor")
	_check(native_art.texture.get_size() == Vector2(256,192) and native_art.global_scale == Vector2.ONE, "entrance source stays native256x192 atscale1")
	_check(door.get_child_count() == 0 and door.global_position == native_prop.global_position, "scripted portal stays artless while actual passive content owns artwork and collision")
	_check(door.approach_position() == Vector2(368,16), "entrance approach remains east of the mouth")
	_check(not _body_blocked(door.approach_position()), "east-side exact approach fits the actual player body")
	var return_point: Vector2 = scene.get_node("SpawnPoints/ValtherianMinesReturn").global_position
	_check(not _body_blocked(return_point), "overworld return marker fits the real actor body")
	_check(game.world.grid != null, "overworld retains audited shared grid with new entrance")
	if game.world.grid != null:
		_check(not game.world.grid.path(game.player.get_position(), game.grid_adapter.simulation_point(return_point)).is_empty(), "existing player route reaches the new mine approach")
	player_ref = game.player
	training_ref = game.skill_training_session
	player_ref.add_item("Low Grade Fish Food", 7)
	player_ref.gold = 437
	player_ref.set_skill_level("attack", 12)
	player_ref.add_skill_experience("fishing", 125)
	player_ref.give_and_equip("Bronze Dagger")
	player_ref.current_hp = 73
	player_ref.current_mana = 11
	training_ref.record_event({"type": "skill_experience_gained", "skill": "fishing", "experience_gained": 49})
	game._refresh_player_actor_from_player()
	expected = {"hp": player_ref.current_hp, "mana": player_ref.current_mana, "gold": player_ref.gold,
		"backpack": player_ref.backpack.duplicate(true), "equipment": player_ref.equipment.duplicate(true),
		"levels": player_ref.levels.duplicate(true), "xp": player_ref.skill_experience.duplicate(true),
		"spell": player_ref.selected_spell_id, "style": player_ref.attack_style}
	_place(return_point)
	_click(door.to_global(Vector2(0, -52)), MOUSE_BUTTON_RIGHT)
	await get_tree().process_frame
	_check(_menu_button("Enter Valtherian Mines") != null, "mine art offers the real Enter context action")
	await _menu_action("Walk here")
	await _walk_until_stopped()
	_check(get_tree().current_scene == scene and not travel.is_transitioning(), "walking onto the mine entrance does not trigger travel")
	await _capture("01-overworld-mine-entrance.png")
	_place(return_point + Vector2(0, 96))
	game.set_physics_process(true)
	_click(door.to_global(Vector2(0, -52)), MOUSE_BUTTON_LEFT)
	_check(game.interactions.walking and game.interactions.pending_portal == door, "distant mine click queues walking with entry intent")
	var deadline := Time.get_ticks_msec() + 8000
	while not travel.is_transitioning() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	_check(travel.is_transitioning(), "normal movement reaches mine interaction range")
	if not await _settle_travel(MINE):
		_finish()
		return
	_check_character("mine arrival")
	_check_marker("Entrance")
	_check(game.world.grid != null, "mine adopts the same audited hidden movement grid")
	_check(int(game.grid_adapter.report.get("checks",0)) >= 70, "runtime adoption covers all room, route and29ore-approach probes")
	_check_exact_ore_approaches()
	_check(game.get_parent().get_node("ValtherianMinesContent").transform == Transform2D.IDENTITY, "mine artwork remains at native world scale")
	var exit := game.get_node_or_null("OutskirtsExit") as CavePortal
	_check(exit != null and exit.destination_scene == OUTSKIRTS and exit.destination_spawn_id == "ValtherianMinesReturn", "mine exit returns to its reciprocal overworld marker")
	if exit == null:
		_finish()
		return
	_check(not _body_blocked(exit.approach_position()), "mine exit approach fits the real actor body")
	game._zoom_map_camera(100.0)
	_check(game.get_parent().get_node("MapCamera").zoom == Vector2(4, 4), "mine supports existing maximum 4x zoom")
	await _capture("02-mine-arrival-4x.png")
	game._zoom_map_camera(-100.0)
	_place(exit.approach_position())
	_click(exit.to_global(exit.click_rect.get_center()), MOUSE_BUTTON_RIGHT)
	await get_tree().process_frame
	await _menu_action("Enter Valtheiris")
	if not await _settle_travel(OUTSKIRTS):
		_finish()
		return
	_check_character("overworld return")
	_check_marker("ValtherianMinesReturn")
	await _capture("03-overworld-mine-return.png")
	await _check_authoritative_round_trip()
	_finish()

func _ore_layout() -> Array:
	var layout:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://Assets/Maps/ValtherianMines/layout.json"))
	return layout.get("ores",[])

func _ore_probe_definitions_present() -> bool:
	var state:SceneState=(load(MINE) as PackedScene).get_state()
	var positions:Dictionary={}
	for index in range(state.get_node_count()):
		var path:String=str(state.get_node_path(index)).trim_prefix("./")
		if not path.begins_with("GridProbes/OreApproach"):
			continue
		for property in range(state.get_node_property_count(index)):
			if state.get_node_property_name(index,property)==&"position":
				positions[path]=state.get_node_property_value(index,property)
	var ores:=_ore_layout()
	_check(ores.size()==29, "the approved marker layout contains exactly29ore nodes")
	var present:=ores.size()==29
	for ore:Dictionary in ores:
		var path:String="GridProbes/OreApproach"+str(ore.name)
		var point:Array=ore.approach_world_xy
		var expected_point:=Vector2(point[0],point[1])
		var exact:bool=positions.has(path) and positions[path]==expected_point
		_check(exact,"wrapper pins exact ore approach: "+str(ore.id))
		present=present and exact
	return present

func _check_exact_ore_approaches() -> void:
	for ore:Dictionary in _ore_layout():
		var marker:Node2D=game.get_parent().get_node("GridProbes/OreApproach"+str(ore.name))
		var point:Vector2=marker.global_position
		_check(not _body_blocked(point),"actual24px body clears exact ore approach: "+str(ore.id))
		var target:Vector2=game.grid_adapter.simulation_point(point)
		var route:PackedVector2Array=game.world.grid.path(game.player.get_position(),target)
		_check(not route.is_empty() and route[-1].is_equal_approx(target),"shared-grid path reaches exact ore approach: "+str(ore.id))

func _settle_map(scene: Node) -> void:
	game = scene.get_node("Combat")
	game.set_physics_process(false)
	for frame in range(120):
		await get_tree().physics_frame
		if game.grid_adapter != null and game.grid_adapter.completed:
			break
	await get_tree().process_frame

func _settle_travel(path: String) -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	while travel.is_transitioning() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var arrived: bool = not travel.is_transitioning() and get_tree().current_scene.scene_file_path == path
	_check(arrived, "portal input completes transition to " + path.get_file())
	if arrived:
		await _settle_map(get_tree().current_scene)
	return arrived

func _place(point: Vector2) -> void:
	var local: Vector2 = game.to_local(point)
	var actor: CombatActor = game.combat.actors[game.player.entity_id]
	var simulation := Vector2((local.x - game.map_origin.x) / game.TILE_SIZE,
		(game.map_origin.y + game.map_height - local.y) / game.TILE_SIZE)
	if game.world.grid != null:
		simulation = GridPlacement.resolve(game.world.grid, simulation)
		_check(simulation.is_finite(), "test placement resolves through a safe shared-grid center")
		if not simulation.is_finite():
			return
	actor.x = simulation.x
	actor.y = simulation.y
	game.player.x = actor.x
	game.player.y = actor.y
	game.world.grid_travellers.erase(actor.entity_id)
	game.world.grid_traveller(actor.entity_id)
	game._update_sprite_position(actor.entity_id)
	game._update_map_camera()
	game.get_parent().get_node("MapCamera").force_update_scroll()

func _click(point: Vector2, button: MouseButton) -> void:
	_click_screen(game.get_global_transform_with_canvas() * game.to_local(point), button)

func _click_screen(point: Vector2, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = true
	get_tree().root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	get_tree().root.push_input(event)

func _menu_button(label: String) -> Button:
	for node: Node in game.context_menu.find_children("*", "Button", true, false):
		if node.text == label:
			return node as Button
	return null

func _menu_action(label: String) -> void:
	var button := _menu_button(label)
	_check(button != null, "context menu contains " + label)
	if button != null:
		_click_screen(button.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
		await get_tree().process_frame

func _walk_until_stopped() -> void:
	for step in range(1000):
		if not game.interactions.walking:
			break
		game.interactions.update_walk(0.2)
		if step % 16 == 0:
			await get_tree().physics_frame

func _body_blocked(point: Vector2) -> bool:
	var sprite := game.actor_sprites[game.player.entity_id] as CharacterBody2D
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = sprite.get_node("BodyCollision").shape
	query.transform = Transform2D(0, point)
	query.collision_mask = 1
	query.exclude = [sprite.get_rid()]
	return not sprite.get_world_2d().direct_space_state.intersect_shape(query).is_empty()

func _check_marker(id: String) -> void:
	var marker: Node2D = game.get_parent().get_node("SpawnPoints/" + id)
	var sprite: Node2D = game.actor_sprites[game.player.entity_id]
	_check(sprite.global_position.distance_to(marker.global_position) <= 24.0, "arrival resolves beside authored " + id + " marker")
	_check(not _body_blocked(sprite.global_position), "actual arrival body is clear at " + id)

func _check_character(label: String) -> void:
	_check(game.player == player_ref and game.skill_training_session == training_ref, label + ": exact character and training references survive")
	_check(game.player.current_hp == expected.hp and game.player.current_mana == expected.mana, label + ": health and mana remain exact")
	_check(game.player.gold == expected.gold and game.player.backpack == expected.backpack, label + ": inventory and gold remain exact")
	_check(game.player.equipment == expected.equipment and game.player.levels == expected.levels and game.player.skill_experience == expected.xp, label + ": equipment and progression remain exact")
	_check(game.player.selected_spell_id == expected.spell and game.player.attack_style == expected.style, label + ": selected combat controls remain exact")
	_check(int(game.skill_training_session.get_progress("fishing").experience_gained) == 49, label + ": session XP remains exact")
	_check(not game.interactions.walking and travel.pending_spawn_id.is_empty(), label + ": previous movement intent is cleared")

func _check_authoritative_round_trip() -> void:
	var host := TestHost.new()
	add_child(host)
	var http := FakeAccountHTTP.new()
	host.add_child(http)
	host._http = http
	host._key = "isolated-valtherian-travel-fixture"
	var outskirts: AuthoritativeRegion = await host._get_region("outskirts")
	var traveler := PlayerState.new("Mine server traveler")
	traveler.gold = 19
	traveler.add_item("Beginner Rod", 1)
	traveler.x = outskirts.geometry_game.player.x
	traveler.y = outskirts.geometry_game.player.y
	outskirts.add_player("mine-server-traveler", traveler)
	var session := {"peer": 14101, "character_id": traveler.entity_id, "username": traveler.name,
		"lease_token": "isolated-mine-lease", "revision": 0, "region_id": "outskirts",
		"player": traveler, "state": {}, "hash": "", "busy": false, "queue": [], "pending": {},
		"last_save": 0, "heartbeat": 0, "disconnected": 0, "closing": false,
		"last_sequence": -1, "saving": false}
	host.sessions[14101] = session
	for destination: String in ["valtherian_mines", "outskirts"]:
		var source: AuthoritativeRegion = host.regions[session.region_id]
		var map: Node = source.geometry_game.get_parent()
		var portal: CavePortal
		for candidate: Node in get_tree().get_nodes_in_group("cave_portal"):
			if map.is_ancestor_of(candidate) and Protocol.region_for_scene(candidate.destination_scene) == destination:
				portal = candidate as CavePortal
		_check(portal != null, "authoritative source registers real portal to " + destination)
		if portal == null:
			break
		var portal_id := str(map.get_path_to(portal))
		var target_point: Vector2 = source.geometry_game.grid_adapter.simulation_point(portal.approach_position())
		_check(source.world.grid != null, "authoritative source uses physics-audited shared grid")
		if source.world.grid != null:
			var route := source.world.grid.path(traveler.get_position(), target_point, portal.interaction_radius / 32.0)
			_check(not route.is_empty(), "server actor has a checked route to " + destination)
			if route.is_empty():
				break
			target_point = route[-1]
		traveler.x = target_point.x
		traveler.y = target_point.y
		var actor: CombatActor = source.world.combat.actors[traveler.entity_id]
		actor.x = target_point.x
		actor.y = target_point.y
		source.world.grid_traveller(traveler.entity_id)
		source._sync_body(traveler.entity_id)
		var result: Dictionary = await host._travel(session, portal_id)
		_check(result.get("ok", false), "server accepts in-range real portal to " + destination)
		if not result.get("ok", false):
			break
		var target: AuthoritativeRegion = host.regions[destination]
		_check(session.region_id == destination and target.players.get(traveler.entity_id) == traveler and not source.players.has(traveler.entity_id), "server moves one persistent actor into " + destination)
		_check(target.world.grid != null and target.world.grid.is_center(traveler.get_position()) and target.world.grid.clear_point(traveler.get_position()), "server arrival is a clear shared-grid center")
		_check(await host._persist(session), "account persistence acknowledges " + destination)
		_check(session.state.region_id == destination and session.state.x == traveler.x and session.state.y == traveler.y and session.state.gold == 19 and session.state.inventory.size() == 1, "saved region, arrival and inventory match authoritative " + destination)
	host.queue_free()
	await get_tree().process_frame

func _capture(filename: String) -> void:
	if capture_directory.is_empty():
		return
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	_check(get_tree().root.get_texture().get_image().save_png(capture_directory.path_join(filename)) == OK, "capture " + filename)

func _finish() -> void:
	print("[Valtherian travel] %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
