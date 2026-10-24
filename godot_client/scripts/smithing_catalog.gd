class_name SmithingCatalog
extends RefCounted
## Finished metal equipment and usable smelting materials. No pending components.
const METALS := ["Bronze", "Iron", "Steel", "Blacksteel", "Mithril", "Adamantite", "Starforged"]
const WEAPONS := ["Dagger", "Shortsword", "Longsword", "Mace", "Warmaul"]
const ARMOR := {"Helmet": "helmet", "Platebody": "body", "Platelegs": "legs", "Kiteshield": "shield", "Square Shield": "shield"}
const ORDER := ["ore", "ingot", "weapon", "helmet", "body", "legs", "shield"]

static func category(item: Dictionary) -> String:
	if bool(item.get("legacy_placeholder", false)):
		return ""
	var name_key := str(item.get("name", ""))
	if name_key == "Coal" and item.get("type") == "Crafting":
		return "ore"
	var material := str(item.get("material", ""))
	if material not in METALS or int(item.get("tier", 0)) != METALS.find(material) + 1:
		return ""
	if item.get("type") == "Crafting":
		if name_key == material + " Ingot": return "ingot"
		# Steel is an alloy made from Iron Ore and Coal, not a mined ore.
		if material != "Steel" and name_key == material + " Ore": return "ore"
	if item.get("type") == "Weapon" and item.get("slot") == "weapon":
		for kind: String in WEAPONS:
			if name_key == material + " " + kind: return "weapon"
	if item.get("type") == "Armor":
		for kind: String in ARMOR:
			if name_key == material + " " + kind: return ARMOR[kind]
	return ""

static func item_ids(db: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for key: Variant in db:
		if not category(db[key]).is_empty(): result.append(int(key))
	result.sort_custom(func(a: int, b: int) -> bool:
		var left: Dictionary = db[a]
		var right: Dictionary = db[b]
		if int(left.tier) != int(right.tier): return int(left.tier) < int(right.tier)
		var left_category := ORDER.find(category(left))
		var right_category := ORDER.find(category(right))
		if left_category != right_category: return left_category < right_category
		return a < b)
	return result
