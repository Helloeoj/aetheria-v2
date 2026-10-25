class_name CombatActor
extends RefCounted

const OrbRules := preload("res://scripts/orb_effects.gd")

var entity_id := ""
var name := ""
var x := 0.0
var y := 0.0
var spawn_x := 0.0
## Committed occupancy; continuous x/y remain authoritative travel coordinates.
var logical_cell := Vector2i.ZERO
var spawn_y := 0.0
var hp := 1
var max_hp := 1
var attack_style := "slash"
var damage_roll_level := 0
var magic_level := 1
var magic_accuracy := 0.5
var min_damage := 0
var max_damage := 1
var accuracy := 0.5
var melee_attack_roll := -1.0
var melee_max_damage := -1
var melee_defence_rolls: Dictionary = {}
var defence_level := 1
var crit_chance := 0.0
var crit_multiplier := 1.5
var resistances: Dictionary = {}
var damage_reductions: Dictionary = {}
var uses_armour_rating := false
var attack_speed := GameTickConfig.MONSTER_ATTACK_INTERVAL_TICKS # Player cadence is stored in seconds.
var attack_interval_seconds := GameTickConfig.TICK_DURATION_SECONDS
var attack_cooldown_seconds := 0.0
var attack_range := 2.0
var projectile_speed := 0.0
var requires_line_of_sight := true
var next_attack_tick := 0.0
var is_monster := false
var monster_attack_type := ""
var hybrid_melee_style := "slash"
var hybrid_secondary_style := "magic"
var hybrid_melee_attack_count := 0
var current_target_id := ""
var aggro_attacker_ids: Array[String] = []
var status_effects: Array[String] = []
var orb_element := ""
var active_orb_effects: Dictionary = {}
var is_alive := true
var death_reported := false

func configure(data: Dictionary) -> CombatActor:
	entity_id = String(data.get("entity_id", ""))
	name = String(data.get("name", ""))
	x = float(data.get("x", 0.0))
	y = float(data.get("y", 0.0))
	spawn_x = float(data.get("spawn_x", x))
	spawn_y = float(data.get("spawn_y", y))
	max_hp = maxi(1, int(data.get("max_hp", 1)))
	hp = clampi(int(data.get("hp", max_hp)), 0, max_hp)
	attack_style = String(data.get("attack_style", "slash"))
	damage_roll_level = maxi(0, int(data.get("damage_roll_level", 0)))
	magic_level = clampi(int(data.get("magic_level", 1)), 1, SkillProgression.MAX_LEVEL)
	magic_accuracy = clampf(float(data.get("magic_accuracy", 0.5)), 0.0, 1.0)
	min_damage = maxi(0, int(data.get("min_damage", 0)))
	max_damage = maxi(min_damage, int(data.get("max_damage", 1)))
	accuracy = float(data.get("accuracy", 0.5))
	melee_attack_roll = float(data.get("melee_attack_roll", -1.0))
	melee_max_damage = int(data.get("melee_max_damage", -1))
	melee_defence_rolls = data.get("melee_defence_rolls", {}).duplicate(true)
	defence_level = maxi(1, int(data.get("defence_level", 1)))
	crit_chance = float(data.get("crit_chance", 0.0))
	crit_multiplier = float(data.get("crit_multiplier", 1.5))
	resistances = data.get("resistances", {}).duplicate(true)
	damage_reductions = data.get("damage_reductions", {}).duplicate(true)
	uses_armour_rating = bool(data.get("uses_armour_rating", false))
	is_monster = bool(data.get("is_monster", false))
	attack_speed = GameTickConfig.MONSTER_ATTACK_INTERVAL_TICKS if is_monster else 1
	attack_interval_seconds = maxf(0.1, float(data.get(
		"attack_interval_seconds", GameTickConfig.TICK_DURATION_SECONDS
	)))
	attack_cooldown_seconds = maxf(0.0, float(data.get("attack_cooldown_seconds", 0.0)))
	attack_range = maxf(0.0, float(data.get("attack_range", 2.0)))
	projectile_speed = 0.0 if is_monster else maxf(0.0, float(data.get("projectile_speed", 0.0)))
	requires_line_of_sight = bool(data.get("requires_line_of_sight", true))
	next_attack_tick = float(data.get("next_attack_tick", 0.0))
	monster_attack_type = String(data.get("monster_attack_type", ""))
	hybrid_melee_style = String(data.get("hybrid_melee_style", "slash"))
	hybrid_secondary_style = String(data.get("hybrid_secondary_style", "magic"))
	hybrid_melee_attack_count = maxi(0, int(data.get("hybrid_melee_attack_count", 0)))
	current_target_id = String(data.get("current_target_id", ""))
	aggro_attacker_ids.clear()
	var configured_aggro_attackers: Variant = data.get("aggro_attacker_ids", [])
	if configured_aggro_attackers is Array:
		for attacker_id: Variant in configured_aggro_attackers:
			aggro_attacker_ids.append(String(attacker_id))
	var configured_statuses: Variant = data.get("status_effects", [])
	status_effects.clear()
	if configured_statuses is Array:
		for effect: Variant in configured_statuses:
			status_effects.append(String(effect))
	orb_element = String(data.get("orb_element", "")).to_lower()
	active_orb_effects = data.get("active_orb_effects", {}).duplicate(true)
	is_alive = hp > 0 and bool(data.get("is_alive", true))
	if not is_alive:
		active_orb_effects.clear()
	death_reported = bool(data.get("death_reported", false))
	return self

