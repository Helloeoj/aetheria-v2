extends Node
## Real map, physics, pointer dispatch and area-loading roundtrips.
## Optional rendering: -- --capture --output=<absolute evidence directory>

const OVERWORLD := "res://scenes/EastOutskirtsLayered.tscn"
const DUNGEON := "res://scenes/GolemKingdom.tscn"

var checks := 0
var failures: Array[String] = []
var game: Node
var travel: Node
var player_ref: PlayerState
var training_ref: SkillTrainingSession
var expected := {}
var finished_count := 0
var last_destination := ""
var capture_directory := ""


func _ready() -> void:
	_run.call_deferred()


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("[Golem portal FAIL] ", label)


func _click(screen_point: Vector2, button: MouseButton) -> void:
	var viewport := get_tree().root
	var motion := InputEventMouseMotion.new()
	motion.position = screen_point
	motion.global_position = screen_point
	viewport.push_input(motion)
	var event := InputEventMouseButton.new()
	event.position = screen_point
	event.global_position = screen_point
	event.button_index = button
	event.pressed = true
	viewport.push_input(event)
	var release := InputEventMouseButton.new()
	release.position = screen_point
	release.global_position = screen_point
	release.button_index = button
	viewport.push_input(release)


func _screen(world_point: Vector2) -> Vector2:
	return game.get_global_transform_with_canvas() * game.to_local(world_point)


func _portal_hit(portal: CavePortal) -> Vector2:
	if portal.contains_global_point(portal.global_position):
		return portal.global_position
	if portal.hit_polygon.size() >= 3:
		var center := Vector2.ZERO
		for point: Vector2 in portal.hit_polygon:
			center += point
		center /= portal.hit_polygon.size()
		return portal.to_global(center)
	return portal.to_global(portal.click_rect.get_center())


func _menu_button(label: String) -> Button:
	for candidate: Node in game.context_menu.find_children("*", "Button", true, false):
		if candidate.text == label:
			return candidate as Button
	return null


func _place_player(world_point: Vector2) -> void:
	var local_point: Vector2 = game.to_local(world_point)
	var actor: CombatActor = game.combat.actors[game.player.entity_id]
	actor.x = (local_point.x - game.map_origin.x) / game.TILE_SIZE
	actor.y = (game.map_origin.y + game.map_height - local_point.y) / game.TILE_SIZE
	game.player.x = actor.x
	game.player.y = actor.y
	game._update_sprite_position(actor.entity_id)
	game._update_map_camera()
	var camera := game.get_parent().get_node("MapCamera") as Camera2D
	camera.force_update_scroll()


func _on_finished(destination: String) -> void:
	finished_count += 1
	last_destination = destination


func _await_transition(previous_count: int, destination: String) -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	while finished_count <= previous_count and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var completed := finished_count == previous_count + 1 and last_destination == destination
	_check(completed, "one transition finishes at " + destination.get_file())
	if completed:
		game = get_tree().current_scene.get_node("Combat")
		await get_tree().physics_frame
		await get_tree().process_frame
	return completed


func _capture(filename: String, settle_frames: int = 2) -> void:
	if capture_directory.is_empty():
		return
	for frame in range(settle_frames):
		await get_tree().process_frame
	RenderingServer.force_draw(false)
	var error := get_tree().root.get_texture().get_image().save_png(capture_directory.path_join(filename))
	_check(error == OK, "writes rendered evidence " + filename)


func _capture_loading() -> void:
	if capture_directory.is_empty():
		return
	var deadline := Time.get_ticks_msec() + 1000
	while travel.is_transitioning() and travel.get("_cover").modulate.a < 0.9 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await _capture("03-loading.png", 0)


