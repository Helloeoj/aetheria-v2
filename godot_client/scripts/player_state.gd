class_name PlayerState
extends RefCounted

const MAX_HIT_DAMAGE_DIVISOR := 256.0
const MAX_SKILL_DEFENCE_BONUS := 0.25
const FISHING_PALE_SIZE := 9

var name := "Player"
var levels: Dictionary = {
	"health": 10, "attack": 1, "strength": 1,
	"defense": 1, "range": 1, "magic": 1, "fishing": 1, "cooking": 1, "mining": 1
}
var skill_experience: Dictionary = {
	"health": 0, "attack": 0, "strength": 0,
	"defense": 0, "range": 0, "magic": 0, "fishing": 0, "cooking": 0, "mining": 0
}
var current_hp := 200
var food_cooldown_seconds := 0.0
var food_attack_cooldown_seconds := 0.0
var food_attack_interval_seconds := 0.0
var quick_food_name := ""
var active_cooking_session: WeakRef = null
var magic_experience := 0
var magic_level := 1
var current_mana := 10
var selected_spell_id := ""
var gold := 0
var backpack: Dictionary = {} # item name -> quantity
var fishing_pale: Array[String] = [] # Fixed positions; an empty string is an empty slot.
var equipment: Dictionary = {
	"head": {}, "chest": {}, "legs": {}, "cape": {}, "neck": {},
	"ring1": {}, "ring2": {}, "weapon": {}, "shield": {}
}
var quiver_item: Dictionary = {}
var quiver_amount := 0
var attack_style := "slash"
var entity_id := "player"
var current_target := ""
var in_combat := false
var x := 10.0
var y := 10.0

func _init(player_name: String = "Player") -> void:
	name = player_name
	for skill: String in SkillProgression.SKILL_IDS:
		levels[skill] = int(levels.get(skill, SkillProgression.MIN_LEVEL))
		skill_experience[skill] = SkillProgression.experience_for_level(int(levels[skill]))
	fishing_pale.resize(FISHING_PALE_SIZE)
	fishing_pale.fill("")
	magic_experience = int(skill_experience.get("magic", 0))
	magic_level = int(levels.get("magic", SkillProgression.MIN_LEVEL))
	current_hp = get_max_hp()

func get_max_hp() -> int:
	return PlayerStats.max_health(get_skill_level("health"))

func get_combat_level() -> int:
	return SkillProgression.combat_level_for_skills(levels)

func get_skill_level(skill: String) -> int:
	var skill_id := SkillProgression.normalize_skill(skill)
	return int(levels.get(skill_id, SkillProgression.MIN_LEVEL))

func get_skill_experience(skill: String) -> int:
	var skill_id := SkillProgression.normalize_skill(skill)
	return int(skill_experience.get(skill_id, 0))

func get_skill_progress(skill: String) -> Dictionary:
	var skill_id := SkillProgression.normalize_skill(skill)
	if skill_id not in SkillProgression.SKILL_IDS:
		return {}
	var experience := get_skill_experience(skill_id)
	var level := get_skill_level(skill_id)
	return {
		"id": skill_id,
		"name": String(SkillProgression.SKILL_NAMES[skill_id]),
		"level": level,
		"experience": experience,
		"experience_for_current_level": SkillProgression.experience_for_level(level),
		"experience_for_next_level": SkillProgression.experience_for_level(level + 1),
		"experience_to_next_level": SkillProgression.experience_to_next_level(experience),
		"max_experience": SkillProgression.MAX_EXPERIENCE
	}

func get_skills_progress() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for skill: String in SkillProgression.SKILL_IDS:
		result.append(get_skill_progress(skill))
	return result

func get_magic_level() -> int:
	return magic_level

func get_max_mana() -> int:
	return get_magic_level() * 10

func set_magic_level(value: int) -> void:
	set_skill_level("magic", value)
	current_mana = get_max_mana()

func add_magic_experience(amount: int) -> int:
	return add_skill_experience("magic", amount)

func get_known_spells() -> Array[Dictionary]:
	return GameData.get_unlocked_spells(get_magic_level())

func select_spell(spell_id: String) -> bool:
	if not GameData.is_spell_unlocked(spell_id, get_magic_level()):
		return false
	selected_spell_id = spell_id
	return true

