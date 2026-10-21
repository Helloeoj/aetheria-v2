class_name LegacyProjectile
extends RefCounted

var start_x := 0.0
var start_y := 0.0
var current_x := 0.0
var current_y := 0.0
var dir_x := 0.0
var dir_y := 0.0
var speed_tiles_per_tick := 0.0
var max_range := 20.0
var target: Variant
var attacker_stats: Dictionary = {}
var damage_type := "ranged"
var combat := CombatEngine.new()

func _init(attacker: Variant = null, target_ref: Variant = null, stats: Dictionary = {}, engine: CombatEngine = null) -> void:
	start_x = float(attacker.x) if attacker != null else 0.0
	start_y = float(attacker.y) if attacker != null else 0.0
	current_x = start_x
	current_y = start_y
	var destination := Vector2(float(target_ref.x), float(target_ref.y)) if target_ref != null else Vector2(start_x, start_y)
	var direction := (destination - Vector2(start_x, start_y)).normalized()
	dir_x = direction.x
	dir_y = direction.y
	speed_tiles_per_tick = float(stats.get("projectile_speed", 0.0))
	max_range = float(stats.get("attack_range", 20.0))
	target = target_ref
	attacker_stats = stats.duplicate(true)
	damage_type = String(stats.get("style", stats.get("damage_type", "ranged")))
	if engine != null:
		combat = engine

func resolve_hit() -> int:
	if target == null:
		return 0
	var target_stats: Dictionary = target.get_combat_stats()
	var attacker := attacker_stats.duplicate(true)
	attacker["attack_style"] = String(attacker.get("style", damage_type))
	var outcome := combat.calculate_hit_outcome(attacker, target_stats)
	return outcome.damage
