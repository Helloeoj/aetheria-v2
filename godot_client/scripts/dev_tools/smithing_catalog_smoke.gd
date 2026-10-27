extends Node
## Completed catalog -> real exchanges -> original F6 and crafting interfaces.
const METALS := ["Bronze", "Iron", "Steel", "Blacksteel", "Mithril", "Adamantite"]
const GEAR := [["Dagger", 1], ["Shortsword", 2], ["Longsword", 3], ["Mace", 3], ["Warmaul", 4], ["Helmet", 2], ["Platebody", 5], ["Platelegs", 3], ["Kiteshield", 3], ["Square Shield", 2]]
class Geometry extends Node2D:
	var map_width := 1536.0
	var map_height := 1024.0
var checks := 0
var failures := 0
var catalog: Script
var capture_dir := ""

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Smithing catalog FAIL] " + label)

func _ready() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="): capture_dir = argument.trim_prefix("--capture=")
	get_tree().create_timer(60.0).timeout.connect(func() -> void: get_tree().quit(1))
	_run.call_deferred()

func frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		if code >= KEY_0 and code <= KEY_9: event.unicode = code
		event.pressed = pressed
		get_tree().root.push_input(event)
		await frames()

func click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_tree().root.push_input(motion)
	await frames()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		get_tree().root.push_input(event)
		await frames()

func capture(label: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(capture_dir.path_join(label + ".png")) == OK, "Rendered " + label)

func _run() -> void:
	check(ResourceLoader.exists("res://scripts/smithing_catalog.gd"), "Completed smithing catalog is shared by both menus")
	if failures > 0:
		_finish()
		return
	catalog = load("res://scripts/smithing_catalog.gd")
	_catalog_and_recipes()
	_authority()
	await _menus()
	_finish()

func _catalog_and_recipes() -> void:
	var ids: Array = catalog.item_ids(GameData.items_by_id)
	check(ids.size() == 72, "Six craftable tiers provide 60 gear pieces and twelve material items")
	for metal: String in METALS:
		var player := PlayerState.new()
		player.add_item("Iron Ore" if metal == "Steel" else metal + " Ore", 10)
		if metal == "Steel": player.add_item("Coal", 10)
		check(CraftingService.craft(player, "smelt_" + metal.to_lower(), "furnace", 10).ok and player.backpack == {metal + " Ingot": 10}, "Ten correct ore produce ten real ingots: " + metal)
		for gear: Array in GEAR:
			var name_key := metal + " " + String(gear[0])
			var item := GameData.get_item_by_name(name_key)
			check(ids.has(int(item.id)) and not String(catalog.category(item)).is_empty(), "Implemented gear appears in Smithing view: " + name_key)
			check(ItemVisualLibrary.texture(name_key) != null, "Authored or generic icon available: " + name_key)
			player.backpack.clear()
			player.add_item(metal + " Ingot", int(gear[1]) * 2)
			var id := (metal + " " + String(gear[0])).to_snake_case()
			check(CraftingService.craft(player, id, "anvil", 2).ok and player.backpack == {name_key: 2}, "Category costs and batch yield remain exact: " + name_key)
			var output := player.backpack.duplicate(true)
			check(not CraftingService.craft(player, id, "anvil").ok and player.backpack == output, "No replay without ingots: " + name_key)
			player.backpack.clear()
			player.add_item("Iron Ingot" if metal == "Bronze" else "Bronze Ingot", 100)
			var wrong_metal := player.backpack.duplicate(true)
			check(not CraftingService.craft(player, id, "anvil").ok and player.backpack == wrong_metal, "Other metals cannot substitute: " + name_key)
	for item: Dictionary in GameData.list_items():
		if int(item.id) in ids:
			check(not String(item.name).to_lower().contains("bow") and item.get("slot") not in ["cape", "neck", "ring"], "Smithing view excludes bows and accessories")
	for name_key: String in ["Bronze Bow", "Bronze Crossbow", "Bronze Ring", "Bronze Necklace", "Apprentice Magic Staff", "Homespun Hood", "Magic Orb"]:
		check(String(catalog.category(GameData.get_item_by_name(name_key))).is_empty(), "Excluded category: " + name_key)
	check(String(catalog.category(GameData.get_item_by_name("Steel Ore"))).is_empty() and ids.has(int(GameData.get_item_by_name("Coal").id)), "Steel alloy uses Coal instead of legacy Steel Ore")
	check(not GameData.get_item_by_name("Steel Ore").generic_loot, "Historical Steel Ore no longer enters generic loot")
	check(ItemVisualLibrary.texture("Coal") != null, "Coal has a generic inventory icon")
	for supplies: Dictionary in [{"Iron Ore": 10}, {"Coal": 10}, {"Steel Ore": 10}]:
		var player := PlayerState.new()
		player.backpack = supplies.duplicate(true)
		check(not CraftingService.craft(player, "smelt_steel", "furnace", 10).ok and player.backpack == supplies, "Both alloy ingredients are required atomically")

