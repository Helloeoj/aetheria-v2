extends Node
## Collection transactions and real Fishing Pale buttons with both runtime loops active.
var checks := 0
var failures: Array[String] = []
var root: Window
var game: Node
var panel: FishingPanel
var capture_dir := ""


func _ready() -> void:
	root = get_tree().root
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_dir = argument.trim_prefix("--capture=")
	get_tree().create_timer(45.0).timeout.connect(func() -> void:
		printerr("[Fishing pale FAIL] Test timed out")
		get_tree().quit(1))
	_run.call_deferred()


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("[Fishing pale FAIL] ", description)


func prepared_player() -> PlayerState:
	var player := PlayerState.new()
	player.add_item("Beginner Rod")
	player.add_item("Low Grade Fish Food", 20)
	return player


func check_model() -> void:
	var player := prepared_player()
	check(player.fishing_pale.size() == 9 and player.fishing_pale_count() == 0, "Each player starts with nine empty fixed slots")
	check(not player.store_fishing_catch("Beginner Rod") and not player.store_fishing_catch("Low Grade Fish Food"), "Only actual catchable fish can enter the pale")
	for slot in range(9):
		check(player.store_fishing_catch("Raw Reedkip") and player.fishing_pale[slot] == "Raw Reedkip", "Duplicate catch occupies its own slot %d" % slot)
	check(player.fishing_pale_count() == 9 and int(player.backpack.get("Raw Reedkip", 0)) == 0, "Nine identical catches stay separate from the backpack")
	check(PlayerState.new().fishing_pale_count() == 0, "Different players do not share pale contents")
	var full_snapshot := player.fishing_pale.duplicate()
	check(not player.store_fishing_catch("Raw Marlo") and player.fishing_pale == full_snapshot, "Tenth catch cannot replace an occupied slot")
	var session := FishingSession.new(player)
	var bait_before := int(player.backpack[session.bait])
	session.act()
	check(session.state == FishingSession.State.READY and int(player.backpack[session.bait]) == bait_before, "A full pale blocks cast charging without spending bait")
	check(not player.remove_fishing_catch(0, "Raw Marlo") and player.fishing_pale == full_snapshot, "Stale expected fish cannot remove a different catch")
	check(not player.remove_fishing_catch(-1) and not player.move_fishing_catch_to_inventory(9), "Invalid slot transactions are rejected")
	check(player.move_fishing_catch_to_inventory(4), "Individual transfer succeeds")
	check(player.fishing_pale[4].is_empty() and player.fishing_pale[5] == "Raw Reedkip" and player.fishing_pale.size() == 9, "Removing a fish preserves every other slot position")
	check(int(player.backpack.get("Raw Reedkip", 0)) == 1 and not player.move_fishing_catch_to_inventory(4), "Individual transfer moves exactly one fish and cannot repeat")
	session.act()
	check(session.state == FishingSession.State.POWER, "Freeing a slot allows casting again")
	player.store_fishing_catch("Raw Marlo")
	session.advance(0.7)
	session.act()
	check(session.state == FishingSession.State.READY and int(player.backpack[session.bait]) == bait_before, "Release rechecks capacity before consuming bait")
	check(player.fishing_pale[4] == "Raw Marlo", "The next catch reuses the first empty slot")
	check(player.empty_fishing_pale_to_inventory() == 9 and player.fishing_pale_count() == 0, "Bulk transfer moves every occupied slot")
	check(int(player.backpack.get("Raw Reedkip", 0)) == 9 and int(player.backpack.get("Raw Marlo", 0)) == 1 and player.empty_fishing_pale_to_inventory() == 0, "Bulk transfer preserves each fish exactly once")
	check(player.get_skill_experience("fishing") == 0, "Moving catches does not award fishing XP")

	player = prepared_player()
	session = FishingSession.new(player)
	session.fish = GameData.get_item_by_name("Raw Reedkip")
	session.state = FishingSession.State.FIGHT
	session.distance = 10.0
	session.remaining = 0.05
	session.dart_after = 10.0
	session.advance(0.1)
	var earned_xp := player.get_skill_experience("fishing")
	check(session.state == FishingSession.State.CAUGHT and player.fishing_pale_count() == 1 and player.fishing_pale[0] == "Raw Reedkip", "Finishing the real fight simulation lands one fish in the pale")
	check(earned_xp > 0 and int(player.backpack.get("Raw Reedkip", 0)) == 0, "Landing awards XP while leaving the backpack unchanged")
	session.advance(1.0)
	session._land()
	check(player.fishing_pale_count() == 1 and player.get_skill_experience("fishing") == earned_xp, "Finished cast cannot duplicate its fish or XP")
	player.empty_fishing_pale_to_inventory()
	check(player.get_skill_experience("fishing") == earned_xp, "Transferring a landed catch does not repeat its XP reward")

	# Another transaction can fill the pale after a cast has already begun.
	player = prepared_player()
	for _slot in range(9):
		player.store_fishing_catch("Raw Reedkip")
	session = FishingSession.new(player)
	session.fish = GameData.get_item_by_name("Raw Marlo")
	session.state = FishingSession.State.FIGHT
	session.distance = 10.0
	session.remaining = 0.05
	session.dart_after = 10.0
	session.advance(0.1)
	check(session.state == FishingSession.State.FIGHT and player.fishing_pale_count() == 9 and player.get_skill_experience("fishing") == 0, "A pale filled during a cast retains the landed fish without granting XP early")
	player.move_fishing_catch_to_inventory(0)
	session.advance(0.1)
	earned_xp = player.get_skill_experience("fishing")
	check(session.state == FishingSession.State.CAUGHT and player.fishing_pale[0] == "Raw Marlo" and earned_xp > 0, "Freeing a slot completes the waiting catch without losing it")
	session.advance(1.0)
	check(player.fishing_pale_count() == 9 and player.get_skill_experience("fishing") == earned_xp, "Completing a waiting catch still grants its fish and XP only once")


