class_name LegacyPlayerModel
extends RefCounted

const VALID_MELEE_STYLES := ["stab", "slash", "blunt"]
const PROJECTILE_SPEEDS := {"bow": 3.0, "crossbow": 2.2, "wand": 2.5, "staff": 2.0, "spell": 2.4, "thrown": 2.8}

var name := "Player"
var levels := {"attack": 1, "strength": 1, "defence": 1, "magic": 1, "ranged": 1, "health_level": 10}
var max_hp := 100
var current_hp := 100
var equipped := {
	"head": {}, "chest": {}, "legs": {}, "cape": {}, "neck": {},
	"ring1": {}, "ring2": {}, "weapon": {}, "shield": {}, "quiver_item": {}
}
var backpack: Dictionary = {}
var current_attack_style := "slash"
var swing_timer := 0.0
var x := 5
var y := 5

func _init(player_name: String = "Player") -> void:
	name = player_name
	max_hp = int(levels.health_level) * 10
	current_hp = max_hp

func get_position() -> Vector2i:
	return Vector2i(x, y)

func move(dx: int, dy: int) -> void:
	x += dx
	y += dy

func add_to_backpack(item_name: String, quantity: int = 1) -> void:
	backpack[item_name] = int(backpack.get(item_name, 0)) + quantity

func remove_from_backpack(item_name: String, quantity: int = 1) -> void:
	if not backpack.has(item_name):
		return
	backpack[item_name] = int(backpack[item_name]) - quantity
	if int(backpack[item_name]) <= 0:
		backpack.erase(item_name)

func equip_item(item: Dictionary) -> bool:
	var slot_value: Variant = item.get("slot", null)
	var slot := EquipmentUtils.get_item_slot(item) if slot_value == null else String(slot_value)
	if slot.is_empty():
		return false
	if slot == "ammo":
		slot = "quiver_item"
	if slot == "ring":
		if equipped.ring1.is_empty():
			equipped.ring1 = item
		elif equipped.ring2.is_empty():
			equipped.ring2 = item
		else:
			var previous: Dictionary = equipped.ring1
			add_to_backpack(String(previous.get("name", "")), 1)
			equipped.ring1 = item
		remove_from_backpack(String(item.get("name", "")), 1)
		return true
	if not equipped.has(slot):
		return false
	var previous: Dictionary = equipped[slot]
	if not previous.is_empty():
		add_to_backpack(String(previous.get("name", "")), 1)
	equipped[slot] = item
	remove_from_backpack(String(item.get("name", "")), 1)
	return true

func get_equipped_weapon() -> Dictionary:
	return equipped.weapon

func get_valid_styles_for_weapon() -> Array[String]:
	return PlayerStats.valid_styles_for_weapon(get_equipped_weapon())

func set_attack_style(style: String) -> bool:
	if style in get_valid_styles_for_weapon():
		current_attack_style = style
		return true
	return false

func weapon_speed_in_ticks() -> int:
	return PlayerStats.weapon_speed_in_ticks(get_equipped_weapon())

func get_attack_range() -> float:
	return PlayerStats.get_attack_range(current_attack_style, get_equipped_weapon())

func get_projectile_speed() -> float:
	var weapon := get_equipped_weapon()
	if weapon.is_empty():
		return 2.0
	var name_lower := String(weapon.get("name", "")).to_lower()
	for key: String in PROJECTILE_SPEEDS:
		if name_lower.contains(key):
			return float(PROJECTILE_SPEEDS[key])
	return 2.0

func calculate_attack_bonuses() -> Dictionary:
	var bonuses := {
		"stab_acc": 0, "slash_acc": 0, "blunt_acc": 0, "magic_acc": 0, "ranged_acc": 0,
		"stab_dmg": [1, 3], "slash_dmg": [1, 3], "blunt_dmg": [1, 3],
		"magic_dmg": [1, 3], "ranged_dmg": [1, 3]
	}
	for item: Dictionary in equipped.values():
		if item.is_empty():
			continue
		var attack: Dictionary = item.get("attack_bonuses", {})
		for style: String in ["stab", "slash", "blunt", "magic", "ranged"]:
			bonuses[style + "_acc"] = int(bonuses[style + "_acc"]) + int(attack.get(style, 0))
			var damage_range: Array = bonuses[style + "_dmg"]
			damage_range[0] += int(item.get(style + "_min_damage", 0))
			damage_range[1] += int(item.get(style + "_max_damage", 0))
			bonuses[style + "_dmg"] = damage_range
	for key: String in ["stab_acc", "slash_acc", "blunt_acc", "magic_acc", "ranged_acc"]:
		bonuses[key] = mini(100, int(bonuses[key]))
	return bonuses

func reset_hp() -> void:
	current_hp = max_hp

func full_reset() -> void:
	reset_hp()
	swing_timer = 0.0

func summary() -> Dictionary:
	var equipped_names := {}
	for slot: String in equipped:
		var item: Dictionary = equipped[slot]
		equipped_names[slot] = item.get("name") if not item.is_empty() else null
	return {
		"name": name, "position": get_position(), "hp": "%d/%d" % [current_hp, max_hp],
		"attack_style": current_attack_style, "equipped": equipped_names,
		"backpack": backpack.duplicate(true)
	}
