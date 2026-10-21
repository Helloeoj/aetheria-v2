class_name MagicProgression
extends RefCounted

const MIN_LEVEL := SkillProgression.MIN_LEVEL
const MAX_LEVEL := SkillProgression.MAX_LEVEL
const MAX_EXPERIENCE := SkillProgression.MAX_EXPERIENCE

static func experience_for_level(level: int) -> int:
	return SkillProgression.experience_for_level(level)

static func level_for_experience(experience: int) -> int:
	return SkillProgression.level_for_experience(experience)

static func experience_to_next_level(experience: int) -> int:
	return SkillProgression.experience_to_next_level(experience)
