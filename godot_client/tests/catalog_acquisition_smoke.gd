extends Node
## Run matching scenes/dev_tools/catalog_acquisition_smoke.tscn for autoloads.

var checks := 0
var failures: Array[String] = []
var data: Node

func _ready() -> void:
	_run()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("[Crafting acquisition] " + label)

func _run() -> void:
	data = get_tree().root.get_node("GameData")
	_check_catalog()
	_check_legacy_inventory()
	if ResourceLoader.exists("res://scripts/acquisition_rules.gd"):
		_check_policies(load("res://scripts/acquisition_rules.gd"))
	else:
		_check(false, "Acquisition rules must exist")
	if failures.is_empty():
		print("[Crafting acquisition] PASS: %d checks." % checks)
		get_tree().quit(0)
	else:
		printerr("[Crafting acquisition] FAIL: %d of %d checks." % [failures.size(), checks])
		get_tree().quit(1)

func _check_catalog() -> void:
	_check(String(data.get_item(157).name) == "Galehunter\u2019s Garb Mask", "Existing artifact Unicode name is preserved")
	_check(String(data.get_item(157).set_name) == "Galehunter\u2019s Garb", "Existing artifact set identity is preserved")
	var seen_ids := {}
	var seen_names := {}
	for item: Dictionary in data.items:
		_check(not seen_ids.has(item.id), "Unique ID: %d" % int(item.id))
		_check(not seen_names.has(item.name), "Unique name: " + String(item.name))
		seen_ids[item.id] = true
		seen_names[item.name] = true
		if not bool(item.get("is_artifact", false)) and item.get("slot", "") == "cape":
			_check(item.get("crafting_skill", "") == "tailoring", "Cape belongs to Tailoring: " + String(item.name))
			_check(item.get("material", "") == "Cloth", "Cape is cloth: " + String(item.name))
	var renamed: Dictionary = data.get_item_by_name("Starforged Dagger")
	_check(not renamed.is_empty(), "Starforged replaces Runite")
	_check(data.get_item_by_name("Runite Dagger") == renamed, "Runite lookup alias preserves old references")
	for item_name: String in ["Starter Hide", "Tanned Leather", "Tanned Leather Coif", "Tanned Leather Tunic", "Tanned Leather Chaps", "Bronze Ingot", "Magic Orb", "Animal Sinew", "Starforged Ore", "Aetherwyrm Leather", "Celestial Cloth"]:
		_check(not data.get_item_by_name(item_name).is_empty(), "Crafting item exists: " + item_name)
	for element: String in ["Fire", "Ice", "Lightning", "Hurricane"]:
		_check(not data.get_item_by_name(element + " Sigil").is_empty(), element + " Sigil exists")
		_check(not data.get_item_by_name(element + " Orb").is_empty(), element + " Orb exists")
	var wand: Dictionary = data.get_item(9)
	_check(bool(wand.get("legacy_placeholder", false)), "Old wand record is retained but retired")
	_check(int(data.get_item_by_name("Bronze Magic Wand").get("id", -1)) == 9, "Old wand name preserves original item ID")
	_check(not bool(wand.get("generic_loot", true)), "Retired wand cannot generate from loot")
	_check(int(wand.get("speed", 0)) == 3, "Retired wand ID keeps original speed")
	_check(int(data.get_item_by_name("Apprentice Magic Staff").get("speed", 0)) == 5, "Canonical staff retains original speed")
	_check(wand not in data.list_items(), "Retired record is hidden in item browser")
	_check(wand not in data.get_items_for_tier(1), "Retired record is hidden in tier catalog")
	for prefix: String in ["Apprentice", "Adept", "Runic", "Enchanted", "Astral", "Empyrean", "Celestial"]:
		var base: Dictionary = data.get_item_by_name(prefix + " Magic Staff")
		for element: String in ["Fire", "Ice", "Lightning", "Hurricane"]:
			var variant: Dictionary = data.get_item_by_name(prefix + " Magic Staff (" + element + ")")
			_check(variant.get("orb_element", "") == element.to_lower(), "Staff stores elemental identity")
			_check(variant.get("attack_bonuses", {}) == base.get("attack_bonuses", {}), "Element does not rebalance staff attack")
			_check(variant.get("speed", 0) == base.get("speed", 0), "Element does not rebalance staff speed")
			_check(not bool(variant.get("generic_loot", true)), "Empowered staff cannot enter generic pool")

