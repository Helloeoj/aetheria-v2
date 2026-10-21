extends Node
## Real journal/context-menu, keyboard and HUD coverage for food consumption.
var checks := 0
var failures: Array[String] = []
var game: Node
var capture_dir := ""

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("[Food input FAIL] ", description)

func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture_dir = arg.trim_prefix("--capture=")
	get_tree().create_timer(45.0).timeout.connect(func() -> void:
		printerr("[Food input FAIL] Test timed out")
		get_tree().quit(1))
	_run.call_deferred()

func frames(count: int = 3) -> void:
	for frame in range(count):
		await get_tree().process_frame

func key(code: Key, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.echo = echo
	get_tree().root.push_input(event)
	await frames()
	if not echo:
		event = InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		get_tree().root.push_input(event)
		await frames()

func click(control: Control, button := MOUSE_BUTTON_LEFT) -> void:
	var at := control.get_global_transform_with_canvas() * (control.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_tree().root.push_input(motion)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = button
		event.pressed = pressed
		get_tree().root.push_input(event)
		await frames()

func find_button(container: Node, text: String) -> Button:
	for node: Node in container.find_children("*", "Button", true, false):
		if node.text == text:
			return node as Button
	return null

func select_food(name: String) -> void:
	var source: Button
	for node: Node in game.inventory_menu.find_children("*", "Button", true, false):
		if String(node.get_meta("item_name", "")) == name:
			source = node as Button
			break
	check(source != null, name + " has a real inventory card")
	if source == null:
		return
	await click(source, MOUSE_BUTTON_RIGHT)
	var action := find_button(game.context_menu, "Set quick food [H]")
	check(action != null, "Food context menu exposes quick selection")
	if action != null:
		await click(action)
	check(game.player.quick_food_name == name, name + " is selected through native UI input")

func capture(name: String) -> void:
	if capture_dir.is_empty():
		return
	await frames()
	RenderingServer.force_draw(false)
	get_tree().root.get_texture().get_image().save_png(capture_dir.path_join(name))

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	var scene := (load("res://scenes/EastOutskirtsLayered.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	await frames(6)
	game = scene.get_node("Combat")
	game.player.backpack.clear()
	var actor: CombatActor = game.combat.actors[game.player.entity_id]
	actor.hp = 100
	game._sync_actor_states()
	# Finish actual landing transactions, then transfer the caught fish.
	var session := FishingSession.new(game.player)
	for name: String in ["Reedkip", "Reedkip", "Sunfish"]:
		session.fish = GameData.get_item_by_name("Raw " + name)
		session.state = FishingSession.State.FIGHT
		session._land()
	check(game.player.fishing_pale_count() == 3 and game.player.backpack.is_empty(), "Landed food remains in the pale until transferred")
	check(game.player.empty_fishing_pale_to_inventory() == 3, "Caught food transfers into the backpack")
	check(game.player.get_quick_food().is_empty(), "Raw catches are never selected as quick food")
	var fire := CookingCampfire.new(game.player.get_position())
	fire.active = true
	game.player.set_skill_level("cooking", 100)
	var cooking := CookingSession.new(game.player, fire)
	for species: String in ["Reedkip", "Sunfish"]:
		var raw_name := "Raw " + species
		check(cooking.start(raw_name, int(game.player.backpack[raw_name])).is_empty(), "Transferred fish can start cooking")
		for fish_index in range(int(game.player.backpack[raw_name])):
			cooking.advance(3.0)
			cooking.flip()
			cooking.advance(CookingSession.FEEDBACK_SECONDS)
	var fishing_xp: int = game.player.get_skill_experience("fishing")
	await frames()
	check(game.player.get_quick_food() == "Reedkip", "The initial default selects the lowest-healing carried food")
	await key(KEY_I)
	await select_food("Sunfish")
	check(game.player.current_hp == 100 and game.player.backpack["Sunfish"] == 1, "Selecting quick food consumes nothing")
	await select_food("Reedkip")
	await key(KEY_I)
	await key(KEY_H)
	check(game.player.current_hp == 140 and actor.hp == 140 and game.player.backpack["Reedkip"] == 1, "Native H heals and consumes one carried fish with synchronized combat HP")
	check(game.food_notice.text.contains("+40 HP") and game.food_button.text.contains("cooldown"), "HUD shows actual healing and the eating cooldown")
	await capture("food-hud-healing.png")
	await key(KEY_H, true)
	check(game.player.backpack["Reedkip"] == 1 and actor.hp == 140, "Held key repeat cannot eat another fish")
	game.set_quick_food("Sunfish")
	await key(KEY_H)
	check(game.player.backpack.has("Sunfish") and actor.hp == 140, "Changing quick food cannot bypass the shared cooldown")
	await get_tree().create_timer(1.9).timeout
	check(actor.hp == 140, "Waiting in the outskirts provides no passive healing")
	await key(KEY_H)
	check(actor.hp == 200 and not game.player.backpack.has("Sunfish"), "High food heals only missing HP and consumes exactly one")
	check(game.player.quick_food_name == "Sunfish" and game.food_button.text.contains("No food left"), "Depletion preserves the selected species instead of substituting food")
	await key(KEY_H)
	check(game.player.backpack["Reedkip"] == 1, "A depleted quick slot never spends another species")
	await get_tree().create_timer(1.9).timeout
	game.set_quick_food("Reedkip")
	await key(KEY_H)
	check(game.player.backpack["Reedkip"] == 1 and actor.hp == 200, "Full health leaves food untouched through the real input path")
	actor.hp = 0
	game._sync_actor_states()
	await key(KEY_H)
	check(actor.hp == 0 and game.player.backpack["Reedkip"] == 1, "Food input cannot revive a defeated character")
	actor.hp = 100
	game._sync_actor_states()
	var edit := LineEdit.new()
	edit.position = Vector2(800, 100)
	edit.size = Vector2(200, 40)
	game.ui_root.add_child(edit)
	edit.grab_focus()
	await key(KEY_H)
	check(actor.hp == 100 and game.player.backpack["Reedkip"] == 1, "Typing in an editing control does not consume food")
	edit.release_focus()
	edit.queue_free()
	await frames()
	game.player.current_hp = 180
	var result: Dictionary = game.eat_food("Reedkip")
	check(result.ok and result.healing == 40 and actor.hp == 140, "Eating uses current combat HP rather than stale UI HP")
	game.player.add_item("Marlo")
	check(game.player.get_quick_food() == "Reedkip", "Receiving another species does not replace depleted quick food")
	await get_tree().create_timer(1.9).timeout
	game.set_quick_food("Marlo")
	await frames()
	await click(game.food_button)
	check(actor.hp == 200 and not game.player.backpack.has("Marlo"), "The native HUD button follows the same consumption path")
	check(game.player.get_skill_experience("fishing") == fishing_xp, "Eating does not duplicate Fishing XP")
	await capture("food-hud-full.png")
	for dimensions: Vector2i in [Vector2i(960, 540), Vector2i(1920, 1080)]:
		get_tree().root.size = dimensions
		game._update_ui_scale()
		await frames()
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(game.food_button.get_global_rect()), "Food HUD fits viewport %s" % dimensions)
	print("[Food input] %d checks, %d failures" % [checks, failures.size()])
	scene.free()
	get_tree().quit(0 if failures.is_empty() else 1)