func _check_character(label: String) -> void:
	_check(game.player == player_ref and game.skill_training_session == training_ref, label + ": exact character and training references survive")
	_check(game.player.current_hp == expected.hp and game.player.current_mana == expected.mana, label + ": health and mana do not refill")
	_check(game.player.gold == expected.gold and game.player.backpack == expected.backpack, label + ": gold, stacks and starter kit remain exact")
	_check(game.player.equipment == expected.equipment and game.player.quiver_item == expected.quiver and game.player.quiver_amount == expected.quiver_amount, label + ": equipment and quiver remain exact")
	_check(game.player.levels == expected.levels and game.player.skill_experience == expected.xp, label + ": skill levels and XP remain exact")
	_check(game.player.selected_spell_id == expected.spell and game.player.attack_style == expected.style, label + ": selected spell and attack style survive")
	_check(int(game.skill_training_session.get_progress("fishing").experience_gained) == expected.session_xp, label + ": earned session XP survives")
	_check(game.player.current_target.is_empty() and not game.player.in_combat and not game.auto_chase_target, label + ": old combat intent is cleared")
	_check(game.movement_controller.get_move_vector().is_zero_approx() and not game.interactions.walking and not game.spell_cast_requested, label + ": held movement, queued walking and spell requests are cleared")
	var sprite: Node2D = game.actor_sprites[game.player.entity_id]
	var camera := game.get_parent().get_node("MapCamera") as Camera2D
	_check(camera.enabled and camera.global_position.distance_to(sprite.global_position) < 0.1, label + ": active camera follows the arriving player")
	_check(travel.pending_spawn_id.is_empty(), label + ": pending spawn is consumed")
	_check(not game.skill_debug_panel.visible, label + ": practice tools do not obscure the arrival or doorway")


func _check_marker(marker_name: String, label: String) -> void:
	var marker := game.get_parent().get_node("SpawnPoints/" + marker_name) as Node2D
	var sprite: Node2D = game.actor_sprites[game.player.entity_id]
	_check(sprite.global_position.distance_to(marker.global_position) < 0.1, label + ": player lands exactly on the authored marker")