func _check_legacy_inventory() -> void:
	var entries := [[9, "Bronze"], [31, "Iron"], [52, "Steel"], [61, "Blacksteel"], [81, "Mithril"], [102, "Adamantite"], [188, "Runite"]]
	for entry: Array in entries:
		var old_name := String(entry[1]) + " Magic Wand"
		var old_id := int(entry[0])
		# Keep the old item's numerical fields and infer its historical projectile
		# and handedness from the pre-migration name, as the baseline game did.
		var historical: Dictionary = data.get_item(old_id).duplicate(true)
		historical["name"] = old_name
		historical.erase("projectile_type")
		historical.erase("two_handed")
		var expected_player := PlayerState.new("Historical weapon fixture")
		var actual_player := PlayerState.new("Saved inventory fixture")
		for skill: String in SkillProgression.SKILL_IDS:
			expected_player.set_skill_level(skill, 100)
			actual_player.set_skill_level(skill, 100)
		expected_player.equipment["weapon"] = historical
		expected_player.attack_style = "magic"
		actual_player.backpack[old_name] = 1
		InventorySystem.inventory_slots(actual_player)
		actual_player.equip_item(old_name)
		actual_player.attack_style = "magic"
		var equipped: Dictionary = actual_player.equipment.get("weapon", {})
		_check(int(equipped.get("id", -1)) == old_id, "Opening/equipping saved wand retains ID: " + old_name)
		_check(String(equipped.get("name", "")).contains("Magic Staff"), "Historical weapon uses staff terminology")
		_check(not String(equipped.get("name", "")).contains("Wand"), "Historical weapon has no separate wand display family")
		var expected_stats := expected_player.get_combat_stats()
		var actual_stats := actual_player.get_combat_stats()
		for field: String in ["min_damage", "max_damage", "accuracy", "attack_interval_seconds", "projectile_speed", "attack_range"]:
			_check(is_equal_approx(float(actual_stats.get(field, -1)), float(expected_stats.get(field, -2))), "Saved wand preserves " + field + ": " + old_name)
		_check(not EquipmentUtils.is_two_handed(equipped), "Historical weapon remains one handed: " + old_name)
		actual_player.add_item("Bronze Kiteshield")
		actual_player.equip_item("Bronze Kiteshield")
		_check(not actual_player.equipment.get("shield", {}).is_empty(), "Historical weapon keeps shield compatibility: " + old_name)
		_check(data.get_item_by_name(old_name).get("id", -1) == old_id, "Alias preserves old wand ID: " + old_name)

