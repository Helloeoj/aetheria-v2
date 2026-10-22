extends Node
## Real scene transitions, pointer/context actions, stove UI and cooking transactions.
const OVERWORLD := "res://scenes/EastOutskirtsLayered.tscn"
const TAVERN := "res://scenes/TavernInterior.tscn"
var checks := 0
var failures: Array[String] = []
var game: Node
var capture_directory := ""

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("[Tavern FAIL] " + label)

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
	var event := InputEventMouseButton.new()
	event.position = screen
	event.global_position = screen
	event.button_index = button
	event.pressed = true
	get_tree().root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	get_tree().root.push_input(event)

func _button(root_node: Node, label: String) -> Button:
	for node: Node in root_node.find_children("*", "Button", true, false):
		if node.text == label:
			return node as Button
	return null

func _menu_action(label: String) -> void:
	var button := _button(game.context_menu, label)
	check(button != null, "context menu contains " + label)
	if button != null:
		button.pressed.emit()

func _settle_travel(path: String) -> void:
	var travel := get_node("/root/SceneTravel")
	var deadline := Time.get_ticks_msec() + 15000
	while travel.is_transitioning() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(not travel.is_transitioning() and get_tree().current_scene.scene_file_path == path, "transition completes at " + path.get_file())
	game = get_tree().current_scene.get_node("Combat")
	game.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().process_frame

func _walk_until_stopped() -> void:
	for step in range(240):
		if not game.interactions.walking:
			break
		game.interactions.update_walk(0.1)
		await get_tree().physics_frame
	game._update_map_camera()
	game.get_parent().get_node("MapCamera").force_update_scroll()

func _capture(filename: String) -> void:
	if capture_directory.is_empty():
		return
	game.queue_redraw()
	game.health_bar_layer.queue_redraw()
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	check(get_tree().root.get_texture().get_image().save_png(capture_directory.path_join(filename)) == OK, "capture " + filename)