func _authority() -> void:
	var geometry := Geometry.new()
	add_child(geometry)
	for id: String in ["anvil", "furnace"]:
		var station := CraftingStation.new()
		station.name = id
		station.setup(id, id.capitalize(), Vector2(10, 10))
		geometry.add_child(station)
	var region := AuthoritativeRegion.new()
	region.configure("smithing-catalog", geometry)
	var player := PlayerState.new()
	region.add_player("smithing-tester", player)
	var stations := {}
	for id: String in region.stations: stations[String(region.stations[id].station)] = id
	for recipe: Dictionary in CraftingService.list_recipes():
		if recipe.station not in ["anvil", "furnace"] or not recipe.enabled: continue
		player.backpack.clear()
		for entry: Dictionary in recipe.inputs: player.add_item(entry.item, int(entry.quantity))
		var command: Dictionary = JSON.parse_string(JSON.stringify({"type": "craft", "station_id": stations[recipe.station], "recipe_id": recipe.id, "quantity": 1}))
		var result: Dictionary = region.submit(player.entity_id, command)
		var output := {}
		for entry: Dictionary in recipe.outputs: output[entry.item] = int(entry.quantity)
		check(bool(result.ok) and player.backpack == output, "Server validates completed recipe: " + String(recipe.id))
		check(not region.submit(player.entity_id, command).ok and player.backpack == output, "Server repeated request cannot duplicate output: " + String(recipe.id))
	player.backpack = {"Iron Ore": 1}
	check(not region.submit(player.entity_id, {"type": "craft", "station_id": stations.furnace, "recipe_id": "smelt_steel", "quantity": 1}).ok and player.backpack == {"Iron Ore": 1}, "Server preserves Iron Ore without Coal")
	player.backpack = {"Iron Ore": 1, "Coal": 1, "Starforged Ingot": 5, "Steel Ore": 2}
	var codec: Script = load("res://network/character_codec.gd")
	var restored: Dictionary = codec.decode(JSON.parse_string(JSON.stringify(codec.encode(player, "outskirts"))), "Smithing tester", player.entity_id)
	check(restored.ok and restored.player.backpack == player.backpack, "New Coal and existing metals survive character serialization")
	region.remove_player(player.entity_id)
	geometry.queue_free()

