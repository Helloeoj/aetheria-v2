extends Node
## Actual catalog exchanges, world station buttons and authoritative commands.
const CASES := [
	["smelt_bronze", "furnace", {"Bronze Ore": 1}, "Bronze Ingot", 1],
	["bronze_dagger", "anvil", {"Bronze Ingot": 1}, "Bronze Dagger", 1],
	["bronze_shortsword", "anvil", {"Bronze Ingot": 2}, "Bronze Shortsword", 1],
	["bronze_longsword", "anvil", {"Bronze Ingot": 3}, "Bronze Longsword", 1],
	["bronze_mace", "anvil", {"Bronze Ingot": 3}, "Bronze Mace", 1],
	["bronze_warmaul", "anvil", {"Bronze Ingot": 4}, "Bronze Warmaul", 1],
	["bronze_helmet", "anvil", {"Bronze Ingot": 2}, "Bronze Helmet", 1],
	["bronze_platebody", "anvil", {"Bronze Ingot": 5}, "Bronze Platebody", 1],
	["bronze_platelegs", "anvil", {"Bronze Ingot": 3}, "Bronze Platelegs", 1],
	["bronze_kiteshield", "anvil", {"Bronze Ingot": 3}, "Bronze Kiteshield", 1],
	["bronze_square_shield", "anvil", {"Bronze Ingot": 2}, "Bronze Square Shield", 1],
	["bronze_arrowheads", "anvil", {"Bronze Ingot": 1}, "Bronze Arrowheads", 15],
	["bronze_bolts", "anvil", {"Bronze Ingot": 1}, "Bronze Bolts", 15],
	["bronze_arrows", "fletching", {"Arrow Shafts": 15, "Feathers": 15, "Bronze Arrowheads": 15}, "Bronze Arrows", 15]
]
class Geometry extends Node2D:
	var map_width := 1536.0
	var map_height := 1024.0

var checks := 0
var failures := 0
var capture_dir := ""

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("[Bronze recipes FAIL] " + label)

func _ready() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="): capture_dir = argument.trim_prefix("--capture=")
	get_tree().create_timer(50.0).timeout.connect(func() -> void: get_tree().quit(1))
	_run.call_deferred()