func can_move() -> bool:
	return is_alive and not active_orb_effects.has("lightning")

func can_attack() -> bool:
	return is_alive and not active_orb_effects.has("lightning")

func effective_attack_interval_seconds() -> float:
	var base := float(attack_speed) * GameTickConfig.TICK_DURATION_SECONDS if is_monster else attack_interval_seconds
	return base / OrbRules.ATTACK_RATE_MULTIPLIER if active_orb_effects.has("ice") else base

func effective_defence_level() -> int:
	return maxi(1, floori(float(defence_level) * OrbRules.DEFENCE_MULTIPLIER)) if active_orb_effects.has("hurricane") else defence_level

func to_dictionary() -> Dictionary:
	return {
		"entity_id": entity_id, "name": name, "x": x, "y": y,
		"spawn_x": spawn_x, "spawn_y": spawn_y, "hp": hp,
		"max_hp": max_hp, "attack_style": attack_style,
		"damage_roll_level": damage_roll_level,
		"magic_level": magic_level,
		"magic_accuracy": magic_accuracy,
		"min_damage": min_damage, "max_damage": max_damage,
		"accuracy": accuracy, "crit_chance": crit_chance,
		"melee_attack_roll": melee_attack_roll,
		"melee_max_damage": melee_max_damage,
		"melee_defence_rolls": melee_defence_rolls,
		"defence_level": defence_level,
		"crit_multiplier": crit_multiplier, "resistances": resistances,
		"uses_armour_rating": uses_armour_rating,
		"damage_reductions": damage_reductions,
		"attack_speed": attack_speed,
		"attack_interval_seconds": attack_interval_seconds,
		"attack_cooldown_seconds": attack_cooldown_seconds,
		"attack_range": attack_range,
		"projectile_speed": projectile_speed,
		"requires_line_of_sight": requires_line_of_sight,
		"next_attack_tick": next_attack_tick,
		"is_monster": is_monster, "monster_attack_type": monster_attack_type,
		"hybrid_melee_style": hybrid_melee_style,
		"hybrid_secondary_style": hybrid_secondary_style,
		"hybrid_melee_attack_count": hybrid_melee_attack_count,
		"current_target_id": current_target_id,
		"aggro_attacker_ids": aggro_attacker_ids.duplicate(),
		"status_effects": status_effects.duplicate(), "is_alive": is_alive,
		"orb_element": orb_element, "active_orb_effects": active_orb_effects.duplicate(true),
		"death_reported": death_reported
	}
