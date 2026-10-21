class_name HitOutcome
extends RefCounted

var damage := 0
var crit := false
var hit := false
var status_effects: Array[String] = []

func _init(damage_amount: int = 0, was_critical: bool = false, did_hit: bool = false, effects: Array[String] = []) -> void:
	damage = damage_amount
	crit = was_critical
	hit = did_hit
	status_effects = effects.duplicate()
