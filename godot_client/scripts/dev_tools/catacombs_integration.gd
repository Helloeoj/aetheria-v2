extends Node
## Floor-one scene, actual pointer travel, player clearance and room routes.
const FLOOR := "res://scenes/CatacombsFloor01.tscn"
const KINGDOM := "res://scenes/GolemKingdom.tscn"
const ROOM_POINTS := {
	"Broken Processional Hall": Vector2(1300, 5680),
	"Split Foundry": Vector2(3520, 3830),
	"Basalt Excavation": Vector2(1000, 3190),
	"Abandoned Kiln Galleries": Vector2(1540, 1120),
	"Great Crucible Cavern": Vector2(5780, 3710),
	"Eastern Fracture Wing": Vector2(8200, 5370),
	"Northern Rift Galleries": Vector2(3980, 1810),
	"Deep Descent Approach": Vector2(7530, 1480),
}
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

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("[Catacombs FAIL] " + label)

func _run() -> void:
	_check(ResourceLoader.exists(FLOOR), "approved floor one is a playable area")
	if not ResourceLoader.exists(FLOOR):
		_finish()
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			capture_directory = argument.trim_prefix("--output=")
	if not capture_directory.is_empty():
		DirAccess.make_dir_recursive_absolute(capture_directory)
	get_tree().root.size = Vector2i(1280, 720)
	travel = get_node("/root/SceneTravel")
	var scene := (load(KINGDOM) as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await get_tree().physics_frame
	await get_tree().process_frame
	game = scene.get_node("Combat")
	game.set_physics_process(false)
	var door := game.get_node_or_null("CatacombsEntrance") as CavePortal
	_check(door != null, "existing kingdom southwest door offers catacombs entry")
	if door == null:
		_finish()
		return
	_check(door.global_position == Vector2(153, 2610), "entry uses referenced southwest door")
	_check(not _body_blocked(Vector2(255, 2745)), "kingdom return marker fits actual player body")
	player_ref = game.player
	training_ref = game.skill_training_session
	player_ref.add_item("Low Grade Fish Food", 7)
	player_ref.gold = 437
	player_ref.set_skill_level("attack", 12)
	player_ref.add_skill_experience("fishing", 125)
	player_ref.give_and_equip("Bronze Dagger")
	player_ref.current_hp = 73
	player_ref.current_mana = 11
	player_ref.cycle_known_spell(1)
	training_ref.record_event({"type": "skill_experience_gained", "skill": "fishing", "experience_gained": 49})
	game._refresh_player_actor_from_player()
	expected = {"hp": player_ref.current_hp, "mana": player_ref.current_mana, "gold": player_ref.gold,
		"backpack": player_ref.backpack.duplicate(true), "equipment": player_ref.equipment.duplicate(true),
		"quiver": player_ref.quiver_item.duplicate(true), "quiver_amount": player_ref.quiver_amount,
		"levels": player_ref.levels.duplicate(true), "xp": player_ref.skill_experience.duplicate(true),
		"spell": player_ref.selected_spell_id, "style": player_ref.attack_style}
	_place(door.approach_position() + Vector2(60, 0))
	_click(_portal_hit(door), MOUSE_BUTTON_RIGHT)
	await get_tree().process_frame
	_check(_menu_button("Enter Golem Catacombs") != null, "door provides real Enter context action")
	await _menu_action("Walk here")
	await _walk_until_stopped()
	_check(get_tree().current_scene == scene and not travel.is_transitioning(), "kingdom Walk here reaches door without entering")
	_check(door.is_in_interaction_range(game), "door approach is physically reachable")
	await _capture("01-kingdom-catacombs-door.png")
	_place(door.approach_position() + Vector2(84, 0))
	game.set_physics_process(true)
	_click(_portal_hit(door), MOUSE_BUTTON_LEFT)
	_check(game.interactions.walking and game.interactions.pending_portal == door, "distant left click queues an approach and entry intent")
	var entry_deadline := Time.get_ticks_msec() + 8000
	while not travel.is_transitioning() and Time.get_ticks_msec() < entry_deadline:
		await get_tree().physics_frame
	_check(travel.is_transitioning(), "normal physics walks the distant click into the loading transition")
	if not await _settle_travel(FLOOR):
		_finish()
		return
	_check_character("floor arrival")
	_check_marker("Entrance")
	var content: Node2D = game.get_parent().get_node("CatacombsFloor01Content")
	_check(content.scale == Vector2(0.75, 0.75), "native art and actor texture pixels have the same density")
	_check(game.actor_sprites[game.player.entity_id].animated_sprite.scale == Vector2(0.75, 0.75), "actor retains native display scale")
	for layer: String in ["Ground", "FloorDetails", "VolcanicRock", "Walls"]:
		_check(content.get_node_or_null(layer) is TileMapLayer, "editable terrain layer " + layer)
	var camera: Camera2D = game.get_parent().get_node("MapCamera")
	_check(camera.zoom == Vector2(3, 3), "floor starts at 3x zoom")
	game._zoom_map_camera(-100.0)
	_check(camera.zoom == Vector2(3, 3), "floor camera stops at 3x minimum")
	game._zoom_map_camera(100.0)
	_check(camera.zoom == Vector2(4, 4), "floor camera stops at 4x maximum")
	await _capture("02-floor-arrival-4x.png")
	game._zoom_map_camera(-100.0)
	await _capture("02b-floor-entrance-3x.png")
	var entry: Vector2 = game.get_parent().get_node("SpawnPoints/Entrance").global_position
	var exit: CavePortal = game.get_node("KingdomExit")
	for point: Vector2 in [Vector2(1464, 6792), Vector2(1656, 6792)]:
		_check(_body_blocked(point), "exit gateway post blocks actual player body " + str(point))
		_check(game.get_parent().interaction_path(entry, point).is_empty(), "navigation refuses exit gateway post " + str(point))
	_check(not _body_blocked(Vector2(1550, 6800)), "exit gateway opening fits actual player body")
	await _walk_to(Vector2(1550, 6800), "clear exit gateway opening")
	await _walk_to(entry, "visible arrival in front of gateway")
	_place(entry + Vector2(72, 0))
	_click(_portal_hit(exit), MOUSE_BUTTON_RIGHT)
	await get_tree().process_frame
	game.set_physics_process(true)
	await _menu_action("Walk here")
	await _walk_normal_until_stopped()
	game.set_physics_process(false)
	_check(get_tree().current_scene.scene_file_path == FLOOR and not travel.is_transitioning(), "floor exit Walk here never enters kingdom")
	_check(game.actor_sprites[game.player.entity_id].global_position.distance_to(entry) < 3.0, "real context button and normal physics reach floor exit approach")
	for label: String in ROOM_POINTS:
		var point: Vector2 = ROOM_POINTS[label]
		_check(not _body_blocked(point), "actual body fits " + label)
		_check(not game.get_parent().interaction_path(entry, point).is_empty(), "entry connects to " + label)
		await _walk_to(point, label)
		if label == "Great Crucible Cavern":
			await _capture("03-great-crucible-3x.png")
	for point: Vector2 in [Vector2(5550, 4290), Vector2(6980, 3530)]:
		_check(not _body_blocked(point), "removed island has no collision " + str(point))
		await _walk_to(point, "removed island " + str(point))
	for point: Vector2 in [Vector2(708, 5900), Vector2(4550, 1580), Vector2(1850, 5600)]:
		_check(_body_blocked(point), "rock or corner blocks actual body " + str(point))
		_check(game.get_parent().interaction_path(entry, point).is_empty(), "navigation refuses blocked destination " + str(point))
	for point: Vector2 in [Vector2(96, 96), Vector2(4780, 1630)]:
		_check(game.get_parent().interaction_path(entry, point).is_empty(), "navigation never enters enclosed rock interior " + str(point))
	var sprite := game.actor_sprites[game.player.entity_id] as CharacterBody2D
	_check(sprite.test_move(Transform2D(0, Vector2(780, 5900)), Vector2(-120, 0)), "actual collider cannot cross west rock boundary")
	_check(sprite.test_move(Transform2D(0, Vector2(1800, 5650)), Vector2(100, -100)), "actual collider cannot cut concave room corner")
	_place(Vector2(738, 5900))
	_check(not _body_blocked(Vector2(738, 5900)), "keyboard movement can leave body clear beside the conservative route margin")
	await _capture("03b-wall-clearance-3x.png")
	await _walk_to(Vector2(840, 5900), "safe recovery from route-margin boundary")
	await _walk_to(Vector2(738, 5900), "exact clear destination inside route margin")
	_check(_body_blocked(Vector2(726, 5900)), "nearby on-floor target overlaps the rock with actual player body")
	_check(game.get_parent().interaction_path(Vector2(840, 5900), Vector2(726, 5900)).is_empty(), "destination recovery refuses an endpoint overlapping rock")
	await _walk_to(Vector2(1800, 5650), "corner approach")
	await _walk_to(Vector2(1900, 5550), "safe route around concave corner")
	await _walk_to(Vector2(8210, 400), "sealed northeast descent")
	var sealed: Node2D = game.get_parent().get_node("SealedDescent")
	_check(sealed.global_position == Vector2(8210, 400), "future descent is at authored northeast point")
	_check(game.interactions.portals_at(sealed.global_position).is_empty(), "future descent cannot enter an unavailable floor")
	_click(sealed.global_position, MOUSE_BUTTON_RIGHT)
	await get_tree().process_frame
	_check(_menu_button("Walk here") != null, "sealed descent offers ordinary walking")
	for button: Node in game.context_menu.find_children("*", "Button", true, false):
		_check(not button.text.begins_with("Enter "), "sealed descent has no Enter option")
	game.context_menu.dismiss()
	await _capture("04-sealed-descent.png")
	await _walk_to(exit.approach_position(), "return to entrance")
	_click(_portal_hit(exit), MOUSE_BUTTON_RIGHT)
	await get_tree().process_frame
	await _menu_action("Enter Golem Kingdom")
	if not await _settle_travel(KINGDOM):
		_finish()
		return
	_check_character("kingdom return")
	_check_marker("CatacombsReturn")
	_check(not _body_blocked(Vector2(255, 2745)), "round trip returns outside kingdom collision")
	game._zoom_map_camera(-100.0)
	_check(game.get_parent().get_node("MapCamera").zoom == Vector2(1.5, 1.5), "kingdom retains existing camera minimum")
	await _capture("05-kingdom-return.png")
	_finish()

func _place(point: Vector2) -> void:
	var local: Vector2 = game.to_local(point)
	var actor: CombatActor = game.combat.actors[game.player.entity_id]
	actor.x = (local.x - game.map_origin.x) / game.TILE_SIZE
	actor.y = (game.map_origin.y + game.map_height - local.y) / game.TILE_SIZE
	game.player.x = actor.x
	game.player.y = actor.y
	game._update_sprite_position(actor.entity_id)
	game._update_map_camera()
	game.get_parent().get_node("MapCamera").force_update_scroll()

func _click(point: Vector2, button: MouseButton) -> void:
	var screen: Vector2 = game.get_global_transform_with_canvas() * game.to_local(point)
	_click_screen(screen, button)

func _click_screen(screen: Vector2, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.position = screen
	event.global_position = screen
	event.button_index = button
	event.pressed = true
	get_tree().root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	get_tree().root.push_input(event)

func _portal_hit(portal: CavePortal) -> Vector2:
	return portal.to_global(portal.click_rect.get_center())

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

func _settle_travel(path: String) -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	while travel.is_transitioning() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var arrived: bool = not travel.is_transitioning() and get_tree().current_scene.scene_file_path == path
	_check(arrived, "input transition completes at " + path.get_file())
	if arrived:
		game = get_tree().current_scene.get_node("Combat")
		game.set_physics_process(false)
		await get_tree().physics_frame
		await get_tree().process_frame
	return arrived

func _walk_until_stopped() -> void:
	for step in range(12000):
		if not game.interactions.walking:
			break
		game.interactions.update_walk(0.2)
		if step % 16 == 0:
			await get_tree().physics_frame
	game._update_map_camera()
	game.get_parent().get_node("MapCamera").force_update_scroll()

func _walk_normal_until_stopped() -> void:
	var deadline := Time.get_ticks_msec() + 8000
	while game.interactions.walking and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	_check(not game.interactions.walking, "normal physics completes the queued floor route")
	game._update_map_camera()
	game.get_parent().get_node("MapCamera").force_update_scroll()

func _walk_to(point: Vector2, label: String) -> void:
	game.interactions.walk_here(point)
	await _walk_until_stopped()
	var sprite: Node2D = game.actor_sprites[game.player.entity_id]
	_check(sprite.global_position.distance_to(point) < 3.0, "physical walking reaches " + label)

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
	_check(game.actor_sprites[game.player.entity_id].global_position.distance_to(marker.global_position) < 0.1, "arrival consumes authored " + id + " marker")
	_check(not _body_blocked(marker.global_position), "actual body is clear at " + id)

func _check_character(label: String) -> void:
	_check(game.player == player_ref and game.skill_training_session == training_ref, label + ": exact character and training references survive")
	_check(game.player.current_hp == expected.hp and game.player.current_mana == expected.mana, label + ": health and mana remain exact")
	_check(game.player.gold == expected.gold and game.player.backpack == expected.backpack, label + ": inventory and gold remain exact")
	_check(game.player.equipment == expected.equipment and game.player.quiver_item == expected.quiver and game.player.quiver_amount == expected.quiver_amount, label + ": equipment and quiver remain exact")
	_check(game.player.levels == expected.levels and game.player.skill_experience == expected.xp, label + ": skills and XP remain exact")
	_check(game.player.selected_spell_id == expected.spell and game.player.attack_style == expected.style, label + ": spell and style remain exact")
	_check(int(game.skill_training_session.get_progress("fishing").experience_gained) == 49, label + ": training XP remains exact")
	_check(not game.interactions.walking and travel.pending_spawn_id.is_empty(), label + ": old walking intent and spawn are cleared")

func _capture(filename: String) -> void:
	if capture_directory.is_empty():
		return
	game.queue_redraw()
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	_check(get_tree().root.get_texture().get_image().save_png(capture_directory.path_join(filename)) == OK, "capture " + filename)

func _finish() -> void:
	print("[Catacombs] %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
