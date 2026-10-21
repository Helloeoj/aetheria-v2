extends Node

const DATA_ROOT := "res://data/"
var items: Array[Dictionary] = []
var items_by_id: Dictionary = {}
var items_by_name: Dictionary = {}
var monsters: Array[Dictionary] = []
var monsters_by_name: Dictionary = {}
var monsters_by_id: Dictionary = {}
var world_data: Dictionary = {}
var loot_data: Dictionary = {}
var set_bonuses: Dictionary = {}
var spells: Array[Dictionary] = []
var spells_by_id: Dictionary = {}

func _ready() -> void:
	items = _load_array("items.json")
	monsters = _load_array("monsters.json")
	world_data = _load_dict("world.json")
	loot_data = _load_dict("loot.json")
	set_bonuses = _load_dict("set_bonuses.json")
	spells = _load_array("spells.json")
	for item: Dictionary in items:
		_complete_item_stats(item)
		items_by_id[int(item.get("id", -1))] = item
		items_by_name[String(item.get("name", ""))] = item
	# Keep saved IDs intact while resolving historical display names to the
	# approved replacement. Retired wand records retain their original stats.
	for item: Dictionary in items:
		var canonical: Dictionary = items_by_id.get(int(item.get("canonical_item_id", item.id)), item)
		items_by_name[String(item.name)] = canonical
		for alias: Variant in item.get("aliases", []):
			items_by_name[String(alias)] = canonical
	for monster: Dictionary in monsters:
		monsters_by_name[String(monster.get("name", "")).to_lower()] = monster
		monsters_by_id[int(monster.get("id", -1))] = monster
	for spell: Dictionary in spells:
		var spell_id := String(spell.get("id", ""))
		if spell_id.is_empty():
			push_error("Spell definition is missing an ID.")
			continue
		if spells_by_id.has(spell_id):
			push_error("Duplicate spell ID: " + spell_id)
			continue
		spells_by_id[spell_id] = spell

func get_item(identifier: Variant) -> Dictionary:
	if identifier is int:
		return items_by_id.get(int(identifier), {})
	return get_item_by_name(String(identifier))

func _complete_item_stats(item: Dictionary) -> void:
	for stat_group: String in ["attack_bonuses", "defence_bonuses"]:
		var bonuses: Dictionary = item.get(stat_group, {})
		for style: String in PlayerStats.ALL_STYLES:
			if not bonuses.has(style):
				bonuses[style] = 0
		item[stat_group] = bonuses
	if not item.has("accuracy_bonus"):
		item["accuracy_bonus"] = 0.0

func get_item_by_name(item_name: String) -> Dictionary:
	return items_by_name.get(item_name, {})

func canonical_item_name(item_name: String) -> String:
	var item := get_item_by_name(item_name)
	return String(item.get("name", item_name))

func list_items() -> Array[Dictionary]:
	var visible: Array[Dictionary] = []
	for item: Dictionary in items:
		if not bool(item.get("legacy_placeholder", false)):
			visible.append(item)
	return visible

func get_spell(spell_id: String) -> Dictionary:
	return spells_by_id.get(spell_id, {})

func list_spells() -> Array[Dictionary]:
	return spells.duplicate(true)

func get_unlocked_spells(magic_level: int) -> Array[Dictionary]:
	var unlocked: Array[Dictionary] = []
	for spell: Dictionary in spells:
		if int(spell.get("unlock_level", 101)) <= magic_level:
			unlocked.append(spell)
	unlocked.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_level := int(first.get("unlock_level", 101))
		var second_level := int(second.get("unlock_level", 101))
		if first_level == second_level:
			return String(first.get("id", "")) < String(second.get("id", ""))
		return first_level < second_level
	)
	return unlocked

func is_spell_unlocked(spell_id: String, magic_level: int) -> bool:
	var spell := get_spell(spell_id)
	return not spell.is_empty() and int(spell.get("unlock_level", 101)) <= magic_level

