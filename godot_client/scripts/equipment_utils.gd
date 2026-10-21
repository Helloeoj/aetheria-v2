class_name EquipmentUtils
extends RefCounted

static func is_ammo(item: Dictionary) -> bool:
	var name := String(item.get("name", ""))
	if String(item.get("type", "")) not in ["Weapon", "Armor", "Enchantment/Misc", "Crafting"]:
		return false
	for suffix: String in [" Arrow", " Arrows", " Bolt", " Bolts"]:
		if name.ends_with(suffix):
			return true
	return false

static func is_two_handed(item: Dictionary) -> bool:
	if String(item.get("type", "")) != "Weapon":
		return false
	if item.has("two_handed"):
		return bool(item["two_handed"])
	var name := String(item.get("name", ""))
	return name.contains("Warmaul") or name.contains(" Bow") or name.contains("Magic Staff")

static func get_item_slot(item: Dictionary) -> String:
	var name := String(item.get("name", ""))
	var item_type := String(item.get("type", ""))
	if item_type == "Weapon":
		return "weapon"
	if item_type == "Armor":
		if name.contains("Helmet"):
			return "head"
		if name.contains("Platebody"):
			return "chest"
		if name.contains("Platelegs"):
			return "legs"
		if name.contains("Kiteshield") or name.contains("Square Shield"):
			return "shield"
		if name.contains("Ring"):
			return "ring"
		if name.contains("Necklace"):
			return "neck"
		if name.contains("Cape"):
			return "cape"
	if is_ammo(item):
		return "ammo"
	return ""
