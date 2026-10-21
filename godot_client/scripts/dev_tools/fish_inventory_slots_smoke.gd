extends Node
## Verify individual fish slots through the real journal, food and drop paths.
var checks := 0
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("[Fish inventory slots FAIL] ", description)

func item_buttons(menu: InventoryMenu, item_name: String) -> Array[Button]:
	var found: Array[Button] = []
	for widget: Node in menu.body.find_children("*", "Button", true, false):
		if widget.has_meta("inventory_slot") and String(widget.get_meta("item_name", "")) == item_name:
			found.append(widget as Button)
	return found

func right_click(menu: InventoryMenu, item_name: String) -> void:
	var button: Button = item_buttons(menu, item_name)[0]
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	event.position = button.size * 0.5
	menu._inventory_context_input(event, item_name, button)

func context_action(game: Node, label: String) -> Callable:
	for entry: Dictionary in game.context_menu.actions:
		if String(entry.get("label", "")) == label:
			return entry.action
	return Callable()

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	var scene := (load("res://scenes/EastOutskirtsLayered.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var game: Node = scene.get_node("Combat")
	game.set_physics_process(false)
	var player: PlayerState = game.player
	var menu: InventoryMenu = game.inventory_menu
	player.backpack.clear()
	player.add_item("Reedkip", 4)
	player.add_item("Marlo", 2)
	player.add_item("Feathers", 5)
	player.add_item("Beginner Rod", 3)
	player.add_item("Low Grade Fish Food", 50)
	player.backpack["Bracken"] = 0
	player.backpack["Kessa"] = -2
	var original_backpack := player.backpack.duplicate(true)
	var slots := InventorySystem.inventory_slots(player)
	check(slots.size() == 9, "Six individual fish and three ordinary stacks use nine slots")
	check(player.backpack == original_backpack, "Projecting slots preserves dictionary quantities and save compatibility")
	for fish_name: String in FishingSession.FISH:
		check(not InventorySystem.is_stackable(fish_name), "Fish uses individual slots: " + fish_name)
	for item_name: String in ["Beginner Rod", "Low Grade Fish Food", "Feathers"]:
		check(InventorySystem.is_stackable(item_name), "Other items retain their stack behavior: " + item_name)
	var reedkip_count := 0
	var marlo_count := 0
	var ignored_nonpositive := true
	for slot: Dictionary in slots:
		if String(slot.name) == "Reedkip":
			reedkip_count += 1
			check(int(slot.quantity) == 1, "Each Reedkip slot contains exactly one fish")
		elif String(slot.name) == "Marlo":
			marlo_count += 1
			check(int(slot.quantity) == 1, "Each Marlo slot contains exactly one fish")
		ignored_nonpositive = ignored_nonpositive and String(slot.name) not in ["Bracken", "Kessa"]
	check(reedkip_count == 4 and marlo_count == 2, "Duplicate species expand into distinct inventory entries")
	check(ignored_nonpositive, "Empty and invalid negative quantities do not produce slots")
	menu.show()
	menu.select_page(InventoryMenu.Page.INVENTORY)
	var copies := item_buttons(menu, "Reedkip")
	check(copies.size() == 4 and item_buttons(menu, "Marlo").size() == 2, "Journal renders one clickable card per fish")
	check(item_buttons(menu, "Feathers").size() == 1, "Ordinary materials keep a single stack card")
	var fish_have_no_stack_label := true
	var fish_texture_matches := true
	for button: Button in copies:
		for label: Label in button.find_children("*", "Label", true, false):
			fish_have_no_stack_label = fish_have_no_stack_label and not label.text.begins_with("×")
		var icons := button.find_children("*", "TextureRect", true, false)
		fish_texture_matches = fish_texture_matches and icons.size() == 1 and icons[0].texture == ItemVisualLibrary.texture("Reedkip")
	check(fish_have_no_stack_label, "Individual fish cards have no stack count")
	check(fish_texture_matches, "Individual fish reuse the existing inventory texture")
	var second_copy_slot := int(copies[1].get_meta("inventory_slot"))
	copies[1].pressed.emit()
	check(menu.selected_inventory_slot_index == second_copy_slot and menu.selected_item_name == "Reedkip", "Selecting a duplicate fish keeps that particular slot selected")
	var highlighted := 0
	for button: Button in item_buttons(menu, "Reedkip"):
		var style := button.get_theme_stylebox("normal") as StyleBoxFlat
		if style.border_color == FantasyUI.GOLD:
			highlighted += 1
	check(highlighted == 1, "Only the selected fish card is highlighted")
	right_click(menu, "Reedkip")
	var fish_drop_all := false
	for entry: Dictionary in game.context_menu.actions:
		fish_drop_all = fish_drop_all or String(entry.label).begins_with("Drop all")
	check(not fish_drop_all and context_action(game, "Drop").is_valid(), "Fish context offers a single Drop action without Drop all")
	check(context_action(game, "Eat fish").is_valid(), "Each fish retains its eating action")
	player.current_hp = player.get_max_hp() - 1
	# Food uses the combat actor's authoritative HP, as real damage would.
	var player_actor: CombatActor = game.combat.actors[player.entity_id]
	player_actor.hp = player.current_hp
	player.food_cooldown_seconds = 0.0
	context_action(game, "Eat fish").call()
	check(int(player.backpack.get("Reedkip", 0)) == 3 and item_buttons(menu, "Reedkip").size() == 3, "Eating removes exactly one fish and its displayed slot")
	right_click(menu, "Reedkip")
	context_action(game, "Drop").call()
	check(int(player.backpack.get("Reedkip", 0)) == 2 and item_buttons(menu, "Reedkip").size() == 2, "Dropping removes exactly one fish and its displayed slot")
	check(game.ground_drops.back().quantity == 1, "Single-fish drop creates a ground item of quantity one")
	menu._handle_drop("Reedkip", 99)
	check(int(player.backpack.get("Reedkip", 0)) == 1, "Journal drop handler cannot drop all duplicate fish at once")
	right_click(menu, "Feathers")
	check(context_action(game, "Drop all (5)").is_valid(), "Stackable materials retain Drop all")
	game.context_menu.dismiss()
	print("[Fish inventory slots] %d checks, %d failures" % [checks, failures.size()])
	scene.free()
	get_tree().quit(0 if failures.is_empty() else 1)
