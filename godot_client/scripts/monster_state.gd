class_name MonsterState
extends RefCounted

var monster_id := -1
var entity_id := ""
var name := ""
var tier := 1
var level := 1
var skills: Dictionary = {}
var max_hp := 1
var current_hp := 1
var min_damage := 0
var max_damage := 1
var damage_type := "slash"
var accuracy := 0.5
var resistances: Dictionary = {}
var damage_reductions: Dictionary = {}
var attack_speed := GameTickConfig.MONSTER_ATTACK_INTERVAL_TICKS
var attack_range := 1
var projectile_speed := 0.0
var crit_chance := 0.05
var crit_multiplier := 1.5
var x := 0.0
var y := 0.0
var is_alive := true
var in_combat := false
var target: Variant = null
var attack_style := "slash"
var hybrid_melee_style := "slash"
var hybrid_secondary_style := "magic"

func _init(template: Dictionary = {}, start_x: float = 0.0, start_y: float = 0.0) -> void:
	monster_id = int(template.get("id", -1))
	name = String(template.get("name", "Monster"))
	tier = int(template.get("tier", 1))
	level = int(template.get("level", 1))
	skills = template.get("skills", {}).duplicate(true)
	max_hp = PlayerStats.max_health(int(skills.health)) if skills.has("health") else int(template.get("max_hp", 1))
	current_hp = max_hp
	min_damage = int(template.get("min_damage", 0))
	max_damage = int(template.get("max_damage", 1))
	damage_type = String(template.get("damage_type", "slash"))
	if damage_type in PlayerStats.MELEE_STYLES and skills.has("strength"):
		min_damage = 1
		max_damage = PlayerStats.melee_max_hit(int(skills.strength), 0)
	attack_style = damage_type
	hybrid_melee_style = String(template.get("hybrid_melee_style", "slash"))
	hybrid_secondary_style = String(template.get("hybrid_secondary_style", "magic"))
	accuracy = float(template.get("accuracy", 0.5))
	if damage_type in PlayerStats.MELEE_STYLES and skills.has("attack"):
		accuracy = PlayerStats.melee_hit_chance(PlayerStats.melee_attack_roll(int(skills.attack), 0), PlayerStats.melee_defence_roll(1, 0.0))
	resistances = template.get("resistances", {}).duplicate(true)
	damage_reductions = template.get("damage_reductions", {}).duplicate(true)
	attack_speed = GameTickConfig.MONSTER_ATTACK_INTERVAL_TICKS
	attack_range = int(template.get("attack_range", 1))
	projectile_speed = 0.0
	var projectile_style := damage_type
	if damage_type == "hybrid":
		projectile_style = hybrid_secondary_style
	if projectile_style in ["ranged", "magic"]:
		var projectile_profile := PlayerStats.get_default_projectile_profile(projectile_style)
		projectile_speed = float(projectile_profile.get("speed", 0.0))
	crit_chance = float(template.get("crit_chance", 0.05))
	crit_multiplier = float(template.get("crit_multiplier", 1.5))
	x = start_x
	y = start_y

func get_position() -> Vector2:
	return Vector2(x, y)

func move_to(new_x: float, new_y: float) -> void:
	x = new_x
	y = new_y

func distance_to(other: Variant) -> float:
	return get_position().distance_to(Vector2(float(other.x), float(other.y)))

func get_combat_stats() -> Dictionary:
	return {
		"defence_level": int(skills.get("defense", level)),
		"melee_attack_roll": PlayerStats.melee_attack_roll(int(skills.attack), 0) if skills.has("attack") else -1.0,
		"melee_strength_bonus": 0,
		"melee_max_damage": PlayerStats.melee_max_hit(int(skills.strength), 0) if skills.has("strength") else -1,
		"health": {"current": current_hp, "max": max_hp},
		"min_damage": min_damage,
		"max_damage": max_damage,
		"style": damage_type,
		"accuracy": accuracy,
		"crit_chance": crit_chance,
		"crit_multiplier": crit_multiplier,
		"resistances": resistances,
		"damage_reductions": damage_reductions,
		"attack_speed": attack_speed,
		"attack_range": attack_range,
		"projectile_speed": projectile_speed,
		"hybrid_melee_style": hybrid_melee_style,
		"hybrid_secondary_style": hybrid_secondary_style,
		"status_effects": []
	}

func apply_damage(amount: int) -> void:
	if amount <= 0 or not is_alive:
		return
	current_hp = maxi(0, current_hp - amount)
	if current_hp == 0:
		is_alive = false

func summary() -> Dictionary:
	return {
		"name": name, "tier": tier, "level": level,
		"skills": skills.duplicate(true),
		"damage_reductions": damage_reductions.duplicate(true),
		"hp": "%d/%d" % [current_hp, max_hp],
		"damage": "%d-%d" % [min_damage, max_damage],
		"type": damage_type, "accuracy": accuracy, "resistances": resistances,
		"position": get_position(), "alive": is_alive,
		"crit": {"chance": crit_chance, "multiplier": crit_multiplier}
	}
