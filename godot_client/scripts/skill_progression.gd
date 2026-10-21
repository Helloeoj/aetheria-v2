class_name SkillProgression
extends RefCounted

const MIN_LEVEL := 1
const MAX_LEVEL := 100
const TARGET_HOURS_TO_MAX := 80.0
# Reference: tier upgrades, current melee rolls, active goblins and 70% combat
# uptime. See docs/ExperienceRates.md for the route and other-skill limits.
const MAX_EXPERIENCE := 19_450_000
const LEVEL_CURVE_RATE := 0.06920900746073569

const SKILL_IDS := ["health", "attack", "strength", "defense", "range", "magic", "fishing", "cooking"]
const COMBAT_SKILL_IDS := ["attack", "strength", "defense", "range", "magic"]
const MIN_COMBAT_LEVEL := 1
const MAX_COMBAT_LEVEL := 150
const SKILL_NAMES := {
	"health": "Health",
	"attack": "Attack",
	"strength": "Strength",
	"defense": "Defense",
	"range": "Range",
	"magic": "Magic",
	"fishing": "Fishing",
	"cooking": "Cooking"
}

# Approved baseline rewards. All runtime damage awards and UI rate labels use
# these values; skill level changes affect combat output, not XP per damage.
const XP_PER_DAMAGE := {
	"health": 1,
	"attack": 3,
	"strength": 3,
	"defense": 3,
	"range": 3,
	"magic": 3
}
const MAGIC_XP_PER_CAST_LEVEL := 10
const MAGIC_CAST_FAILURE_CHANCE_AT_UNLOCK := 0.20
const MAGIC_LEVELS_TO_MASTER_SPELL := 20

static func normalize_skill(skill: String) -> String:
	match skill.to_lower():
		"defence":
			return "defense"
		"ranged":
			return "range"
		_:
			return skill.to_lower()

static func combat_level_for_skills(skill_levels: Dictionary) -> int:
	var skill_levels_gained := 0
	for skill: String in COMBAT_SKILL_IDS:
		var level := clampi(int(skill_levels.get(skill, MIN_LEVEL)), MIN_LEVEL, MAX_LEVEL)
		skill_levels_gained += level - MIN_LEVEL
	var possible_skill_gains := COMBAT_SKILL_IDS.size() * (MAX_LEVEL - MIN_LEVEL)
	# Floor the combined contribution so only five maxed skills can reach 150.
	var combat_levels_gained := floori(
		float(skill_levels_gained) * float(MAX_COMBAT_LEVEL - MIN_COMBAT_LEVEL)
		/ float(possible_skill_gains)
	)
	return MIN_COMBAT_LEVEL + combat_levels_gained

static func experience_for_level(level: int) -> int:
	var bounded_level := clampi(level, MIN_LEVEL, MAX_LEVEL)
	if bounded_level == MIN_LEVEL:
		return 0
	var level_curve := exp(LEVEL_CURVE_RATE * float(bounded_level - MIN_LEVEL)) - 1.0
	var maximum_curve := exp(LEVEL_CURVE_RATE * float(MAX_LEVEL - MIN_LEVEL)) - 1.0
	return roundi(float(MAX_EXPERIENCE) * level_curve / maximum_curve)

static func level_for_experience(experience: int) -> int:
	var bounded_experience := clampi(experience, 0, MAX_EXPERIENCE)
	for level in range(MAX_LEVEL, MIN_LEVEL - 1, -1):
		if bounded_experience >= experience_for_level(level):
			return level
	return MIN_LEVEL

static func experience_to_next_level(experience: int) -> int:
	var bounded_experience := clampi(experience, 0, MAX_EXPERIENCE)
	var level := level_for_experience(bounded_experience)
	if level >= MAX_LEVEL:
		return 0
	return maxi(0, experience_for_level(level + 1) - bounded_experience)

static func magic_experience_for_cast(unlock_level: int) -> int:
	var bounded_unlock_level := clampi(unlock_level, MIN_LEVEL, MAX_LEVEL)
	return MAGIC_XP_PER_CAST_LEVEL * bounded_unlock_level

static func damage_experience(skill: String, actual_damage: int) -> int:
	var skill_id := normalize_skill(skill)
	return maxi(0, actual_damage) * int(XP_PER_DAMAGE.get(skill_id, 0))

static func experience_source_text(skill: String) -> String:
	var skill_id := normalize_skill(skill)
	var rate := int(XP_PER_DAMAGE.get(skill_id, 0))
	match skill_id:
		"cooking":
			return "XP for successfully cooking food; burnt food awards no XP"
		"fishing":
			return "XP for landing fish; rarer fish award more"
		"health":
			return "%d XP per damage dealt" % rate
		"attack", "strength":
			return "%d XP per melee damage dealt" % rate
		"defense":
			return "%d XP per damage received" % rate
		"range":
			return "%d XP per ranged damage dealt" % rate
		"magic":
			return "%d XP per magic damage + cast XP" % rate
	return ""

static func magic_cast_failure_chance(magic_level: int, unlock_level: int) -> float:
	# Locked spells are rejected separately by the spellbook's unlock check.
	var bounded_unlock_level := clampi(unlock_level, MIN_LEVEL, MAX_LEVEL)
	var levels_above_requirement := maxi(0, magic_level - bounded_unlock_level)
	var levels_until_mastery := maxi(0, MAGIC_LEVELS_TO_MASTER_SPELL - levels_above_requirement)
	return MAGIC_CAST_FAILURE_CHANCE_AT_UNLOCK * (
		float(levels_until_mastery) / float(MAGIC_LEVELS_TO_MASTER_SPELL)
	)