func _check_policies(rules: GDScript) -> void:
	var ordinary := {"name": "Goblin Scout", "tier": 7, "family": "goblins", "is_boss": true}
	var titan := {"name": "Golem Titan", "tier": 5}
	var aetherwyrm := {"name": "Aetherwyrm", "tier": 7}
	for item_name: String in ["Starforged Ore", "Starforged Ingot", "Aetherwyrm Leather", "Celestial Cloth"]:
		var item: Dictionary = data.get_item_by_name(item_name)
		_check(not rules.can_drop(item, ordinary), "No normal monster top material: " + item_name)
		_check(not rules.can_purchase(item), "No shop top material: " + item_name)
	_check(rules.can_drop(data.get_item_by_name("Starforged Ore"), titan), "Titan supplies Starforged Ore despite existing tier 5")
	_check(not rules.can_drop(data.get_item_by_name("Starforged Ore"), aetherwyrm), "Other boss cannot drop Starforged Ore")
	_check(rules.can_drop(data.get_item_by_name("Aetherwyrm Leather"), aetherwyrm), "Aetherwyrm supplies its leather")
	_check(not rules.can_drop(data.get_item_by_name("Celestial Cloth"), titan), "Celestial boss remains unresolved")
	_check(not rules.can_drop({"name": "Unconfigured Tier 7 Material", "type": "Crafting", "tier": 7}, titan), "Missing top-tier policy fails closed")
	_check(not rules.can_drop(data.get_item_by_name("Fire Sigil"), ordinary), "Boss flag on goblin does not qualify for sigils")
	_check(rules.can_drop(data.get_item_by_name("Fire Sigil"), titan), "Configured boss qualifies for sigil eligibility")
	_check(rules.can_drop(data.get_item_by_name("Magic Orb"), {"name": "Cultist Initiate", "tier": 1}), "Cultist can drop plain orb")
	_check(not rules.can_drop(data.get_item_by_name("Magic Orb"), ordinary), "Noncultist cannot drop orb")
	for monster_name: String in ["Goblin Scout", "Bandit Boss", "Troll Matron", "Cultist Initiate", "Kobold King", "Harpy Matriarch"]:
		_check(not rules.can_drop(data.get_item_by_name("Animal Sinew"), {"name": monster_name, "tier": 7}), "No humanoid sinew: " + monster_name)
	for monster_name: String in ["Wolf Cub", "Bat Flutter", "Spider Creeper"]:
		_check(rules.can_drop(data.get_item_by_name("Animal Sinew"), {"name": monster_name, "tier": 1}), "Beast sinew: " + monster_name)
	for item_name: String in ["Beginner Rod", "Apprentice Rod", "Pro Rod", "Master Rod"]:
		var item: Dictionary = data.get_item_by_name(item_name)
		_check(rules.can_purchase(item), "Bait shop rod: " + item_name)
		_check(not rules.can_drop(item, titan), "Shop rod excluded from drops: " + item_name)
	_check(not rules.can_purchase(data.get_item_by_name("Demon Rod")), "Demon Rod cannot be purchased")
	_check(rules.can_drop(data.get_item_by_name("Demon Rod"), {"name": "Demon Overlord", "tier": 7}), "Demon Overlord supplies Demon Rod")
	_check(not rules.can_drop(data.get_item_by_name("Demon Rod"), titan), "Other bosses cannot supply Demon Rod")
	for item_name: String in ["Low Grade Fish Food", "Medium Grade Fish Food", "High Grade Fish Food"]:
		_check(rules.can_purchase(data.get_item_by_name(item_name)), "Bait is sold: " + item_name)
		_check(rules.can_drop(data.get_item_by_name(item_name), ordinary), "Bait can drop: " + item_name)
	var loot: RefCounted = load("res://scripts/loot_system.gd").new()
	loot.random.seed = 437
	var denied_names := ["Starforged Ore", "Aetherwyrm Leather", "Celestial Cloth", "Demon Rod", "Animal Sinew", "Magic Orb", "Beginner Rod"]
	var guaranteed: Array = []
	for item_name: String in denied_names:
		guaranteed.append({"item": item_name, "quantity": [1, 1]})
	var poison_table := {"guaranteed": guaranteed, "common": {"attempts": 0}, "rare": {"table_chance": 0}}
	data.loot_data["families"]["policy_test"] = {"Goblin Scout": poison_table}
	# Place this table first so it wins over the actual goblin family.
	var saved: Dictionary = data.loot_data["families"]
	data.loot_data["families"] = {"policy_test": {"Goblin Scout": poison_table}}
	var denied: Dictionary = loot.roll_monster_loot(ordinary)
	_check(denied.get("items", []).is_empty(), "Real explicit loot rejects prohibited source injection")
	data.loot_data["families"] = saved
	data.loot_data["families"].erase("policy_test")
	for attempt in range(300):
		var result: Dictionary = loot.roll_monster_loot({"name": "Uncatalogued Goblin", "tier": 7})
		var item: Variant = result.get("item", null)
		if item is Dictionary:
			_check(rules.can_drop(item, {"name": "Uncatalogued Goblin", "tier": 7}), "Real generic loot respects acquisition policy")