func cycle_known_spell(direction: int = 1) -> Dictionary:
	var known_spells := get_known_spells()
	if known_spells.is_empty():
		selected_spell_id = ""
		return {}
	var selected_index := -1
	for index in range(known_spells.size()):
		if String(known_spells[index].get("id", "")) == selected_spell_id:
			selected_index = index
			break
	if selected_index < 0:
		selected_index = 0 if direction >= 0 else known_spells.size() - 1
	else:
		selected_index = posmod(selected_index + (1 if direction >= 0 else -1), known_spells.size())
	selected_spell_id = String(known_spells[selected_index].get("id", ""))
	return known_spells[selected_index]

func get_position() -> Vector2:
	return Vector2(x, y)

func set_level(skill: String, value: int) -> void:
	set_skill_level(skill, value)

func set_skill_level(skill: String, value: int) -> void:
	var skill_id := SkillProgression.normalize_skill(skill)
	if skill_id not in SkillProgression.SKILL_IDS:
		return
	var old_max_hp := get_max_hp()
	var old_max_mana := get_max_mana()
	var bounded_level := clampi(value, SkillProgression.MIN_LEVEL, SkillProgression.MAX_LEVEL)
	levels[skill_id] = bounded_level
	skill_experience[skill_id] = SkillProgression.experience_for_level(bounded_level)
	if skill_id == "health":
		var hp_capacity_change := get_max_hp() - old_max_hp
		current_hp = clampi(current_hp + hp_capacity_change, 0, get_max_hp())
	elif skill_id == "magic":
		magic_level = bounded_level
		magic_experience = int(skill_experience[skill_id])
		var mana_capacity_change := get_max_mana() - old_max_mana
		current_mana = clampi(current_mana + mana_capacity_change, 0, get_max_mana())

func add_skill_experience(skill: String, amount: int) -> int:
	var skill_id := SkillProgression.normalize_skill(skill)
	if skill_id not in SkillProgression.SKILL_IDS or amount <= 0:
		return get_skill_level(skill_id)
	var old_max_hp := get_max_hp()
	var old_max_mana := get_max_mana()
	var new_experience := mini(
		SkillProgression.MAX_EXPERIENCE,
		get_skill_experience(skill_id) + amount
	)
	skill_experience[skill_id] = new_experience
	levels[skill_id] = SkillProgression.level_for_experience(new_experience)
	if skill_id == "health":
		var hp_capacity_change := get_max_hp() - old_max_hp
		current_hp = clampi(current_hp + hp_capacity_change, 0, get_max_hp())
	elif skill_id == "magic":
		magic_experience = new_experience
		magic_level = int(levels[skill_id])
		var mana_capacity_change := get_max_mana() - old_max_mana
		current_mana = clampi(current_mana + mana_capacity_change, 0, get_max_mana())
	return get_skill_level(skill_id)

func add_item(item_name: String, quantity: int = 1) -> void:
	if GameData.get_item_by_name(item_name).is_empty() or quantity <= 0:
		return
	InventorySystem.add_to_backpack(self, item_name, quantity)

func remove_item(item_name: String, quantity: int = 1) -> bool:
	return InventorySystem.remove_from_backpack(self, item_name, quantity)

func get_quick_food() -> String:
	# Keep an explicitly selected species when depleted; never silently substitute
	# a more expensive meal. Only choose a default before any selection exists.
	if not quick_food_name.is_empty():
		return quick_food_name
	var lowest_heal := 2147483647
	var names := backpack.keys()
	names.sort()
	for item_name: String in names:
		var healing := int(GameData.get_item_by_name(item_name).get("food_healing", 0))
		if int(backpack[item_name]) > 0 and healing > 0 and healing < lowest_heal:
			quick_food_name = item_name
			lowest_heal = healing
	return quick_food_name

func fishing_pale_count() -> int:
	var count := 0
	for fish_name: String in fishing_pale:
		if not fish_name.is_empty():
			count += 1
	return count

func store_fishing_catch(fish_name: String) -> bool:
	var item := GameData.get_item_by_name(fish_name)
	if int(item.get("fishing_xp", 0)) <= 0 or String(item.get("fish_state", "")) != "raw":
		return false
	var slot := fishing_pale.find("")
	if slot < 0:
		return false
	fishing_pale[slot] = fish_name
	return true

