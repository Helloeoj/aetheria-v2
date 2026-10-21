class_name LootSystem
extends RefCounted

const Acquisition = preload("res://scripts/acquisition_rules.gd")

const GOLD_TABLE := {
	1: [3, 10], 2: [5, 18], 3: [10, 28], 4: [18, 40],
	5: [25, 60], 6: [40, 95], 7: [75, 150]
}

var random := RandomNumberGenerator.new()

func _init() -> void:
	random.randomize()

func roll_monster_loot(monster: Variant) -> Dictionary:
	var tier := int(monster.tier) if monster is Object else int(monster.get("tier", 1))
	var gold_range: Array = GOLD_TABLE.get(tier, GOLD_TABLE[7])
	var gold := random.randi_range(int(gold_range[0]), int(gold_range[1]))
	var monster_table := _get_monster_loot_table(monster)
	if not monster_table.is_empty():
		return {"gold": gold, "items": _roll_explicit_monster_table(monster_table, monster)}
	return _roll_generic_loot(tier, gold, monster)

func roll_loot(monster: Variant) -> Dictionary:
	return roll_monster_loot(monster)

func _roll_generic_loot(tier: int, gold: int, monster: Variant = null) -> Dictionary:
	if random.randf() > 0.40:
		return {"gold": gold, "item": null, "quantity": 0}
	var chosen_tier := _choose_loot_tier(tier)
	var weapon_roll := random.randi_range(1, 50) == 1
	var accessory_roll := random.randi_range(1, 150) == 1
	if weapon_roll:
		return {"gold": gold, "item": _roll_weapon_or_armor(chosen_tier, monster), "quantity": 1}
	if accessory_roll:
		return {"gold": gold, "item": _roll_accessory(chosen_tier, monster), "quantity": 1}
	var general_item := _roll_basic_item(chosen_tier, monster)
	return {"gold": gold, "item": null if general_item.is_empty() else general_item, "quantity": 0 if general_item.is_empty() else _determine_stack_size(general_item)}

func roll_artifact_loot() -> Variant:
	var artifacts: Array[Dictionary] = []
	for item: Dictionary in GameData.items:
		if bool(item.get("is_artifact", false)):
			artifacts.append(item)
	return null if artifacts.is_empty() else artifacts[random.randi_range(0, artifacts.size() - 1)]

func get_family_loot_table(family: String) -> Dictionary:
	var families: Dictionary = GameData.loot_data.get("families", {})
	return families.get(family.strip_edges().to_lower(), {})

func _get_monster_loot_table(monster: Variant) -> Dictionary:
	var monster_name := String(monster.name) if monster is Object else String(monster.get("name", ""))
	if monster_name.is_empty():
		return {}
	var families: Dictionary = GameData.loot_data.get("families", {})
	for family_value: Variant in families.values():
		if not family_value is Dictionary:
			continue
		var table: Variant = family_value.get(monster_name, {})
		if table is Dictionary and table.has("common") and table.has("rare"):
			return table
	return {}

func _roll_explicit_monster_table(table: Dictionary, monster: Variant = null) -> Array[Dictionary]:
	var drops: Array[Dictionary] = []
	for guaranteed_entry: Variant in table.get("guaranteed", []):
		_add_explicit_drop(drops, guaranteed_entry, "guaranteed", monster)

	var common: Dictionary = table.get("common", {})
	var common_attempts := maxi(0, int(common.get("attempts", 0)))
	var common_outcomes: Array = common.get("outcomes", [])
	for _attempt in range(common_attempts):
		var result: Variant = _roll_weighted_outcome(common_outcomes)
		if result is Dictionary and result.get("item", null) != null:
			_add_explicit_drop(drops, result, "common", monster)

	var rare: Dictionary = table.get("rare", {})
	var rare_chance := clampf(float(rare.get("table_chance", 0.0)), 0.0, 100.0)
	if random.randf() * 100.0 < rare_chance:
		var rare_result: Variant = _roll_weighted_outcome(rare.get("outcomes", []))
		if rare_result is Dictionary and rare_result.get("item", null) != null:
			_add_explicit_drop(drops, rare_result, "rare", monster)
	return drops

