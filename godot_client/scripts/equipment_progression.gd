class_name EquipmentProgression
extends RefCounted

const LEVELS_PER_TIER := 10
const ARMOR_SLOTS := ["head", "chest", "legs", "cape", "shield"]

static func required_level_for_tier(tier: int) -> int:
	# Bronze (tier 1) has no requirement. Do not cap future tiers to level 100:
	# a tier above the skill cap must stay unavailable rather than unlock early.
	return maxi(0, (tier - 1) * LEVELS_PER_TIER)

static func tier_for_level(level: int) -> int:
	return 1 + floori(float(maxi(0, level)) / float(LEVELS_PER_TIER))

static func requirements(item: Dictionary) -> Dictionary:
	if item.is_empty():
		return {}
	var slot_value: Variant = item.get("slot", "")
	var slot := "" if slot_value == null else String(slot_value)
	var item_type := String(item.get("type", ""))
	# Ammunition is loaded independently of worn weapons and armor.
	if slot in ["quiver", "ammo"] or EquipmentUtils.is_ammo(item):
		return {}
	var required_level := required_level_for_tier(int(item.get("tier", 1)))
	if slot == "weapon" or item_type == "Weapon":
		return {"attack": required_level}
	if item_type == "Armor" or slot in ARMOR_SLOTS:
		return {"defense": required_level}
	return {}

static func can_equip(player: Variant, item: Dictionary) -> bool:
	var needed := requirements(item)
	for skill: String in needed:
		if player == null or int(player.get_skill_level(skill)) < int(needed[skill]):
			return false
	return true

static func requirement_text(item: Dictionary) -> String:
	var parts: Array[String] = []
	var needed := requirements(item)
	for skill: String in needed:
		var required_level := int(needed[skill])
		if required_level > 0:
			parts.append("%s %d" % [skill.capitalize(), required_level])
	return "No skill requirement" if parts.is_empty() else "Requires " + ", ".join(parts)

static func unmet_requirement_text(player: Variant, item: Dictionary) -> String:
	var parts: Array[String] = []
	var needed := requirements(item)
	for skill: String in needed:
		var current_level := 0 if player == null else int(player.get_skill_level(skill))
		var required_level := int(needed[skill])
		if current_level < required_level:
			parts.append("%s %d (current %d)" % [skill.capitalize(), required_level, current_level])
	return "" if parts.is_empty() else "Requires " + ", ".join(parts)