func _run() -> void:
	check(ResourceLoader.exists(TAVERN), "approved tavern has its own playable scene")
	if not ResourceLoader.exists(TAVERN):
		_finish()
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			capture_directory = argument.trim_prefix("--output=")
	if not capture_directory.is_empty():
		DirAccess.make_dir_recursive_absolute(capture_directory)
	get_tree().root.size = Vector2i(1280, 720)
	var scene := (load(OVERWORLD) as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await get_tree().physics_frame
	await get_tree().process_frame
	game = scene.get_node("Combat")
	game.set_physics_process(false)
	var door: CavePortal = game.get_node_or_null("TavernEntrance")
	check(door != null, "existing overworld tavern has a door interaction")
	if door == null:
		_finish()
		return
	var player_ref: PlayerState = game.player
	game.player.add_item("Raw Reedkip", 3)
	game.player.set_skill_level("cooking", 21)
	game.player.gold = 47
	var before_inventory: Dictionary = game.player.backpack.duplicate(true)
	_place(door.approach_position() + Vector2(0, 60))
	_click(door.to_global(door.click_rect.get_center()), MOUSE_BUTTON_RIGHT)
	check(_button(game.context_menu, "Enter Tavern") != null, "door offers Enter Tavern")
	_menu_action("Walk here")
	await _walk_until_stopped()
	check(get_tree().current_scene == scene and not get_node("/root/SceneTravel").is_transitioning(), "Walk here approaches door without entering")
	await _capture("01-tavern-door.png")
	_click(door.to_global(door.click_rect.get_center()), MOUSE_BUTTON_LEFT)
	await _settle_travel(TAVERN)
	check(game.player == player_ref and game.player.gold == 47 and game.player.backpack == before_inventory, "entry retains exact player, inventory and gold")
	var spawn: Node2D = game.get_parent().get_node("SpawnPoints/Entrance")
	check(game.actor_sprites[game.player.entity_id].global_position.distance_to(spawn.global_position) < 0.1, "entry lands safely inside south door")
	check(game.actor_sprites[game.player.entity_id].animated_sprite.scale == Vector2(0.75, 0.75), "character retains native display scale")
	check(game.get_parent().get_node("TavernContent").scale == Vector2(0.75, 0.75), "interior matches character source-pixel density")
	check(game.get_parent().get_node("TavernContent/ApprovedArtwork").texture_filter == CanvasItem.TEXTURE_FILTER_PARENT_NODE, "art inherits the nearest-filtered content")
	var room: Node2D = game.get_parent()
	for source_point: Vector2 in [Vector2(776,200),Vector2(315,700),Vector2(900,750),Vector2(1145,242)]:
		check(not room.interaction_path(spawn.global_position,source_point * 0.75).is_empty(), "room route reaches " + str(source_point))
	game.interactions.walk_here(Vector2(776,200) * 0.75)
	await _walk_until_stopped()
	check(game.actor_sprites[game.player.entity_id].global_position.distance_to(Vector2(776,200) * 0.75) < 3, "physical walking reaches the bartender aisle")
	game.interactions.walk_here(spawn.global_position)
	await _walk_until_stopped()
	check(game.actor_sprites[game.player.entity_id].global_position.distance_to(spawn.global_position) < 3, "bartender aisle connects back to the common room")
	var query := PhysicsPointQueryParameters2D.new()
	query.collision_mask = 1
	query.position = Vector2(620,640) * 0.75
	check(not room.get_world_2d().direct_space_state.intersect_point(query).is_empty(), "hearth has actual physical collision")
	query.position = spawn.global_position
	check(room.get_world_2d().direct_space_state.intersect_point(query).is_empty(), "arrival marker is outside collision")
	var stove: Node2D = game.get_node("Stove")
	var controller: Node = game.cooking_controller
	controller.set_physics_process(false)
	controller.set_process(false)
	check(not controller.panel.visible, "Cooking starts closed")
	_click(stove.global_position, MOUSE_BUTTON_LEFT)
	check(game.interactions.walking and not controller.panel.visible, "distant stove queues a walk before opening Cooking")
	await _walk_until_stopped()
	check(controller.panel.visible, "left click walks around furniture and opens Cooking")
	var panel: Control = controller.panel
	check(_button(panel, "Cook 1") != null and _button(panel, "Cook all") != null, "Cooking provides real one/all buttons")
	var old_position: Vector2 = game.player.get_position()
	var move := InputEventKey.new()
	move.keycode = KEY_W
	move.pressed = true
	game._input(move)
	game._move_player(1.0)
	check(game.player.get_position() == old_position, "Cooking modal blocks movement input")
	var xp_before: int = game.player.get_skill_experience("cooking")
	_button(panel, "Cook 1").pressed.emit()
	check(panel.session != null and panel.session.state == CookingSession.State.COOKING, "Cook 1 starts existing timed CookingSession")
	check(int(game.player.backpack.get("Raw Reedkip", 0)) == 3, "starting cook spends no ingredient")
	controller.advance(3.01)
	check(panel.session.cooked_count == 0, "stove waits for a manual mastered flip")
	controller.flip()
	controller.advance(CookingSession.FEEDBACK_SECONDS)
	check(int(game.player.backpack.get("Raw Reedkip", 0)) == 2 and int(game.player.backpack.get("Reedkip", 0)) == 1, "stove transforms exactly one raw fish after heating and manual flip")
	check(game.player.get_skill_experience("cooking") == xp_before + 40, "successful stove cooking awards existing XP")
	_button(panel, "Cook all").pressed.emit()
	controller.advance(1.0)
	panel.close()
	controller.advance(10.0)
	check(int(game.player.backpack.get("Raw Reedkip", 0)) == 2 and game.player.active_cooking_session == null, "closing cancels unfinished cooking without ingredient loss")
	_click(stove.global_position, MOUSE_BUTTON_RIGHT)
	_menu_action("Walk here")
	await _walk_until_stopped()
	check(not panel.visible, "stove Walk here does not open Cooking")
	_click(stove.global_position, MOUSE_BUTTON_RIGHT)
	_menu_action("Cook at stove")
	_button(panel, "Cook all").pressed.emit()
	controller.advance(0.5)
	await _capture("03-stove-cooking-ui.png")
	for fish_index in range(2):
		controller.advance(3.0)
		controller.flip()
		controller.advance(CookingSession.FEEDBACK_SECONDS)
	check(int(game.player.backpack.get("Raw Reedkip", 0)) == 0 and int(game.player.backpack.get("Reedkip", 0)) == 3, "Cook all completes both remaining fish exactly once")
	check(game.player.get_skill_experience("cooking") == xp_before + 120, "Cook all records both successful rewards")
	check(panel.cook_one.disabled and panel.cook_all.disabled, "empty backpack disables cooking buttons")
	panel.close()
	_click(stove.global_position, MOUSE_BUTTON_RIGHT)
	_menu_action("Cook at stove")
	check(panel.visible, "right-click stove action opens Cooking")
	panel.close()
	var camera: Camera2D = game.get_parent().get_node("MapCamera")
	camera.zoom = Vector2.ONE * game.CAMERA_MAX_ZOOM
	_place(Vector2(900, 750) * 0.75)
	await _capture("04-max-zoom-character.png")
	camera.zoom = Vector2.ONE * 0.68
	camera.position = Vector2(627, 627) * 0.75
	camera.force_update_scroll()
	await _capture("02-interior-overview.png")
	camera.zoom = Vector2.ONE * 1.5
	var exit: CavePortal = game.get_node("TavernExit")
	_place(exit.approach_position())
	_click(exit.to_global(exit.click_rect.get_center()), MOUSE_BUTTON_RIGHT)
	_menu_action("Enter Valtheiris")
	await _settle_travel(OVERWORLD)
	check(game.player == player_ref and game.player.gold == 47, "return preserves the running character")
	var marker: Node2D = game.get_parent().get_node("SpawnPoints/TavernReturn")
	check(game.actor_sprites[game.player.entity_id].global_position.distance_to(marker.global_position) < 0.1, "return lands outside existing tavern")
	door = game.get_node("TavernEntrance")
	_click(door.to_global(door.click_rect.get_center()), MOUSE_BUTTON_RIGHT)
	_menu_action("Enter Tavern")
	await _settle_travel(TAVERN)
	check(not game.cooking_controller.panel.visible and game.player.active_cooking_session == null, "re-entry has no stale cooking UI/session")
	controller = game.cooking_controller
	controller.set_physics_process(false)
	controller.set_process(false)
	stove = game.get_node("Stove")
	game.player.add_item("Raw Reedkip", 1)
	_place(stove.approach_position())
	controller.open(stove)
	panel = controller.panel
	_button(panel, "Cook 1").pressed.emit()
	controller.advance(0.5)
	game.combat.actors[game.player.entity_id].hp -= 1
	controller.advance(0.5)
	check(panel.session.state == CookingSession.State.CANCELLED and int(game.player.backpack.get("Raw Reedkip", 0)) == 1, "damage cancels cooking without spending partial ingredient")
	panel.close()
	controller.open(stove)
	_button(panel, "Cook 1").pressed.emit()
	controller.advance(0.5)
	var old_stove_id: int = stove.get_instance_id()
	check(get_node("/root/SceneTravel").request_travel(game, OVERWORLD, "TavernReturn"), "scripted travel can close an active cooking panel")
	await _settle_travel(OVERWORLD)
	check(game.player.active_cooking_session == null and int(game.player.backpack.get("Raw Reedkip", 0)) == 1, "travel cancels unfinished cooking without spending fish")
	game.interactions._cooking_instance(old_stove_id)
	check(not game.cooking_controller.panel.visible, "stale stove callback cannot open Cooking in another area")
	_finish()

func _finish() -> void:
	print("[Tavern] %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