func _roll_weighted_outcome(outcomes: Array) -> Variant:
	var total_weight := 0.0
	for outcome: Variant in outcomes:
		if outcome is Dictionary:
			total_weight += maxf(0.0, float(outcome.get("chance", 0.0)))
	if total_weight <= 0.0:
		return null
	var roll := random.randf() * total_weight
	var cumulative := 0.0
	for outcome: Variant in outcomes:
		if not outcome is Dictionary:
			continue
		cumulative += maxf(0.0, float(outcome.get("chance", 0.0)))
		if roll < cumulative:
			return outcome
	return null

func _add_explicit_drop(drops: Array[Dictionary], entry: Variant, pool_name: String, monster: Variant = null) -> void:
	var item_name := ""
	var quantity_range: Array = [1, 1]
	if entry is String:
		item_name = entry
	elif entry is Dictionary:
		item_name = String(entry.get("item", ""))
		quantity_range = entry.get("quantity", [1, 1])
	if item_name.is_empty():
		return
	var item: Dictionary = GameData.get_item_by_name(item_name)
	if item.is_empty():
		push_warning("Ignoring loot item missing from catalog: " + item_name)
		return
	if not Acquisition.can_drop(item, monster):
		return
	var minimum := int(quantity_range[0]) if quantity_range.size() > 0 else 1
	var maximum := int(quantity_range[1]) if quantity_range.size() > 1 else minimum
	drops.append({
		"item": item,
		"quantity": random.randi_range(minimum, maxi(minimum, maximum)),
		"pool": pool_name
	})

func _choose_loot_tier(monster_tier: int) -> int:
	if monster_tier <= 1:
		return 1
	var roll := random.randf()
	if roll < 0.65:
		return monster_tier
	if roll < 0.85 and monster_tier > 1:
		return monster_tier - 1
	return 1

func _tier_pools(tier: int, monster: Variant = null) -> Dictionary:
	var weapons: Array[Dictionary] = []
	var armor: Array[Dictionary] = []
	var accessories: Array[Dictionary] = []
	var general: Array[Dictionary] = []
	for item: Dictionary in GameData.items:
		if bool(item.get("is_artifact", false)) or int(item.get("tier", 1)) != tier:
			continue
		if not bool(item.get("generic_loot", true)):
			continue
		if not Acquisition.can_drop(item, monster):
			continue
		var item_type := String(item.get("type", "")).to_lower()
		var slot_value: Variant = item.get("slot", null)
		var item_slot := "" if slot_value == null else String(slot_value).to_lower()
		if item_type == "weapon":
			weapons.append(item)
		elif item_type == "accessory" or item_slot in ["ring", "neck", "cape"]:
			accessories.append(item)
		elif item_type == "armor":
			armor.append(item)
		else:
			general.append(item)
	return {"weapons": weapons, "armor": armor, "accessories": accessories, "general": general}

func _roll_basic_item(tier: int, monster: Variant = null) -> Dictionary:
	var pools := _tier_pools(tier, monster)
	var pool: Array = pools.general
	if pool.is_empty():
		pool = _tier_pools(1, monster).general
	return {} if pool.is_empty() else pool[random.randi_range(0, pool.size() - 1)]

func _roll_weapon_or_armor(tier: int, monster: Variant = null) -> Dictionary:
	var pools := _tier_pools(tier, monster)
	var candidates: Array = []
	if not pools.weapons.is_empty():
		candidates.append(pools.weapons)
	if not pools.armor.is_empty():
		candidates.append(pools.armor)
	if candidates.is_empty():
		return _roll_basic_item(tier, monster)
	var chosen: Array = candidates[random.randi_range(0, candidates.size() - 1)]
	return chosen[random.randi_range(0, chosen.size() - 1)]

func _roll_accessory(tier: int, monster: Variant = null) -> Dictionary:
	var pool: Array = _tier_pools(tier, monster).accessories
	if pool.is_empty():
		return _roll_basic_item(tier, monster)
	return pool[random.randi_range(0, pool.size() - 1)]

func _determine_stack_size(item: Dictionary) -> int:
	if String(item.get("type", "")).to_lower() in ["crafting", "food"]:
		return random.randi_range(1, 3)
	return 1