func _run() -> void:
	var tree := get_tree()
	tree.root.size = Vector2i(1280, 720)
	var args := OS.get_cmdline_user_args()
	if "--capture" in args:
		for argument: String in args:
			if argument.begins_with("--output="):
				capture_directory = argument.trim_prefix("--output=")
		_check(capture_directory.is_absolute_path(), "capture output is an explicit absolute directory")
		if not capture_directory.is_absolute_path():
			_finish()
			return
		DirAccess.make_dir_recursive_absolute(capture_directory)
	travel = tree.root.get_node("SceneTravel")
	travel.transition_finished.connect(_on_finished)
	var scene := (load(OVERWORLD) as PackedScene).instantiate()
	tree.root.add_child(scene)
	tree.current_scene = scene
	await tree.process_frame
	await tree.physics_frame
	game = scene.get_node("Combat")
	_check(not game.skill_debug_panel.visible, "practice tools start closed")
	var entrance := game.get_node_or_null("GolemCaveEntrance") as CavePortal
	_check(entrance != null, "overworld has the authored cave entrance")
	if entrance == null:
		_finish()
		return
	_check(entrance.destination_scene == DUNGEON and entrance.destination_spawn_id == "EastCave", "entrance targets the independent dungeon scene")
	_check(scene.get_node_or_null("SpawnPoints/GolemCaveReturn") != null, "overworld has a safe return marker")
	player_ref = game.player
	training_ref = game.skill_training_session
	player_ref.set_skill_level("attack", 12)
	player_ref.set_skill_level("magic", 3)
	player_ref.add_skill_experience("fishing", 125)
	player_ref.give_and_equip("Bronze Dagger")
	player_ref.add_item("Low Grade Fish Food", 7)
	player_ref.gold = 437
	player_ref.current_hp = 73
	player_ref.current_mana = 11
	player_ref.cycle_known_spell(1)
	training_ref.record_event({"type": "skill_experience_gained", "skill": "fishing", "experience_gained": 49})
	game._refresh_player_actor_from_player()
	expected = {"hp": player_ref.current_hp, "mana": player_ref.current_mana, "gold": player_ref.gold,
		"backpack": player_ref.backpack.duplicate(true), "equipment": player_ref.equipment.duplicate(true),
		"quiver": player_ref.quiver_item.duplicate(true), "quiver_amount": player_ref.quiver_amount,
		"levels": player_ref.levels.duplicate(true), "xp": player_ref.skill_experience.duplicate(true),
		"spell": player_ref.selected_spell_id, "style": player_ref.attack_style, "session_xp": 49}
	_place_player(entrance.approach_position())
	await tree.physics_frame
	await _capture("01-overworld-entrance.png")
	var hit := _portal_hit(entrance)
	_check(entrance.contains_global_point(hit), "test pointer lands on the visible doorway")
	_click(_screen(hit), MOUSE_BUTTON_RIGHT)
	await tree.process_frame
	_check(game.context_menu.visible and _menu_button("Enter Golem Kingdom") != null and _menu_button("Walk here") != null, "overworld right-click exposes Enter Golem Kingdom and Walk here")
	await _capture("02-overworld-menu.png")
	game.context_menu.dismiss()
	game.movement_controller.on_input("w", true)
	game.player.current_target = "old-area-target"
	game.player.in_combat = true
	game.auto_chase_target = true
	game.spell_cast_requested = true
	var before := finished_count
	_click(_screen(hit), MOUSE_BUTTON_LEFT)
	_check(travel.is_transitioning(), "left-click at the doorway quick-enters")
	_check(game.movement_controller.get_move_vector().is_zero_approx() and not game.interactions.walking and not game.spell_cast_requested, "leaving cancels held movement, walking and requested casts immediately")
	await _capture_loading()
	if not await _await_transition(before, DUNGEON):
		_finish()
		return
	_check_character("first dungeon arrival")
	_check_marker("EastCave", "first dungeon arrival")
	await _capture("04-dungeon-arrival.png")
	var exit := game.get_node("EastCaveExit") as CavePortal
	_check(exit.destination_scene == OVERWORLD and exit.destination_spawn_id == "GolemCaveReturn", "dungeon exit returns to the matching cave")
	hit = _portal_hit(exit)
	_click(_screen(hit), MOUSE_BUTTON_RIGHT)
	await tree.process_frame
	_check(game.context_menu.visible and _menu_button("Enter Valtheiris") != null and _menu_button("Walk here") != null, "dungeon right-click exposes Enter Valtheiris and Walk here")
	await _capture("05-dungeon-exit-menu.png")
	var walk_button := _menu_button("Walk here")
	if walk_button != null:
		_click(walk_button.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	_check(game.interactions.walking and game.interactions.pending_portal == null, "Walk here queues ordinary walking without travel intent")
	var walk_start: Vector2 = game.actor_sprites[game.player.entity_id].global_position
	before = finished_count
	var walk_deadline := Time.get_ticks_msec() + 5000
	while game.interactions.walking and Time.get_ticks_msec() < walk_deadline:
		await tree.physics_frame
	_check(game.actor_sprites[game.player.entity_id].global_position.distance_to(walk_start) > 30.0, "Walk here physically moves along the cave path with real collisions")
	_check(not game.interactions.walking and not travel.is_transitioning() and finished_count == before and tree.current_scene.scene_file_path == DUNGEON, "walking up to the doorway never changes scenes")
	_check(exit.is_in_interaction_range(game), "authored dungeon exit approach is reachable")
	_click(_screen(_portal_hit(exit)), MOUSE_BUTTON_RIGHT)
	await tree.process_frame
	var enter_button := _menu_button("Enter Valtheiris")
	_check(enter_button != null, "return action is a real clickable menu button")
	if enter_button != null:
		_click(enter_button.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	if not await _await_transition(before, OVERWORLD):
		_finish()
		return
	_check_character("first overworld return")
	_check_marker("GolemCaveReturn", "first overworld return")
	await _capture("06-overworld-return.png")
	entrance = game.get_node("GolemCaveEntrance") as CavePortal
	var actor: CombatActor = game.combat.actors[game.player.entity_id]
	actor.hp = 0
	actor.is_alive = false
	game.player.current_hp = 0
	_click(_screen(_portal_hit(entrance)), MOUSE_BUTTON_LEFT)
	_check(not travel.is_transitioning() and not game.interactions.walking, "dead player cannot enter or queue travel")
	actor.hp = int(expected.hp)
	actor.is_alive = true
	game.player.current_hp = int(expected.hp)
	# A second full roundtrip catches coordinate offsets or starter items applied twice.
	before = finished_count
	_click(_screen(_portal_hit(entrance)), MOUSE_BUTTON_LEFT)
	if not await _await_transition(before, DUNGEON):
		_finish()
		return
	_check_character("second dungeon arrival")
	_check_marker("EastCave", "second dungeon arrival")
	exit = game.get_node("EastCaveExit") as CavePortal
	before = finished_count
	_click(_screen(_portal_hit(exit)), MOUSE_BUTTON_LEFT)
	_check(game.interactions.walking or travel.is_transitioning(), "distant left-click queues approach and enter")
	if not await _await_transition(before, OVERWORLD):
		_finish()
		return
	_check_character("second overworld return")
	_check_marker("GolemCaveReturn", "second overworld return")
	_check(finished_count == 4, "two roundtrips complete exactly four scene loads")
	_finish()


func _finish() -> void:
	print("[Golem portal] %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
