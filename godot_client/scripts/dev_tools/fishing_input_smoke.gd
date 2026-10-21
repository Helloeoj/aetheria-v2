extends Node
## Exercises real fishing UI input with frame gaps and both runtime loops enabled.
var checks := 0
var failures: Array[String] = []
var root: Window
var game: Node
var panel: FishingPanel


func _ready() -> void:
	root = get_tree().root
	get_tree().create_timer(45.0).timeout.connect(func() -> void:
		printerr("[Fishing input FAIL] Test timed out")
		get_tree().quit(1))
	_run.call_deferred()


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("[Fishing input FAIL] ", description)


func frames(count: int = 3) -> void:
	for _frame in range(count):
		await get_tree().process_frame


func key_event(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func key(code: Key) -> void:
	key_event(code, true)
	await frames()
	key_event(code, false)
	await frames()


func click(control: Control) -> void:
	var point := control.get_global_transform_with_canvas() * (control.size * 0.5)
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
		await frames(9 if pressed else 3)


func recover_close() -> void:
	# Recover only after assertions, so a broken close path cannot hide later checks.
	panel.rod_picker.get_popup().hide()
	panel.bait_picker.get_popup().hide()
	if panel.visible:
		panel.close()
	await frames()


func choose_option(picker: OptionButton, target_index: int, label: String) -> void:
	await click(picker)
	var popup := picker.get_popup()
	check(popup.visible, label + " opens after a mouse press and release on separate frames")
	if popup.visible:
		# Use the OS event parser so embedded/native Window input reaches PopupMenu.
		# A pointer-opened popup can start with no focused item; navigate from
		# its actual focus to the desired row rather than assigning selection.
		for _attempt in range(picker.item_count + 1):
			if popup.get_focused_item() == target_index:
				break
			await key(KEY_UP if popup.get_focused_item() > target_index else KEY_DOWN)
		await key(KEY_ENTER)
		check(not popup.visible, label + " closes after native popup keyboard selection")
		check(picker.selected == target_index, label + " changes selection through popup input")
		popup.hide()
	await frames()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene := (load("res://scenes/EastOutskirtsLayered.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await frames(6)
	await get_tree().physics_frame
	game = scene.get_node("Combat")
	panel = game.fishing_panel
	game.player.set_skill_level("fishing", 100)
	check(game.is_physics_processing(), "Main physics remains enabled")
	check(panel.is_processing(), "Fishing panel processing remains enabled")
	check(game.FISHING_TEST_KEY == KEY_P and game.fishing_test_button.text.ends_with("[P]"), "Practice uses the advertised P shortcut, not Godot's reserved F9 suspend shortcut")
	await key(KEY_F9)
	check(not panel.visible, "Reserved editor F9 no longer opens fishing")
	var position_before: Vector2 = game.player.get_position()
	await key(KEY_P)
	check(panel.visible, "P opens fishing through viewport input")
	await frames(12)
	check(panel.visible and panel.session.state == FishingSession.State.READY, "Fishing remains ready after live physics and panel frames")
	check(game.player.get_position().is_equal_approx(position_before), "Opening fishing keeps the player stationary with physics running")

	await choose_option(panel.rod_picker, panel.rod_picker.selected + 1, "Rod selector")
	check(panel.session.rod == FishingSession.RODS[panel.rod_picker.selected], "Rod popup selection updates the live session")
	await choose_option(panel.bait_picker, panel.bait_picker.selected + 1, "Food selector")
	check(panel.session.bait == FishingSession.BAITS[panel.bait_picker.selected], "Food popup selection updates the live session")
	# Medium food now targets only tiers 4-6, which require a longer cast.
	# Keep that dropdown coverage, then use Low food for this short-cast flow.
	await choose_option(panel.bait_picker, 0, "Low grade food selector")
	check(panel.session.bait == FishingSession.BAITS[0], "Native food selection restores a valid short-cast catch pool")

	await click(panel.action_button)
	check(panel.session.state == FishingSession.State.POWER, "Cast button starts the meter after a real frame-separated click")
	var power_before := panel.session.power
	await frames(12)
	check(panel.session.power != power_before, "Cast meter advances on its normal process callback")
	await click(panel.action_button)
	check(panel.session.state in [FishingSession.State.CASTING, FishingSession.State.WAITING], "Second Cast button click commits the cast")
	await click(panel.get_node("LeaveFishing"))
	check(not panel.visible and panel.session.state == FishingSession.State.CLOSED, "Leave button closes fishing after a frame-separated click")
	await recover_close()

	await click(game.fishing_test_button)
	check(panel.visible, "Top-bar Test fishing button opens fishing after a frame-separated click")
	await key(KEY_SPACE)
	check(panel.session.state == FishingSession.State.POWER, "Space starts casting with live panel processing")
	await key(KEY_ESCAPE)
	check(not panel.visible and panel.session.state == FishingSession.State.CLOSED, "Escape closes fishing with both runtime loops active")
	await recover_close()

	# Escape first dismisses an active native dropdown; it must not trap the session.
	await key(KEY_P)
	await click(panel.rod_picker)
	var popup := panel.rod_picker.get_popup()
	check(popup.visible, "Rod popup reopens in a new fishing session")
	if popup.visible:
		await key(KEY_ESCAPE)
		check(not popup.visible, "Escape dismisses the native rod popup")
	await key(KEY_ESCAPE)
	check(not panel.visible, "Escape still leaves fishing after dismissing its popup")
	await recover_close()
	check(game.is_physics_processing() and panel.is_processing(), "No input scenario disables runtime processing")
	print("[Fishing input] %d checks, %d failures" % [checks, failures.size()])
	scene.free()
	get_tree().quit(0 if failures.is_empty() else 1)
