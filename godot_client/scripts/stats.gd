class_name PlayerStats
extends RefCounted

const MELEE_STYLES := ["stab", "slash", "blunt"]
const ALL_STYLES := ["stab", "slash", "blunt", "magic", "ranged"]
const BASE_ATTACK_INTERVAL_SECONDS := 0.6
const WEAPON_SPEED_RATING_SECONDS := 0.15
const PLAYER_ATTACK_INTERVAL_MULTIPLIER := 3.0
const MIN_ARMOUR_RESISTANCE := -0.5
const MAX_ARMOUR_RESISTANCE := 0.8
const BASE_MELEE_STRENGTH := 16
const MELEE_MAX_HIT_DIVISOR := 64.0

## Projectile speeds are world tiles per second. Attack cadence is configured separately.
const PROJECTILE_PROFILES := {
	"bow": {"speed": 24.0, "range": 18.0},
	"crossbow": {"speed": 16.0, "range": 24.0},
	"handheld": {"speed": 32.0, "range": 5.0},
	"wand": {"speed": 24.0, "range": 20.0},
	"staff": {"speed": 18.0, "range": 20.0},
	"spell": {"speed": 20.0, "range": 20.0}
}

static func base_attack_profile(weapon: Dictionary, style: String) -> Dictionary:
	var profiles: Dictionary = weapon.get("combat_profiles", {})
	return profiles.get(style, {})

static func uses_melee_bonuses(weapon: Dictionary) -> bool:
	return weapon.is_empty() or valid_styles_for_weapon(weapon).any(func(style: String) -> bool: return style in MELEE_STYLES)

static func max_health(health_level: int) -> int:
	return maxi(1, health_level) * 20

static func aggregate_melee_strength(items: Array[Dictionary]) -> int:
	var total := 0
	for item: Dictionary in items:
		total += int(item.get("melee_strength_bonus", 0))
	return total

static func melee_max_hit(strength_level: int, strength_bonus: int) -> int:
	return maxi(1, floori(0.5 + float((strength_level + 8) * maxi(0, strength_bonus + BASE_MELEE_STRENGTH)) / MELEE_MAX_HIT_DIVISOR))

static func melee_attack_roll(attack_level: int, style_bonus: int, accuracy_bonus: float = 0.0) -> float:
	return float((attack_level + 8) * maxi(0, style_bonus + 64)) * maxf(0.0, 1.0 + accuracy_bonus)

static func melee_defence_roll(defence_level: int, resistance: float) -> float:
	return float((maxi(1, defence_level) + 8) * 64) / (1.0 - clampf(resistance, MIN_ARMOUR_RESISTANCE, MAX_ARMOUR_RESISTANCE))

static func melee_hit_chance(attack_roll: float, defence_roll: float) -> float:
	var chance := 0.0
	if attack_roll > defence_roll:
		chance = 1.0 - (defence_roll + 2.0) / (2.0 * (attack_roll + 1.0))
	else:
		chance = attack_roll / (2.0 * (defence_roll + 1.0))
	return clampf(chance, 0.05, 0.99)

static func valid_styles_for_weapon(weapon: Dictionary) -> Array[String]:
	if weapon.is_empty():
		return ["blunt"]
	var bonuses: Dictionary = weapon.get("attack_bonuses", {})
	var styles: Array[String] = []
	for style: String in ALL_STYLES:
		if int(bonuses.get(style, 0)) > 0:
			styles.append(style)
	return styles if not styles.is_empty() else ["blunt"]

static func weapon_speed_rating(weapon: Dictionary) -> int:
	if weapon.is_empty():
		return 4
	var value: Variant = weapon.get("speed", 4)
	return int(value) if value != null and int(value) != 0 else 4

static func weapon_speed_in_ticks(weapon: Dictionary) -> int:
	## Compatibility alias for the legacy client; item speed is a rating, not ticks.
	return weapon_speed_rating(weapon)

