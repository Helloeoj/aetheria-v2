extends RefCounted
## Eligibility only: a source policy never creates a drop or invents its odds.

static var _policy: Dictionary = {}

static func can_manufacture(item: Dictionary) -> bool:
	# Shared by crafting and any future salvage/reconstruction output. Use the
	# canonical material, not historical name aliases belonging to Celestial gear.
	return not item.is_empty() and item.get("material") != "Starforged" and not bool(item.get("legacy_placeholder", false)) and not bool(item.get("drop_only", false)) and bool(item.get("craftable", true))

static func policy() -> Dictionary:
	if _policy.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/acquisition.json"))
		if parsed is Dictionary:
			_policy = parsed
	return _policy

static func can_drop(item: Dictionary, monster: Variant) -> bool:
	if item.is_empty() or bool(item.get("legacy_placeholder", false)):
		return false
	var rules: Dictionary = policy().get("item_policies", {})
	var rule: Dictionary = rules.get(String(item.get("name", "")), {})
	var top_material := _is_top_material(item)
	# A missing policy must fail closed for the top material tier, even if a
	# future catalog or malformed explicit table forgets its source metadata.
	if top_material and rule.is_empty():
		return false
	if rule.is_empty():
		return true
	var route := String(rule.get("drop_route", "none"))
	if route in ["none", "pending"]:
		return false
	var source := _monster_details(monster)
	if route == "bosses":
		var source_name := String(source.get("name", ""))
		return source_name in policy().get("approved_boss_names", []) and source_name in rule.get("source_names", [])
	if top_material:
		return false
	if route == "names":
		return source.get("name", "") in rule.get("source_names", []) and _tier_allows(item, source)
	if route == "families":
		return source.get("family", "") in rule.get("source_families", []) and _tier_allows(item, source)
	return route == "monster" and not source.is_empty() and _tier_allows(item, source)

static func can_purchase(item: Dictionary) -> bool:
	if item.get("material") == "Starforged":
		return false
	if item.is_empty() or bool(item.get("legacy_placeholder", false)) or _is_top_material(item):
		return false
	var rule: Dictionary = policy().get("item_policies", {}).get(String(item.get("name", "")), {})
	return bool(rule.get("purchase", false))

static func can_mine(item: Dictionary) -> bool:
	if item.get("material") == "Starforged":
		return false
	if item.is_empty() or bool(item.get("legacy_placeholder", false)) or not bool(item.get("generic_loot", true)):
		return false
	if bool(item.get("boss_material", false)) or _is_top_material(item):
		return false
	var rule: Dictionary = policy().get("item_policies", {}).get(String(item.get("name", "")), {})
	return String(rule.get("drop_route", "")) not in ["bosses", "pending", "none"]

static func _is_top_material(item: Dictionary) -> bool:
	return int(item.get("tier", 1)) == int(policy().get("highest_material_tier", 7)) and (
		bool(item.get("boss_material", false)) or String(item.get("type", "")) in ["Crafting", "Ammunition"])

static func _tier_allows(item: Dictionary, source: Dictionary) -> bool:
	return not source.is_empty() and int(item.get("tier", 1)) <= int(source.get("tier", 1))

static func _monster_details(monster: Variant) -> Dictionary:
	if monster == null:
		return {}
	var monster_name := ""
	var fallback_tier := 1
	if monster is Dictionary:
		monster_name = String(monster.get("name", ""))
		fallback_tier = int(monster.get("tier", 1))
	elif monster is Object:
		monster_name = String(monster.get("name"))
		fallback_tier = int(monster.get("tier"))
	if monster_name.is_empty():
		return {}
	# Use the real catalog family, never a supplied is_boss or spoofed family.
	var template: Dictionary = GameData.get_monster_by_name(monster_name)
	return {"name": monster_name, "tier": fallback_tier, "family": String(template.get("family", ""))}
