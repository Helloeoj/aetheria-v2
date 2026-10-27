extends Node
## Real catalog/transactions; fixture mutations are restored before each section ends.
const Rules := preload("res://scripts/acquisition_rules.gd")
const RETIRED := [256, 257]
const RECIPES := ["smelt_starforged", "starforged_dagger", "starforged_shortsword", "starforged_longsword", "starforged_mace", "starforged_warmaul", "starforged_helmet", "starforged_platebody", "starforged_platelegs", "starforged_kiteshield", "starforged_square_shield", "starforged_arrowheads", "starforged_bolts", "starforged_arrows", "starforged_bow", "starforged_crossbow_limbs", "starforged_crossbow"]
var checks := 0
var failures := 0

class Geometry extends Node2D:
	var map_width := 1536.0
	var map_height := 1024.0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Starforged FAIL] " + label)

func _ready() -> void:
	_catalog()
	_crafting()
	_sources()
	_saves()
	_authority()
	print("[Starforged acquisition] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _catalog() -> void:
	var ids := SmithingCatalog.item_ids(GameData.items_by_id)
	var found := 0
	for item: Dictionary in GameData.items:
		if item.get("material") != "Starforged": continue
		found += 1
		var name_key := String(item.name)
		check(not bool(item.get("craftable", true)), "Non-craftable: " + name_key)
		check(not ids.has(int(item.id)), "Outside Smithing progression: " + name_key)
		check(not CraftingService._output_allowed("salvage_reconstruction", name_key), "No manufacturing regardless of recipe name: " + name_key)
		check(not Rules.can_purchase(item) and not Rules.can_mine(item), "Drop-only or retired: " + name_key)
		if int(item.id) in RETIRED:
			check(bool(item.get("legacy_placeholder", false)), "Retained legacy resource: " + name_key)
			check(item not in GameData.list_items(), "Retired resource hidden: " + name_key)
		else:
			check(bool(item.get("drop_only", false)), "Explicit drop-only metadata: " + name_key)
			check(not bool(item.get("legacy_placeholder", false)), "Live item preserved: " + name_key)
			check(Rules.can_drop(item, {"name": "Golem Titan", "tier": 5}), "Existing boss eligibility preserved: " + name_key)
			if int(item.id) in [180, 181, 182, 183, 184, 189, 190, 191, 192, 193]:
				check(ItemVisualLibrary.texture(name_key) != null, "Existing equipment icon preserved: " + name_key)
	check(found == 19, "All existing canonical Starforged records covered")
	check(not CraftingService._output_allowed("reconstruct", "Runite Dagger"), "Historical alias cannot manufacture gear")
	check(CraftingService._output_allowed("celestial_staff", "Starforged Magic Staff"), "Celestial staff alias is not banned by spelling")
	check(CraftingService._output_allowed("celestial_cape", "Starforged Cape"), "Celestial cape alias is not banned by spelling")

func _crafting() -> void:
	var player := PlayerState.new()
	for id: String in RECIPES:
		check(CraftingService._find_recipe(id).is_empty(), "Removed recipe: " + id)
		player.backpack = {"Starforged Ore": 100, "Starforged Ingot": 100, "Starforged Arrowheads": 100}
		var before := player.backpack.duplicate(true)
		for station: String in ["anvil", "furnace", "fletching"]:
			player.backpack = before.duplicate(true)
			check(not CraftingService.craft(player, id, station).ok and player.backpack == before, "Stale recipe rejected atomically: " + id + "/" + station)
	for recipe: Dictionary in CraftingService.list_recipes():
		for field: String in ["inputs", "outputs", "planned_inputs", "planned_outputs"]:
			for entry: Variant in recipe.get(field, []):
				var item_name := String(entry.get("item", "")) if entry is Dictionary else String(entry)
				var item := GameData.get_item_by_name(item_name)
				check(item.get("material") != "Starforged", "No remaining recipe dependency: " + String(recipe.id))
	# A future/incorrect enabled recipe must fail even if its ID is not Starforged.
	var original_output: Dictionary = GameData.items_by_name["Bronze Dagger"]
	GameData.items_by_name["Bronze Dagger"] = GameData.get_item(180)
	player.backpack = {"Bronze Ingot": 1}
	check(not CraftingService.craft(player, "bronze_dagger", "anvil").ok and player.backpack == {"Bronze Ingot": 1}, "Enabled recipe cannot convert materials into Starforged")
	GameData.items_by_name["Bronze Dagger"] = original_output
	var original_input: Dictionary = GameData.items_by_name["Bronze Ingot"]
	GameData.items_by_name["Bronze Ingot"] = GameData.get_item(257)
	player.backpack = {"Starforged Ingot": 1}
	check(not CraftingService.craft(player, "bronze_dagger", "anvil").ok and player.backpack == {"Starforged Ingot": 1}, "Legacy ingot cannot feed another conversion")
	GameData.items_by_name["Bronze Ingot"] = original_input
	player.backpack = {"Bronze Ingot": 1}
	check(CraftingService.craft(player, "bronze_dagger", "anvil").ok and player.backpack == {"Bronze Dagger": 1}, "Unrelated crafting still works")

func _sources() -> void:
	for id: int in RETIRED:
		var item := GameData.get_item(id)
		for monster: Dictionary in GameData.monsters:
			check(not Rules.can_drop(item, monster), "No monster source for " + String(item.name) + ": " + String(monster.name))
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mining.json"))
		data.ores[0].item_id = id
		var definitions := MiningDefinitions.new()
		check(not definitions.load_records(data).ok and definitions.ore(id).is_empty(), "Mining rejects retired resource even if configured")
	var saved: Dictionary = GameData.loot_data.families
	GameData.loot_data.families = {"test": {"Golem Titan": {"guaranteed": [{"item": "Starforged Ore"}, {"item": "Starforged Ingot"}, {"item": "Runite Dagger"}], "common": {"attempts": 0}, "rare": {"table_chance": 0}}}}
	var result := LootSystem.new().roll_monster_loot({"name": "Golem Titan", "tier": 5})
	GameData.loot_data.families = saved
	check(result.items.size() == 1 and result.items[0].item.id == 180, "Actual loot rejects retired resources but preserves alias gear eligibility")

func _saves() -> void:
	var player := PlayerState.new("Legacy Starforged")
	player.entity_id = "starforged-test"
	for skill: String in SkillProgression.SKILL_IDS: player.set_skill_level(skill, 100)
	player.backpack = {"Starforged Ore": 17, "Starforged Ingot": 23, "Runite Dagger": 1, "Starforged Bolts": 8}
	InventorySystem.normalize_backpack(player)
	player.equip_item("Starforged Dagger")
	check(int(player.equipment.weapon.get("id", 0)) == 180, "Existing equipment still equips through old alias")
	var stats := player.get_combat_stats()
	for version in [1, 2, 3, CharacterCodec.VERSION]:
		var state := CharacterCodec.encode(player, "outskirts")
		state.version = version
		var restored := CharacterCodec.decode(JSON.parse_string(JSON.stringify(state)), player.name, player.entity_id)
		check(restored.ok, "Legacy save version loads: " + str(version))
		if not restored.ok: continue
		check(restored.player.backpack == player.backpack, "Old resource and ammunition counts survive: " + str(version))
		check(restored.player.equipment.weapon == player.equipment.weapon and restored.player.get_combat_stats() == stats, "Equipment and combat survive save/load: " + str(version))

func _authority() -> void:
	var geometry := Geometry.new()
	add_child(geometry)
	var station := CraftingStation.new()
	station.setup("anvil", "Anvil", Vector2(10, 10))
	geometry.add_child(station)
	var region := AuthoritativeRegion.new()
	region.configure("starforged-test", geometry)
	var player := PlayerState.new()
	region.add_player("starforged-test", player)
	player.backpack = {"Starforged Ingot": 5}
	var result := region.submit(player.entity_id, {"type": "craft", "station_id": region.stations.keys()[0], "recipe_id": "starforged_platebody", "quantity": 1})
	check(not result.ok and player.backpack == {"Starforged Ingot": 5}, "Authority rejects stale manufacturing commands without consuming saved stock")
	region.remove_player(player.entity_id)
	geometry.free()
