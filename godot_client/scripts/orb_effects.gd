class_name OrbEffects
extends RefCounted
## Orb enchantments are independent from the older authored status labels.

const PROC_CHANCE := 0.10
const ATTACK_RATE_MULTIPLIER := 0.90
const DEFENCE_MULTIPLIER := 0.90
const BURN_DAMAGE_FRACTION := 0.10
const BURN_TICKS := 5
const DURATIONS := {"fire": 3.0, "ice": 10.0, "lightning": 1.8, "hurricane": 10.0}

static func create(element: String, source_id: String, damage: int) -> Dictionary:
	if not DURATIONS.has(element):
		return {}
	var result := {"remaining": float(DURATIONS[element]), "source_id": source_id}
	if element == "fire":
		result["tick_remaining"] = GameTickConfig.TICK_DURATION_SECONDS
		result["ticks_left"] = BURN_TICKS
		result["damage_per_tick"] = float(maxi(0, damage)) * BURN_DAMAGE_FRACTION
		result["fractional_damage"] = 0.0
	return result
