class_name CombatProjectile
extends RefCounted

var projectile_id := ""
var spell_id := ""
var attacker_id := ""
var target_id := ""
var x := 0.0
var y := 0.0
var dx := 0.0
var dy := 0.0
var speed := 0.0
var max_range := 20
var travelled := 0.0
var damage := 0
var max_damage := -1
var accuracy := 0.0
var damage_type := "ranged"
var requires_line_of_sight := true
var crit_chance := 0.0
var crit_multiplier := 1.0
var status_effects: Array[String] = []
var orb_element := "" # Captured only for staff autoattacks, never selected spells.

func configure(data: Dictionary) -> CombatProjectile:
	projectile_id = String(data.get("projectile_id", ""))
	spell_id = String(data.get("spell_id", ""))
	attacker_id = String(data.get("attacker_id", ""))
	target_id = String(data.get("target_id", ""))
	x = float(data.get("x", 0.0))
	y = float(data.get("y", 0.0))
	dx = float(data.get("dx", 0.0))
	dy = float(data.get("dy", 0.0))
	speed = float(data.get("speed", 0.0))
	max_range = int(data.get("max_range", 20))
	travelled = float(data.get("travelled", 0.0))
	damage = int(data.get("damage", 0))
	max_damage = int(data.get("max_damage", -1))
	accuracy = float(data.get("accuracy", 0.0))
	damage_type = String(data.get("damage_type", "ranged"))
	orb_element = String(data.get("orb_element", "")).to_lower()
	requires_line_of_sight = bool(data.get("requires_line_of_sight", true))
	crit_chance = clampf(float(data.get("crit_chance", 0.0)), 0.0, 1.0)
	crit_multiplier = maxf(1.0, float(data.get("crit_multiplier", 1.0)))
	status_effects.clear()
	var configured_statuses: Variant = data.get("status_effects", [])
	if configured_statuses is Array:
		for effect: Variant in configured_statuses:
			status_effects.append(String(effect))
	return self