func remove_fishing_catch(slot: int, expected_name: String = "") -> bool:
	if slot < 0 or slot >= fishing_pale.size() or fishing_pale[slot].is_empty():
		return false
	if not expected_name.is_empty() and fishing_pale[slot] != expected_name:
		return false
	fishing_pale[slot] = ""
	return true

func move_fishing_catch_to_inventory(slot: int) -> bool:
	if slot < 0 or slot >= fishing_pale.size():
		return false
	var fish_name := fishing_pale[slot]
	if fish_name.is_empty() or GameData.get_item_by_name(fish_name).is_empty():
		return false
	add_item(fish_name)
	fishing_pale[slot] = ""
	return true

func empty_fishing_pale_to_inventory() -> int:
	var moved := 0
	for slot in range(fishing_pale.size()):
		if move_fishing_catch_to_inventory(slot):
			moved += 1
	return moved

func _iter_equipped_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot: String in ["head", "chest", "legs", "cape", "neck", "ring1", "ring2", "weapon", "shield"]:
		var item: Dictionary = equipment.get(slot, {})
		if not item.is_empty():
			result.append(item)
	return result

func _get_weapon() -> Dictionary:
	return equipment.get("weapon", {})

func _get_weapon_speed_rating() -> int:
	return PlayerStats.weapon_speed_rating(_get_weapon())

func _get_current_style() -> String:
	var desired := attack_style if not attack_style.is_empty() else "slash"
	if desired == "crush":
		desired = "blunt"
	if desired not in PlayerStats.ALL_STYLES:
		desired = "slash"
	var weapon := _get_weapon()
	if weapon.is_empty():
		return "blunt"
	var valid_styles := PlayerStats.valid_styles_for_weapon(weapon)
	if desired in valid_styles:
		return desired
	var bonuses: Dictionary = weapon.get("attack_bonuses", {})
	var best_style := String(valid_styles[0]) if not valid_styles.is_empty() else desired
	var best_value := int(bonuses.get(best_style, -999))
	for style: String in bonuses:
		if style in valid_styles and int(bonuses[style]) > best_value:
			best_style = style
			best_value = int(bonuses[style])
	return best_style

func get_valid_styles_for_weapon() -> Dictionary:
	var weapon := _get_weapon()
	return {
		"weapon": weapon.get("name") if not weapon.is_empty() else null,
		"styles": PlayerStats.valid_styles_for_weapon(weapon)
	}

func set_attack_style(style: String) -> bool:
	if style == "crush":
		style = "blunt"
	if style not in PlayerStats.valid_styles_for_weapon(_get_weapon()):
		return false
	attack_style = style
	return true

func get_attack_range() -> float:
	return PlayerStats.get_attack_range(_get_current_style(), _get_weapon())

func get_projectile_speed() -> float:
	return PlayerStats.get_projectile_speed(_get_weapon(), _get_current_style())

func get_equipped_names() -> Dictionary:
	var result := {}
	for slot: String in equipment:
		var item: Dictionary = equipment[slot]
		result[slot] = item.get("name") if not item.is_empty() else null
	result["quiver_item"] = quiver_item.get("name") if not quiver_item.is_empty() else null
	result["quiver_amount"] = quiver_amount
	return result

func give_and_equip(item_ref: Variant, _slot: Variant = null) -> String:
	var item: Dictionary = {}
	if item_ref is Dictionary:
		item = item_ref
	elif item_ref is String:
		item = GameData.get_item_by_name(item_ref)
	else:
		item = GameData.get_item(int(item_ref))
	if item.is_empty():
		return "Item '%s' does not exist." % str(item_ref)
	var item_name := String(item.get("name", ""))
	add_item(item_name, 1)
	return InventorySystem.equip_item(self, item_name)

func equip_item(item_name: String) -> String:
	return InventorySystem.equip_item(self, item_name)

func unequip_slot(slot_name: String) -> String:
	return InventorySystem.unequip_slot(self, slot_name)