func frames(count: int = 3) -> void:
	for _frame in range(count):
		await get_tree().process_frame


func key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames()


func click(control: Control, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
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
		event.button_index = button
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
		event.pressed = pressed
		root.push_input(event)
		await frames()


func context_button(label: String) -> Button:
	for node: Node in game.context_menu.find_children("*", "Button", true, false):
		if node.text == label:
			return node as Button
	return null


func capture(name: String) -> void:
	if capture_dir.is_empty():
		return
	await frames()
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(capture_dir.path_join(name))


func check_ui() -> void:
	root.size = Vector2i(1280, 720)
	var scene := (load("res://scenes/EastOutskirtsLayered.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await frames(6)
	await get_tree().physics_frame
	game = scene.get_node("Combat")
	panel = game.fishing_panel
	game.player.store_fishing_catch("Raw Reedkip")
	game.player.store_fishing_catch("Raw Reedkip")
	game.player.store_fishing_catch("Raw Marlo")
	await key(KEY_P)
	check(panel.visible and panel.pale_slots.size() == 9, "Fishing UI renders all nine pale slots")
	check(game.is_physics_processing() and panel.is_processing(), "Pale interactions use live physics and panel processing")
	check(panel.pale_slots[0].icon == ItemVisualLibrary.texture("Raw Reedkip") and panel.pale_slots[2].icon == ItemVisualLibrary.texture("Raw Marlo"), "Occupied pale slots use the same item textures as inventory")
	check(panel.pale_slots[0].is_visible_in_tree() and panel.pale_slots[1].is_visible_in_tree(), "Duplicate fish render in separate visible buttons")
	var positions := {}
	var visible_slots := true
	for button: Button in panel.pale_slots:
		positions[button.position] = true
		visible_slots = visible_slots and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(button.get_global_rect())
	check(positions.size() == 9 and visible_slots, "All nine distinct slot buttons fit the viewport")
	var initial_xp: int = game.player.get_skill_experience("fishing")
	await capture("fishing-pale-filled.png")
	await click(panel.pale_slots[0])
	check(game.context_menu.visible, "Clicking an occupied pale slot opens its context menu")
	var move_button := context_button("Move to inventory")
	var drop_button := context_button("Drop to ground")
	check(move_button != null and drop_button != null, "Fish context menu offers Move to inventory and Drop to ground")
	await capture("fishing-pale-context.png")
	await key(KEY_ESCAPE)
	check(not game.context_menu.visible and panel.visible, "Escape dismisses fish actions before closing fishing")
	await click(panel.pale_slots[0])
	move_button = context_button("Move to inventory")
	if move_button != null:
		await click(move_button)
	check(game.player.fishing_pale[0].is_empty() and game.player.fishing_pale[1] == "Raw Reedkip" and int(game.player.backpack.get("Raw Reedkip", 0)) == 1, "Context move transfers only its selected fish")
	check(not game.context_menu.visible and panel.visible, "Moving a catch closes the menu while keeping fishing open")

	await click(panel.pale_slots[2], MOUSE_BUTTON_RIGHT)
	drop_button = context_button("Drop to ground")
	check(drop_button != null, "Right-clicking a fish also opens its actions")
	var drops_before: int = game.ground_drops.size()
	if drop_button != null:
		await click(drop_button)
	check(game.player.fishing_pale[2].is_empty() and game.ground_drops.size() == drops_before + 1, "Context drop creates one real ground item and clears the selected slot")
	if game.ground_drops.size() > drops_before:
		var drop: GroundItemDrop = game.ground_drops.back()
		check(drop.item_name == "Raw Marlo" and drop.quantity == 1 and drop.sprite.texture != null, "Dropped fish preserves its item, quantity, and visible icon")
		check(int(game.player.backpack.get("Raw Marlo", 0)) == 0, "Dropping a pale fish does not also grant an inventory copy")
		check(game._collect_ground_drop(drop) and int(game.player.backpack.get("Raw Marlo", 0)) == 1, "Dropped fish can be picked up into the backpack without loss")
		check(not game._collect_ground_drop(drop), "Dropped fish cannot be collected twice")
	check(not game.drop_fishing_pale_item(1, "Raw Marlo") and game.player.fishing_pale[1] == "Raw Reedkip", "Stale drop actions preserve a different fish in the slot")
	panel.move_pale_catch(1, "Raw Marlo")
	check(game.player.fishing_pale[1] == "Raw Reedkip", "Stale inventory actions preserve a different fish in the slot")
	var player_sprite: ActorSprite = game.actor_sprites[game.player.entity_id]
	game.actor_sprites.erase(game.player.entity_id)
	drops_before = game.ground_drops.size()
	var failed_drop: bool = game.drop_fishing_pale_item(1, "Raw Reedkip")
	game.actor_sprites[game.player.entity_id] = player_sprite
	check(not failed_drop and game.player.fishing_pale[1] == "Raw Reedkip" and game.ground_drops.size() == drops_before, "A failed ground spawn preserves its pale fish without creating a duplicate")
	await click(panel.pale_slots[1])
	await key(KEY_ESCAPE)
	check(panel.visible and not game.context_menu.visible, "First Escape leaves fishing open when fish actions were visible")
	await key(KEY_ESCAPE)
	check(not panel.visible, "Second Escape closes fishing after its actions are dismissed")
	await key(KEY_P)
	check(panel.visible and game.player.fishing_pale[1] == "Raw Reedkip" and game.player.fishing_pale_count() == 1, "Closing and reopening fishing preserves catches and their fixed slots")
	await click(panel.empty_pale_button)
	check(game.player.fishing_pale_count() == 0 and int(game.player.backpack.get("Raw Reedkip", 0)) == 2, "Empty Pale button moves all remaining fish into inventory")
	check(game.player.get_skill_experience("fishing") == initial_xp, "UI transfers, drops, pickups, and reopening never duplicate fishing XP")
	check(panel.empty_pale_button.disabled, "Empty Pale button disables when the pale is empty")
	await capture("fishing-pale-empty.png")
	await key(KEY_ESCAPE)
	scene.free()


func _run() -> void:
	check_model()
	await check_ui()
	print("[Fishing pale] %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