static func weapon_attack_interval_seconds(weapon: Dictionary) -> float:
	if weapon.is_empty():
		return BASE_ATTACK_INTERVAL_SECONDS * PLAYER_ATTACK_INTERVAL_MULTIPLIER
	var speed_rating := weapon_speed_rating(weapon)
	var interval := float(speed_rating) * WEAPON_SPEED_RATING_SECONDS
	var name := String(weapon.get("name", "")).to_lower()
	if name.contains("warmaul"):
		return 3.0
	if name.contains("dagger"):
		interval = minf(interval, 0.45)
	elif name.contains("shortsword"):
		interval = minf(interval, 0.54)
	var projectile_type := weapon_projectile_type(weapon, "")
	if projectile_type == "crossbow":
		interval = maxf(interval, 1.2)
	elif projectile_type == "handheld":
		interval = minf(interval, 0.45)
	return interval * PLAYER_ATTACK_INTERVAL_MULTIPLIER

static func get_attack_range(style: String, weapon: Dictionary) -> float:
	if style in MELEE_STYLES:
		return 2.0
	if style in ["magic", "ranged"]:
		return float(get_projectile_profile(weapon, style).get("range", 20.0))
	return 2.0

static func get_projectile_speed(weapon: Dictionary, style: String = "ranged") -> float:
	if style in MELEE_STYLES:
		return 0.0
	return float(get_projectile_profile(weapon, style).get("speed", 20.0))

static func get_projectile_profile(weapon: Dictionary, style: String) -> Dictionary:
	var projectile_type := weapon_projectile_type(weapon, style)
	return PROJECTILE_PROFILES.get(projectile_type, PROJECTILE_PROFILES["spell"]).duplicate(true)

static func get_default_projectile_profile(style: String) -> Dictionary:
	## Monsters share player projectile classes: ranged attacks use bow speed, magic uses spell speed.
	var projectile_type := "bow" if style == "ranged" else "spell"
	return PROJECTILE_PROFILES[projectile_type].duplicate(true)

static func weapon_projectile_type(weapon: Dictionary, style: String) -> String:
	var declared_type := String(weapon.get("projectile_type", ""))
	if PROJECTILE_PROFILES.has(declared_type):
		return declared_type
	var name := String(weapon.get("name", "")).to_lower()
	if name.contains("crossbow"):
		return "crossbow"
	if name.contains("bow"):
		return "bow"
	if name.contains("wand"):
		return "wand"
	if name.contains("staff"):
		return "staff"
	if style == "magic":
		return "spell"
	if style == "ranged":
		return "handheld"
	return ""

static func aggregate_attack_bonuses(items: Array[Dictionary]) -> Dictionary:
	var total := {"slash": 0, "stab": 0, "blunt": 0, "magic": 0, "ranged": 0}
	for item: Dictionary in items:
		var bonuses: Dictionary = item.get("attack_bonuses", {})
		for key: String in total:
			total[key] += int(bonuses.get(key, 0))
	return total

static func aggregate_defence_bonuses(items: Array[Dictionary]) -> Dictionary:
	## Sum raw ratings; equipment and skill bonuses are converted together once.
	var total := {"slash": 0.0, "stab": 0.0, "blunt": 0.0, "magic": 0.0, "ranged": 0.0}
	for item: Dictionary in items:
		var bonuses: Dictionary = item.get("defence_bonuses", {})
		for key: String in total:
			total[key] = float(total[key]) + float(bonuses.get(key, 0.0))
	return total

static func armour_resistance_from_rating(rating: float) -> float:
	## Diminishing returns preserve tier improvements and bound vulnerabilities.
	return clampf(rating / (1.0 + absf(rating)), MIN_ARMOUR_RESISTANCE, MAX_ARMOUR_RESISTANCE)

static func total_accuracy_bonus(items: Array[Dictionary]) -> float:
	var total := 0.0
	for item: Dictionary in items:
		var value: Variant = item.get("accuracy_bonus", 0.0)
		total += float(value) if value != null else 0.0
	return total