func register_item(item_name: String, item_type: String, material: String, tier: int,
		options: Dictionary = {}) -> Dictionary:
	var definition := options.duplicate(true)
	if item_type == "Weapon" and not definition.has("speed"):
		var inferred := _infer_speed_from_name(item_name)
		if inferred > 0:
			definition["speed"] = inferred
	var item := {
		"id": _next_item_id(), "name": item_name, "type": item_type,
		"material": material, "tier": tier,
		"slot": definition.get("slot", null),
		"attack_bonuses": definition.get("attack_bonuses", {}),
		"defence_bonuses": definition.get("defence_bonuses", {}),
		"accuracy_bonus": definition.get("accuracy_bonus", 0.0),
		"speed": definition.get("speed", null),
		"rarity": definition.get("rarity", "common"),
		"set_name": definition.get("set_name", null),
		"special_effect": definition.get("special_effect", null)
	}
	if definition.has("combat_profiles"):
		item["combat_profiles"] = definition["combat_profiles"].duplicate(true)
	if definition.has("melee_strength_bonus"):
		item["melee_strength_bonus"] = int(definition["melee_strength_bonus"])
	if definition.has("two_handed"):
		item["two_handed"] = bool(definition["two_handed"])
	_complete_item_stats(item)
	items.append(item)
	items_by_id[int(item.id)] = item
	items_by_name[item_name] = item
	return item

func get_monster(identifier: Variant) -> Dictionary:
	if identifier is int:
		return get_monster_by_id(int(identifier))
	return get_monster_by_name(String(identifier))

func get_monster_by_name(monster_name: String) -> Dictionary:
	return monsters_by_name.get(monster_name.strip_edges().to_lower(), {})

func get_monster_by_id(monster_id: int) -> Dictionary:
	return monsters_by_id.get(monster_id, {})

func get_active_monster_templates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for monster: Dictionary in monsters:
		if String(monster.get("family", "")) == "goblins":
			result.append(monster)
	return result

func create_monster_instance(monster_id: int, x: float = 0.0, y: float = 0.0) -> MonsterState:
	var template := get_monster_by_id(monster_id)
	if template.is_empty():
		push_error("Unknown monster ID: %d" % monster_id)
		return null
	return MonsterState.new(template, x, y)

func get_items_for_tier(tier: int) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for item: Dictionary in items:
		if int(item.get("tier", 1)) == tier and not bool(item.get("legacy_placeholder", false)):
			pool.append(item)
	return pool

func _next_item_id() -> int:
	var next_id := 1
	for item_id: Variant in items_by_id:
		next_id = maxi(next_id, int(item_id) + 1)
	return next_id

func _infer_speed_from_name(item_name: String) -> int:
	var defaults := {
		"Dagger": 3, "Shortsword": 4, "Longsword": 5, "Mace": 6,
		"Warmaul": 8, "Bow": 4, "Crossbow": 6, "Magic Staff": 5, "Magic Wand": 3
	}
	for weapon_name: String in defaults:
		if item_name.to_lower().contains(weapon_name.to_lower()):
			return int(defaults[weapon_name])
	return 0

func _load_array(filename: String) -> Array[Dictionary]:
	var value: Variant = _parse(filename)
	var result: Array[Dictionary] = []
	if value is Array:
		for row: Variant in value:
			if row is Dictionary:
				result.append(row)
	return result

func _load_dict(filename: String) -> Dictionary:
	var value: Variant = _parse(filename)
	return value if value is Dictionary else {}

func _parse(filename: String) -> Variant:
	var path := DATA_ROOT + filename
	AetheriaDiagnostics.event("Resources", "load game data", {"resource": path})
	if not FileAccess.file_exists(path):
		push_error("Missing game data: " + path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot open game data: " + path)
		return null
	var value: Variant = JSON.parse_string(file.get_as_text())
	if value == null:
		push_error("Invalid JSON game data: " + path)
	return value