func get_combat_stats() -> Dictionary:
	var equipped_items := _iter_equipped_items()
	var attack_bonuses := PlayerStats.aggregate_attack_bonuses(equipped_items)
	var defence_bonuses := _get_combat_defence_bonuses(equipped_items)
	var style := _get_current_style()
	var skill_level := 1
	var power_level := 1
	match style:
		"stab", "slash", "blunt":
			skill_level = get_skill_level("attack")
			power_level = get_skill_level("strength")
		"ranged":
			skill_level = get_skill_level("range")
			power_level = skill_level
		"magic":
			skill_level = get_magic_level()
			power_level = skill_level
	var attack_roll := (skill_level + 8) * (int(attack_bonuses.get(style, 0)) + 64)
	var accuracy := 0.05 if attack_roll <= 0 else float(attack_roll) / float(attack_roll + 2000)
	accuracy = clampf(accuracy + PlayerStats.total_accuracy_bonus(equipped_items), 0.05, 0.99)
	var magic_attack_roll := (get_magic_level() + 8) * (int(attack_bonuses.get("magic", 0)) + 64)
	var magic_accuracy := 0.05 if magic_attack_roll <= 0 else float(magic_attack_roll) / float(magic_attack_roll + 2000)
	magic_accuracy = clampf(
		magic_accuracy + PlayerStats.total_accuracy_bonus(equipped_items), 0.05, 0.99
	)
	var magic_profile := PlayerStats.base_attack_profile(_get_weapon(), "magic")
	if not magic_profile.is_empty():
		var magic_weapon_bonuses: Dictionary = _get_weapon().get("attack_bonuses", {})
		var magic_rating := int(magic_weapon_bonuses.get("magic", 0)) + 64
		var magic_weapon_roll := float((get_magic_level() + 8) * magic_rating)
		var magic_trained_roll := float((SkillProgression.MAX_LEVEL + 8) * magic_rating)
		var magic_progress := float(get_magic_level() - 1) / float(SkillProgression.MAX_LEVEL - 1)
		var magic_weapon_accuracy := magic_weapon_roll / (magic_weapon_roll + 2000.0)
		var magic_trained_accuracy := magic_trained_roll / (magic_trained_roll + 2000.0)
		magic_accuracy = clampf(lerpf(float(magic_profile.accuracy), magic_trained_accuracy, magic_progress) + magic_accuracy - magic_weapon_accuracy, 0.05, 0.99)
	# Compress high-level damage so level 100 does not produce triple-digit unarmed hits.
	var max_hit := maxi(1, int(
		float((power_level + 8) * (int(attack_bonuses.get(style, 0)) + 64))
		/ MAX_HIT_DAMAGE_DIVISOR
	))
	var min_hit := 1
	var weapon := _get_weapon()
	if not weapon.is_empty():
		# The weapon's selected-style bonus supplies its base minimum; the style's
		# power skill scales it (Strength, Ranged, or Magic).
		var weapon_attack_bonuses: Dictionary = weapon.get("attack_bonuses", {})
		var weapon_base_min_hit := maxi(1, int(float(weapon_attack_bonuses.get(style, 0)) / 8.0))
		var power_scale := float(power_level + 8) / float(SkillProgression.MAX_LEVEL + 8)
		min_hit = maxi(1, int(float(weapon_base_min_hit) * power_scale))
	min_hit = mini(min_hit, max_hit)
	var base_profile := PlayerStats.base_attack_profile(weapon, style)
	if not base_profile.is_empty():
		var progress := float(power_level - 1) / float(SkillProgression.MAX_LEVEL - 1)
		var rating := int(attack_bonuses.get(style, 0))
		var weapon_bonuses: Dictionary = weapon.get("attack_bonuses", {})
		var weapon_rating := int(weapon_bonuses.get(style, 0))
		var equipment_damage := float((power_level + 8) * (rating - weapon_rating)) / MAX_HIT_DAMAGE_DIVISOR
		var trained_max := float((SkillProgression.MAX_LEVEL + 8) * (weapon_rating + 64)) / MAX_HIT_DAMAGE_DIVISOR
		max_hit = maxi(1, floori(lerpf(float(base_profile.max_damage), trained_max, progress) + equipment_damage))
		min_hit = mini(max_hit, maxi(int(base_profile.min_damage), min_hit))
		var weapon_roll := float((skill_level + 8) * (weapon_rating + 64))
		var trained_roll := float((SkillProgression.MAX_LEVEL + 8) * (weapon_rating + 64))
		var weapon_accuracy := weapon_roll / (weapon_roll + 2000.0)
		var trained_accuracy := trained_roll / (trained_roll + 2000.0)
		var accuracy_progress := float(skill_level - 1) / float(SkillProgression.MAX_LEVEL - 1)
		accuracy = clampf(lerpf(float(base_profile.accuracy), trained_accuracy, accuracy_progress) + accuracy - weapon_accuracy, 0.05, 0.99)
	var melee_roll := -1.0
	var melee_strength := PlayerStats.aggregate_melee_strength(equipped_items)
	var melee_defence_rolls := {}
	var armour_ratings := PlayerStats.aggregate_defence_bonuses(equipped_items)
	for melee_style: String in PlayerStats.MELEE_STYLES:
		melee_defence_rolls[melee_style] = PlayerStats.melee_defence_roll(
			get_skill_level("defense"), PlayerStats.armour_resistance_from_rating(float(armour_ratings[melee_style]))
		)
	var uses_melee_bonuses := style in PlayerStats.MELEE_STYLES and PlayerStats.uses_melee_bonuses(weapon)
	if uses_melee_bonuses:
		max_hit = PlayerStats.melee_max_hit(power_level, melee_strength)
		min_hit = 1
		melee_roll = PlayerStats.melee_attack_roll(skill_level, int(attack_bonuses[style]), PlayerStats.total_accuracy_bonus(equipped_items))
		accuracy = PlayerStats.melee_hit_chance(melee_roll, PlayerStats.melee_defence_roll(1, 0.0))
	var stats := {
		"name": name,
		"combat_level": get_combat_level(),
		"style": style,
		"damage_roll_level": 0 if uses_melee_bonuses else skill_level,
		"melee_strength_bonus": melee_strength,
		"melee_attack_roll": melee_roll,
		"melee_defence_rolls": melee_defence_rolls,
		"defence_level": get_skill_level("defense"),
		"min_damage": min_hit,
		"max_damage": max_hit,
		"accuracy": snappedf(accuracy, 0.001),
		"magic_level": get_magic_level(),
		"magic_accuracy": snappedf(magic_accuracy, 0.001),
		"crit_chance": 0.05,
		"crit_multiplier": 1.5,
		"attack_speed": _get_weapon_speed_rating(),
		"weapon_speed_rating": _get_weapon_speed_rating(),
		"attack_interval_seconds": PlayerStats.weapon_attack_interval_seconds(_get_weapon()),
		"attack_range": get_attack_range(),
		"projectile_speed": get_projectile_speed(),
		"orb_element": String(weapon.get("orb_element", "")) if style == "magic" else "",
		"resistances": defence_bonuses,
		"uses_armour_rating": true,
		"health": {"current": current_hp, "max": get_max_hp()}
	}
	return stats