func _menus() -> void:
	var scene: Node = load("res://scenes/EastOutskirtsLayered.tscn").instantiate()
	get_tree().root.add_child(scene)
	await frames()
	var game: Node = scene.get_node("Combat")
	game.set_physics_process(false)
	game.player.backpack.clear()
	await key(KEY_F6)
	var menu: Control = game.item_menu
	check(menu.visible and menu.display_ids.size() == 72, "Existing F6 opens the filtered completed Smithing list")
	menu.quantity.value = 10
	await click(menu.get_global_transform_with_canvas() * Vector2(170, 212))
	check(game.player.backpack.get("Bronze Ore", 0) == 10, "Clicking ore row gives chosen stack quantity")
	await click(menu.get_global_transform_with_canvas() * Vector2(170, 230))
	check(game.player.backpack.get("Bronze Ingot", 0) == 10, "Clicking ingot row gives chosen stack quantity")
	await click(menu.get_global_transform_with_canvas() * Vector2(170, 554))
	check(game.player.backpack.get("Iron Helmet", 0) == 10, "Rows overlapping the old chat HUD remain clickable")
	await capture("f6-smithing-items")
	get_tree().root.size = Vector2i(960, 540)
	await frames()
	menu.quantity.value = 1
	await click(menu.get_global_transform_with_canvas() * Vector2(170, 212))
	check(game.player.backpack.get("Bronze Ore", 0) == 11, "Item row coordinates follow the original UI scale after resize")
	get_tree().root.size = Vector2i(1280, 720)
	await frames()
	await key(KEY_PAGEDOWN)
	check(menu.page_index == 1, "Original PageDown still pages")
	await key(KEY_PAGEUP)
	check(menu.page_index == 0, "Original PageUp still pages")
	menu.view_picker.select(1)
	menu.view_picker.item_selected.emit(1)
	check(menu.display_ids.size() == GameData.items_by_id.size(), "Original complete catalog remains in All Items")
	var before_restricted: Dictionary = game.player.backpack.duplicate(true)
	for view in [0, 1]:
		menu.view_picker.select(view)
		for id in [180, 256, 257, 258, 259, 328]:
			menu._give_item(GameData.get_item(id))
			check(game.player.backpack == before_restricted and menu.status_text.contains("Starforged"), "Neither F6 view grants Starforged gear or resources: " + str(id))
	menu.view_picker.select(0)
	menu.view_picker.item_selected.emit(0)
	menu.quantity.value = 1
	var equipped_before: Dictionary = game.player.equipment.duplicate(true)
	for digit: String in str(int(GameData.get_item_by_name("Adamantite Dagger").id)):
		await key(digit.unicode_at(0) as Key)
	await key(KEY_ENTER)
	check(game.player.backpack.get("Adamantite Dagger", 0) == 1 and game.player.equipment == equipped_before, "Typed IDs remain usable and locked equipment stays in backpack")
	menu.visible_input = str(int(GameData.get_item_by_name("Bronze Bow").id))
	await key(KEY_ENTER)
	check(not game.player.backpack.has("Bronze Bow"), "Smithing view cannot grant excluded bows by ID")
	game.player.backpack["Bronze Ore"] = 9223372036854775807
	menu.quantity.value = 10
	await click(menu.get_global_transform_with_canvas() * Vector2(170, 212))
	check(game.player.backpack["Bronze Ore"] == 9223372036854775807, "Developer quantity cannot overflow material stacks")
	var inventory: Dictionary = game.player.backpack.duplicate(true)
	Network.mode = Network.Mode.CLIENT
	menu._give_item(GameData.get_item_by_name("Bronze Ingot"))
	Network.mode = Network.Mode.OFFLINE
	check(game.player.backpack == inventory, "Direct developer grants remain unavailable online")
	game.player.equipment.weapon = GameData.get_item_by_name("Bronze Dagger")
	menu.quantity.value = 1
	for supplies: Dictionary in [{"Bronze Dagger": 9223372036854775806}, {"Bronze Dagger": 9223372036854775807}]:
		game.player.backpack = supplies.duplicate(true)
		var name_key := "Bronze Dagger" if supplies["Bronze Dagger"] == 9223372036854775806 else "Bronze Shortsword"
		menu._give_item(GameData.get_item_by_name(name_key))
		check(game.player.backpack == supplies and game.player.equipment.weapon == GameData.get_item_by_name("Bronze Dagger"), "Grant preflights returned equipment stack capacity: " + name_key)
	game.player.equipment.shield = GameData.get_item_by_name("Bronze Kiteshield")
	game.player.backpack = {"Bronze Kiteshield": 9223372036854775807}
	menu._give_item(GameData.get_item_by_name("Bronze Warmaul"))
	check(game.player.backpack == {"Bronze Kiteshield": 9223372036854775807} and game.player.equipment.weapon == GameData.get_item_by_name("Bronze Dagger") and not game.player.equipment.shield.is_empty(), "Two-handed replacement cannot overflow its returned shield")
	game.player.backpack.clear()
	menu.quantity.value = 3
	menu._give_item(GameData.get_item_by_name("Bronze Shortsword"))
	check(game.player.backpack == {"Bronze Shortsword": 2, "Bronze Dagger": 1} and game.player.equipment.weapon == GameData.get_item_by_name("Bronze Shortsword"), "Normal quantity grant equips one and preserves old equipment")
	menu.quantity.get_line_edit().grab_focus()
	await key(KEY_F6)
	check(not menu.visible, "F6 closes while editing quantity")
	var anvil: Node2D
	var furnace: Node2D
	for station: Node in get_tree().get_nodes_in_group("crafting_station"):
		if station.station_id == "anvil": anvil = station
		if station.station_id == "furnace": furnace = station
	for station: Node2D in [anvil, furnace]:
		while game.grid_adapter != null and not game.grid_adapter.completed:
			await get_tree().physics_frame
		var point: Vector2 = station.simulation_position
		if game.world.grid != null:
			var route: PackedVector2Array = game.world.grid.path(game.player.get_position(), point, 2.5)
			check(not route.is_empty(), "Station has a reachable grid approach")
			if not route.is_empty(): point = route[-1]
		var actor: CombatActor = game.combat.actors[game.player.entity_id]
		actor.x = point.x
		actor.y = point.y
		game.player.x = point.x
		game.player.y = point.y
		game._update_sprite_position(actor.entity_id)
		game.request_crafting(station)
		var names: Array[String] = []
		for button: Node in game.crafting_panel.content.get_children():
			if not button is Button: continue
			var recipe := CraftingService._find_recipe(String(button.get_meta("recipe_id", "")))
			check(bool(recipe.get("enabled", false)) and button.icon != null, "Only completed recipes with an image are shown")
			check(not button.text.to_lower().contains("bow"), "No bows or crossbow components in smithing station menu")
			for output: Dictionary in recipe.outputs: names.append(String(output.item))
		for metal: String in METALS:
			check(names.has(metal + (" Dagger" if station == anvil else " Ingot")), "Station menu covers existing material: " + metal)
		await capture("anvil-completed-items" if station == anvil else "all-ore-ingot-recipes")
		game.player.backpack = {"Adamantite Ingot": 5} if station == anvil else {"Iron Ore": 2, "Coal": 2}
		game.crafting_panel.amount.value = 1 if station == anvil else 2
		var recipe_id := "adamantite_platebody" if station == anvil else "smelt_steel"
		for button: Node in game.crafting_panel.content.get_children():
			if button.get_meta("recipe_id", "") == recipe_id:
				var scroll := game.crafting_panel.content.get_parent() as ScrollContainer
				await frames()
				scroll.ensure_control_visible(button)
				await frames()
				await click(button.get_global_transform_with_canvas() * (button.size / 2.0))
				break
		check(game.player.backpack == ({"Adamantite Platebody": 1} if station == anvil else {"Steel Ingot": 2}), "Actual station button spends exact higher-tier/alloy ingredients: " + recipe_id)
		await key(KEY_ESCAPE)
		check(not game.crafting_panel.visible, "Escape closes the original station menu")
	scene.queue_free()
	await frames()

func _finish() -> void:
	print("[Smithing catalog] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
