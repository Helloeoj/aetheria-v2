extends SceneTree
## Exercise the actual map input route and its scaled online activity overlay.
class CommandSink extends Node:
	var latest_snapshot: Dictionary = {}
	var commands: Array[Dictionary] = []
	func send_action(command: Dictionary) -> bool:
		commands.append(command)
		return true

var failures: Array[String] = []
var checks := 0
var capture_directory := ""
var click_trace: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("[Online activity input FAIL] ", label)

func _initialize() -> void:
	_run.call_deferred()

func frames(count: int = 4) -> void:
	for _index in range(count):
		await process_frame

func key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event)
		await frames()

func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	click_trace = [{"point": point, "root_size": root.size, "viewport": root.get_visible_rect()}]
	var observe := func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			click_trace.append({"gui_pressed": event.pressed, "position": event.position})
	control.gui_input.connect(observe)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	await frames()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		root.push_input(event)
		await frames()
		var hovered := root.gui_get_hovered_control()
		click_trace.append({"pressed": pressed, "rect": control.get_global_rect(), "hovered": str(hovered.get_path()) if hovered != null else "none"})
	control.gui_input.disconnect(observe)

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_directory = argument.trim_prefix("--capture=")
			DirAccess.make_dir_recursive_absolute(capture_directory)
	root.size = Vector2i(1280, 720)
	var network: Node = root.get_node("Network")
	network.set_process(false)
	network.auto_scene = false
	var scene: Node = load("res://scenes/EastOutskirtsLayered.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await frames(8)
	var game: Node = scene.get_node("Combat")
	while game.grid_adapter == null or not game.grid_adapter.completed:
		await physics_frame
	network.mode = network.Mode.CLIENT
	network.authenticated = true
	game.online_view = load("res://network/online_world_view.gd").new()
	game.add_child(game.online_view)
	game.online_view.configure(game)
	var panel: Control = game.online_view.activity_panel
	var sink := CommandSink.new()
	root.add_child(sink)
	game.player.add_item("Beginner Rod", 1)
	game.player.add_item("Low Grade Fish Food", 2)
	game.player.fishing_pale[3] = "Raw Reedkip"
	var spots: Array = game.fishing_spots()
	check(not spots.is_empty(), "Map provides a real fishing station")
	if spots.is_empty():
		quit(1)
		return
	var shore: Vector2 = game.interactions._simulation_position(spots[0].shore_position())
	var route: PackedVector2Array = game.world.grid.path(game.player.get_position(),shore,spots[0].interact_radius/game.TILE_SIZE)
	check(not route.is_empty(),"Scaled online activity input fixture has an arrived shore center")
	if route.is_empty():
		quit(1)
		return
	var actor: CombatActor = game.combat.actors[game.player.entity_id]
	actor.x = route[-1].x
	actor.y = route[-1].y
	game.player.x = actor.x
	game.player.y = actor.y
	game.world.grid_traveller(actor.entity_id)
	game._update_sprite_position(actor.entity_id)
	var social: Node = root.get_node("Social")
	var original_ui_layer: int = game.get_node("UI").layer
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(2560, 1440), Vector2i(3840, 2160)]:
		root.size = dimensions
		game._update_ui_scale()
		social.update_layout()
		await frames()
		game.character_menu_button.focus_mode = Control.FOCUS_ALL
		game.character_menu_button.grab_focus()
		sink.latest_snapshot = {}
		await key(KEY_F)
		panel.session.transport = sink
		check(panel.visible, "Native F opens online fishing at %s" % dimensions)
		check(game.get_node("UI").layer > social.get_node("SocialOverlay").layer, "Activity controls draw above persistent chat at %s" % dimensions)
		await frames(10)
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(panel.get_global_rect()), "Fishing controls fit scaled viewport at %s" % dimensions)
		if not capture_directory.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var error := root.get_texture().get_image().save_png(capture_directory.path_join("online-fishing-%dx%d.png" % [dimensions.x, dimensions.y]))
			check(error == OK, "Rendered fishing panel capture saves at %s" % dimensions)
		var before := sink.commands.size()
		await key(KEY_ENTER)
		check(not social.panel.composer.has_focus(), "Activity Enter keeps focus out of chat at %s" % dimensions)
		check(sink.commands.size() == before + 1 and sink.commands[-1].type == "fish_start", "Native Enter sends fishing intent at %s" % dimensions)
		check(panel.session.state == 1, "Native Enter immediately displays the cast meter at %s" % dimensions)
		sink.latest_snapshot = {"activity":{"kind":"fish","start_token":panel.session._start_token,"station_id":panel.session.station_id,"encounter_id":1,"sample_id":1,"action_ack":1,"state":1,"elapsed":panel.session.elapsed,"power":panel.session.power}}
		await frames()
		# Recover focus only after assertions, keeping subsequent checks independent.
		root.gui_release_focus()
		before = sink.commands.size()
		await click(panel.action_button)
		check(sink.commands.size() == before + 1 and sink.commands[-1].get("action") == "act" and panel.session.state == 2, "Visible fishing button releases displayed cast power through native clicks at %s" % dimensions)
		before = sink.commands.size()
		await click(panel.pale_slots[3])
		check(game.context_menu.visible, "Original pale slot opens its context menu at %s" % dimensions)
		for button: Node in game.context_menu.find_children("*", "Button", true, false):
			if button.text == "Move to inventory":
				await click(button)
				break
		if sink.commands.size() != before + 1 or sink.commands[-1] != {"type": "pale_move", "slot": 3}:
			printerr("[Online activity click evidence] ", dimensions, " control=", panel.pale_slots[3].get_global_rect(), " commands=", sink.commands.slice(before), " trace=", click_trace)
		check(sink.commands.size() == before + 1 and sink.commands[-1] == {"type": "pale_move", "slot": 3}, "Pale control over chat receives native clicks at %s" % dimensions)
		await key(KEY_ESCAPE)
		check(not panel.visible, "Escape closes online fishing at %s" % dimensions)
		check(game.get_node("UI").layer == original_ui_layer, "Closing fishing restores normal chat layering at %s" % dimensions)
		var held := InputEventKey.new()
		held.keycode = KEY_D
		held.physical_keycode = KEY_D
		held.pressed = true
		root.push_input(held)
		await frames()
		check(game.movement_controller.get_move_vector() == Vector2.RIGHT, "Native movement resumes after closing at %s" % dimensions)
		await key(KEY_D)
		check(game.movement_controller.get_move_vector().is_zero_approx(), "Released movement remains clear after closing at %s" % dimensions)
	# Chat still owns letters while a player explicitly edits its composer.
	await key(KEY_ENTER)
	check(social.panel.composer.has_focus(), "Enter opens chat outside an activity")
	await key(KEY_F)
	check(not panel.visible, "Typing F in chat does not open fishing")
	await key(KEY_ESCAPE)
	print("[Online activity input] %d checks, %d failures" % [checks, failures.size()])
	network.mode = network.Mode.OFFLINE
	network.authenticated = false
	scene.free()
	current_scene = null
	sink.free()
	quit(0 if failures.is_empty() else 1)