func _get_combat_defence_bonuses(items: Array[Dictionary]) -> Dictionary:
	var bonuses := PlayerStats.aggregate_defence_bonuses(items)
	var physical_bonus := _skill_defence_bonus(get_skill_level("defense"))
	var magic_bonus := _skill_defence_bonus(get_magic_level())
	for style: String in ["stab", "slash", "blunt", "ranged"]:
		bonuses[style] = PlayerStats.armour_resistance_from_rating(float(bonuses.get(style, 0.0)) + physical_bonus)
	bonuses["magic"] = PlayerStats.armour_resistance_from_rating(float(bonuses.get("magic", 0.0)) + magic_bonus)
	return bonuses

func _skill_defence_bonus(level: int) -> float:
	var max_level := maxi(2, SkillProgression.MAX_LEVEL)
	var progress := clampf(float(level - 1) / float(max_level - 1), 0.0, 1.0)
	return progress * MAX_SKILL_DEFENCE_BONUS

func summary() -> Dictionary:
	return {
		"name": name,
		"combat_level": get_combat_level(),
		"hp": "%d/%d" % [current_hp, get_max_hp()],
		"mana": "%d/%d" % [current_mana, get_max_mana()],
		"magic_level": magic_level,
		"magic_experience": magic_experience,
		"levels": levels.duplicate(true),
		"skill_experience": skill_experience.duplicate(true),
		"skills": get_skills_progress(),
		"equipped": get_equipped_names(),
		"backpack": backpack.duplicate(true)
	}
