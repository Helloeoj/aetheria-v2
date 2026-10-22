extends SceneTree
## Run the actual persistent HUD and native gameplay input together.
var failures: Array[String] = []
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("[Social UI FAIL] ", label)

func _initialize() -> void:
	_run.call_deferred()

func frames(count: int = 3) -> void:
	for index in range(count):
		await process_frame

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	root.push_input(event)
	await frames()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var social: Node = root.get_node_or_null("Social")
	check(social != null, "Persistent social autoload is installed in the active game")
	if social == null:
		quit(1)
		return
	var scene: Node = load("res://scenes/EastOutskirtsLayered.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await frames(8)
	var game: Node = scene.get_node("Combat")
	var panel: Control = social.panel
	check(panel.visible and panel.get_parent().get_parent() == social, "Chat lives outside replaceable area scenes")
	check(panel.background_alpha < 0.5, "Background is mostly transparent while text stays opaque")
	check(panel.composer != null and panel.tabs.get_tab_count() == 4, "All, Local, Global and Private channels have an input")
	await key(KEY_ENTER)
	check(panel.composer.has_focus(), "Enter focuses chat")
	for code: Key in [KEY_K, KEY_P, KEY_I, KEY_H]:
		await key(code)
	check(not game.skill_debug_panel.visible, "Typing K never opens skill testing")
	check(not game.fishing_panel.visible, "Typing P never starts fishing")
	check(not game.inventory_menu.visible, "Typing I never opens the journal")
	panel.composer.text = "draft"
	await key(KEY_ESCAPE)
	check(not panel.composer.has_focus() and panel.composer.text == "draft", "Escape preserves draft and releases gameplay input")
	social._receive({"type": "ready", "id": "self", "name": "Tester"})
	social._receive({"type": "message", "id": "one", "channel": "global", "sender_id": "other", "sender": "Friend", "target_id": "", "target": "", "text": "[b]Plain text[/b]"})
	check(social.history.size() == 1, "Received messages enter persistent scrollback")
	check(panel.transcript.get_parsed_text().contains("[b]Plain text[/b]"), "Player markup stays literal")
	social._receive({"type": "social", "friends": [], "blocks": [{"id": "other", "name": "Friend"}]})
	check(not panel.transcript.get_parsed_text().contains("Plain text"), "Blocking hides retained messages")
	panel._open_drawer(0)
	panel._open_drawer(2)
	check(panel.drawer.visible and panel.drawer_tabs.current_tab == 2, "Switching drawer tabs keeps the drawer open")
	panel.drawer.hide()
	var underlying := Button.new()
	underlying.text = "Existing activity control"
	game.ui_root.add_child(underlying)
	underlying.position = panel.position + Vector2(100, 65)
	underlying.size = Vector2(220, 40)
	var clicked := [false]
	underlying.pressed.connect(func() -> void: clicked[0] = true)
	panel.tabs.focus_mode = Control.FOCUS_ALL
	panel.tabs.grab_focus()
	var point := underlying.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion)
	for pressed: bool in [true, false]:
		var mouse := InputEventMouseButton.new()
		mouse.position = point
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.pressed = pressed
		root.push_input(mouse)
		await frames()
	check(clicked[0], "Existing activity controls remain clickable beneath the transparent panel")
	underlying.free()
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = dimensions
		social.update_layout()
		game._update_ui_scale()
		await frames()
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(panel.get_global_rect()), "Chat fits %s" % dimensions)
		check(game.food_button.get_global_rect().end.y <= panel.get_global_rect().position.y, "Food controls stay above chat")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			root.size = Vector2i(1280, 720)
			social.update_layout()
			game._update_ui_scale()
			social._receive({"type": "social", "friends": [{"id": "other", "name": "Friend", "online": true}], "blocks": []})
			social._receive({"type": "message", "id": "two", "channel": "local", "sender_id": "other", "sender": "Friend", "text": "Meet me by the tavern?"})
			social._receive({"type": "message", "id": "three", "channel": "private", "sender_id": "other", "sender": "Friend", "target_id": "self", "target": "Tester", "text": "I added you to my friends list."})
			await frames(5)
			root.get_texture().get_image().save_png(argument.trim_prefix("--capture="))
	var expected_history: int = social.history.size()
	var original_panel: Control = panel
	scene.free()
	current_scene = null
	await frames()
	check(is_instance_valid(original_panel) and original_panel.visible and social.history.size() == expected_history, "Panel and history survive area removal")
	print("[Social UI] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