func _run() -> void:
	_transactions()
	_authority()
	await _station_ui()
	_placeholders()
	print("[Bronze recipes] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _supplies(player: PlayerState, entry: Array, batches: int) -> void:
	for name_key: String in entry[2]:
		player.add_item(name_key, int(entry[2][name_key]) * batches)

func _transactions() -> void:
	for entry: Array in CASES:
		var player := PlayerState.new()
		_supplies(player, entry, 2)
		var before := player.backpack.duplicate(true)
		var result := CraftingService.craft(player, entry[0], entry[1], 2)
		check(bool(result.ok), "Executable Bronze recipe: " + entry[0])
		if result.ok:
			check(player.backpack == {entry[3]: int(entry[4]) * 2}, "Exact batch costs/yield: " + entry[0])
			var finished := player.backpack.duplicate(true)
			check(not CraftingService.craft(player, entry[0], entry[1]).ok and player.backpack == finished, "Repeated request cannot produce free items: " + entry[0])
		else:
			check(player.backpack == before, "Disabled request preserves ingredients")
		player.backpack.clear()
		_supplies(player, entry, 1)
		player.remove_item(String(entry[2].keys()[0]), 1)
		before = player.backpack.duplicate(true)
		check(not CraftingService.craft(player, entry[0], entry[1]).ok and player.backpack == before, "Missing one ingredient rejects atomically: " + entry[0])
	for id: String in ["bronze_bow", "bronze_crossbow", "bronze_crossbow_limbs"]:
		var player := PlayerState.new()
		player.add_item("Bronze Ingot", 100)
		var recipe := CraftingService._find_recipe(id)
		check(not bool(recipe.get("enabled", false)), "Excluded bow recipe stays disabled: " + id)
		check(not CraftingService.craft(player, id, String(recipe.station)).ok and player.backpack == {"Bronze Ingot": 100}, "Excluded bow route remains unavailable at its own station: " + id)
	for recipe: Dictionary in CraftingService.list_recipes():
		if not bool(recipe.get("enabled", false)): continue
		for entry: Dictionary in recipe.outputs:
			check(String(entry.item) not in ["Bronze Ring", "Bronze Necklace"], "Jewelry retains its drop-only acquisition")

func _authority() -> void:
	var geometry := Geometry.new()
	add_child(geometry)
	for station_id: String in ["furnace", "anvil", "fletching"]:
		var station := CraftingStation.new()
		station.name = station_id
		station.setup(station_id, station_id.capitalize(), Vector2(10, 10))
		geometry.add_child(station)
	var region := AuthoritativeRegion.new()
	region.configure("bronze-recipes", geometry)
	var station_ids := {}
	for registered_id: String in region.stations:
		station_ids[String(region.stations[registered_id].station)] = registered_id
	check(station_ids.size() == 3, "Server discovers all real fixture stations")
	var player := PlayerState.new()
	region.add_player("bronze-tester", player)
	for entry: Array in CASES:
		player.backpack.clear()
		_supplies(player, entry, 1)
		var command: Dictionary = JSON.parse_string(JSON.stringify({"type": "craft", "station_id": station_ids[entry[1]], "recipe_id": entry[0], "quantity": 1}))
		var result: Dictionary = region.submit(player.entity_id, command)
		check(bool(result.ok) and player.backpack == {entry[3]: entry[4]}, "Server validates and produces Bronze recipe: " + entry[0])
		var before := player.backpack.duplicate(true)
		check(not region.submit(player.entity_id, command).ok and player.backpack == before, "Server repeat cannot duplicate output: " + entry[0])
	player.backpack = {"Bronze Ingot": 5}
	var before := player.backpack.duplicate(true)
	check(not region.submit(player.entity_id, {"type": "craft", "station_id": station_ids.furnace, "recipe_id": "bronze_platebody", "quantity": 1}).ok and player.backpack == before, "Server rejects the wrong station")
	player.x = 30.0
	check(not region.submit(player.entity_id, {"type": "craft", "station_id": station_ids.anvil, "recipe_id": "bronze_platebody", "quantity": 1}).ok and player.backpack == before, "Server rejects a distant station")
	var codec: Script = load("res://network/character_codec.gd")
	var restored: Dictionary = codec.decode(JSON.parse_string(JSON.stringify(codec.encode(player, "outskirts"))), "Bronze tester", player.entity_id)
	check(bool(restored.ok) and restored.player.backpack == player.backpack, "Materials survive the existing character save codec")
	region.remove_player(player.entity_id)
	geometry.queue_free()

func _station_ui() -> void:
	var scene: Node = load("res://scenes/EastOutskirtsLayered.tscn").instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var game: Node = scene.get_node("Combat")
	game.set_physics_process(false)
	for entry: Array in CASES:
		var station: Node2D
		for candidate: Node in get_tree().get_nodes_in_group("crafting_station"):
			if candidate.station_id == entry[1]: station = candidate
		check(station != null, "World contains recipe station: " + entry[1])
		if station == null: continue
		game.player.backpack.clear()
		_supplies(game.player, entry, 1)
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
		var button: Button
		for candidate: Node in game.crafting_panel.content.get_children():
			if candidate.get_meta("recipe_id", "") == entry[0]: button = candidate
		check(button != null and not button.disabled, "Existing UI exposes enabled Bronze recipe: " + entry[0])
		if entry[0] == "bronze_platebody": await _capture("bronze-anvil-recipes")
		if button != null and not button.disabled:
			button.pressed.emit()
			check(game.player.backpack == {entry[3]: entry[4]}, "Existing recipe button produces correct output: " + entry[0])
		game.crafting_panel.close()
	game.player.add_item("Bronze Ore", 10)
	game.player.add_item("Bronze Ingot", 10)
	game.inventory_menu.show()
	game.inventory_menu._inspect_item("Bronze Ingot")
	await _capture("bronze-material-placeholders")
	scene.queue_free()
	await get_tree().process_frame

func _capture(label: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless": return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(capture_dir.path_join(label + ".png")) == OK, "Save rendered " + label)

func _placeholders() -> void:
	for material: String in ["Bronze", "Iron", "Steel", "Blacksteel", "Mithril", "Adamantite", "Starforged"]:
		for suffix: String in [" Ore", " Ingot"]:
			var name_key := material + suffix
			var icon := ItemVisualLibrary.texture(name_key)
			check(icon != null and ItemVisualLibrary.texture(name_key, "ground") == icon, "Placeholder visible in inventory and world: " + name_key)
