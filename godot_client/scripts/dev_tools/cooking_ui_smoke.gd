extends Node
## Real tavern scene, modal input, pan UI, training meter and interrupted sessions.
var checks := 0
var failures := 0
var game: Node
var output := ""
var probe_controller: Node
var probe_visible_window := -1.0
var probe_enabled := false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Cooking UI FAIL] " + label)

func _ready() -> void:
	process_priority = 100
	_run.call_deferred()

func _process(_delta: float) -> void:
	if probe_enabled and probe_controller.panel.session.state == CookingSession.State.FLIP_PENDING:
		probe_visible_window = probe_controller.panel.session.flip_window - probe_controller.panel.session.flip_elapsed
		probe_enabled = false

func key(code: Key, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = echo
	get_tree().root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	get_tree().root.push_input(event)

func click(button: Button) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = button.get_global_transform_with_canvas() * (button.size * 0.5)
	motion.global_position = motion.position
	get_tree().root.push_input(motion)
	await get_tree().process_frame
	var event := InputEventMouseButton.new()
	event.position = button.get_global_transform_with_canvas() * (button.size * 0.5)
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	get_tree().root.push_input(event)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	get_tree().root.push_input(event)
	await get_tree().process_frame

func capture(filename: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	check(get_tree().root.get_texture().get_image().save_png(output.path_join(filename)) == OK, "Capture " + filename)

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
	var scene := (load("res://scenes/TavernInterior.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await get_tree().physics_frame
	await get_tree().process_frame
	game = scene.get_node("Combat")
	game.set_physics_process(false)
	var controller: Node = game.cooking_controller
	controller.set_physics_process(false)
	controller.set_process(false)
	var stove: Node2D = game.get_node("Stove")
	var local: Vector2 = game.to_local(stove.approach_position())
	var actor: CombatActor = game.combat.actors[game.player.entity_id]
	actor.x = (local.x - game.map_origin.x) / game.TILE_SIZE
	actor.y = (game.map_origin.y + game.map_height - local.y) / game.TILE_SIZE
	game.player.x = actor.x
	game.player.y = actor.y
	game._update_sprite_position(actor.entity_id)
	game.player.backpack.clear()
	game.player.add_item("Raw Reedkip", 4)
	controller.open(stove)
	var panel: Control = controller.panel
	await get_tree().process_frame
	await get_tree().process_frame
	# The deterministic controller is paused, so refresh after the initial viewport resize.
	game._update_ui_scale()
	panel.refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	check(panel.visible, "Nearby actual stove opens shared Cooking UI")
	var action := panel.find_child("FlipAction", true, false) as Button
	check(action != null, "Actual Cooking panel has a prominent FLIP button")
	if action == null:
		_finish()
		return
	check(action.disabled, "No premature flip from recipe selection")
	await click(panel.cook_all)
	check(panel.session.state == CookingSession.State.COOKING, "Actual Cook all click starts the batch")
	key(KEY_SPACE)
	check(panel.session.cooked_count == 0, "Space cannot cook during heat-up")
	controller.advance(3.0)
	await get_tree().process_frame
	check(not action.disabled and panel.get("timer_label").text.contains("0.80"), "Unlock shows an actionable 0.80 second countdown")
	check(panel.get("pan") != null, "Food and cooking surface use a reusable pan view")
	await capture("01-flip-finite.png")
	key(KEY_SPACE, true)
	check(panel.session.cooked_count == 0, "Held interaction key cannot auto-flip")
	await click(action)
	check(panel.session.cooked_count == 1 and game.player.get_skill_experience("cooking") == 40, "Actual mouse click cooks once with original XP")
	key(KEY_ENTER)
	check(panel.session.cooked_count == 1, "Input during flip feedback cannot duplicate rewards")
	await capture("02-flip-success.png")
	controller.advance(0.65)
	controller.advance(3.0)
	controller.advance(0.8)
	check(panel.session.burnt_count == 1 and int(game.player.backpack.get("Burnt Reedkip", 0)) == 1, "Missed UI timer yields existing burnt item")
	check(game.player.get_skill_experience("cooking") == 40, "UI burn awards no XP")
	await capture("03-burn.png")
	controller.advance(0.65)
	controller.advance(3.0)
	key(KEY_ENTER)
	check(panel.session.cooked_count == 2, "Enter manually flips the next batch fish")
	check(int(game.skill_training_session.get_progress("cooking").experience_gained) == 80, "Manual flip records training XP through controller")
	controller.advance(0.65)
	controller.advance(3.0)
	key(KEY_ESCAPE)
	check(not panel.visible and game.player.active_cooking_session == null, "Escape closes and releases live prompt")
	check(int(game.player.backpack.get("Burnt Reedkip", 0)) == 2, "Closing a live prompt cannot reroll the same raw ingredient")
	game.player.add_item("Raw Reedkip", 2)
	game.player.set_skill_level("cooking", 21)
	controller.open(stove)
	panel.cook_all.pressed.emit()
	controller.advance(3.0)
	controller.advance(1000000.0)
	check(panel.get("timer_label").text.contains("SAFE") and panel.session.cooked_count == 0 and not action.disabled, "Mastered UI remains untimed and still needs input")
	await capture("04-mastery-safe.png")
	key(KEY_SPACE)
	check(panel.session.cooked_count == 1, "Mastered fish completes only on manual Space")
	controller.advance(0.65)
	controller.advance(3.0)
	actor.hp -= 1
	key(KEY_SPACE)
	check(panel.session.state == CookingSession.State.CANCELLED and panel.session.cooked_count == 1, "Input synchronizes current actor damage before granting rewards")
	panel.close()
	game.player.set_skill_level("cooking", 1)
	game.player.add_item("Raw Reedkip")
	controller.open(stove)
	panel.cook_one.pressed.emit()
	controller.set_physics_process(true)
	controller.set_process(true)
	await get_tree().create_timer(3.1).timeout
	check(panel.session.state == CookingSession.State.FLIP_PENDING and not action.disabled, "Live physics opens the finite reaction prompt after heating")
	await get_tree().create_timer(0.85).timeout
	check(panel.session.burnt_count == 1 and panel.session.cooked_count == 0, "Live physics burns a missed prompt without synthetic advancement")
	controller.set_physics_process(false)
	controller.set_process(false)
	panel.close()
	game.player.add_item("Raw Reedkip")
	controller.open(stove)
	panel.cook_one.pressed.emit()
	controller.advance(2.99)
	probe_controller = controller
	probe_enabled = true
	controller.set_physics_process(true)
	controller.set_process(true)
	# Force several catch-up physics callbacks before the next presentation frame.
	OS.delay_msec(250)
	for frame in range(4):
		await get_tree().process_frame
	controller.set_physics_process(false)
	controller.set_process(false)
	check(probe_visible_window >= 0.79999, "Physics catch-up never spends the reaction window before its first visible frame")
	panel.close()
	game.player.add_item("Raw Reedkip")
	controller.open(stove)
	panel.cook_one.pressed.emit()
	controller.advance(3.0)
	var old_session: CookingSession = panel.session
	scene.queue_free()
	await get_tree().process_frame
	check(old_session.state == CookingSession.State.CANCELLED and old_session.player.active_cooking_session == null, "Scene teardown cancels prompt and releases player")
	check(old_session.call("flip").is_empty(), "Stale/reconnected session cannot claim delayed animation reward")
	_finish()

func _finish() -> void:
	print("[Cooking UI] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
