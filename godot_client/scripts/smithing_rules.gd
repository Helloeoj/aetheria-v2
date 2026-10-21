class_name SmithingRules
extends RefCounted
## Balance lives outside the recipe catalog. No new materials or costs here.
const SETTINGS_PATH := "res://data/smithing.json"
static var _settings: Dictionary = {}

static func settings() -> Dictionary:
	if _settings.is_empty():
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
		if value is Dictionary:
			_settings = value
	return _settings.duplicate(true)

static func required_level(tier: int) -> int:
	var levels: Array = settings().get("required_levels", [])
	return int(levels[tier - 1]) if tier >= 1 and tier <= levels.size() else 101

static func heat_profile(tier: int, level: int, options: Dictionary = {}) -> Dictionary:
	var config := settings()
	config.merge(options, true)
	var widths: Array = config.starting_widths
	if tier < 1 or tier > widths.size():
		return {}
	var proficiency := clampf(float(level - required_level(tier)) / float(config.mastery_levels), 0.0, 1.0)
	var width := lerpf(float(widths[tier - 1]), float(config.maximum_width), proficiency)
	var center := float(config.heat_center)
	return {"low": center - width * 0.5, "high": center + width * 0.5,
		"grace": lerpf(float(config.base_overheat_grace), float(config.maximum_overheat_grace), proficiency),
		"immune": level - required_level(tier) >= int(config.mastery_levels)}

static func smelt_seconds(batch: int, config: Dictionary = {}) -> float:
	var values := settings()
	values.merge(config, true)
	return float(values.base_smelt_seconds) + float(maxi(0, batch - 1)) * float(values.additional_bar_seconds)

static func xp_per_bar(tier: int) -> int:
	if tier < 1 or tier > 7:
		return 0
	var config := settings()
	var overrides: Dictionary = config.xp_per_bar_override
	if overrides.has(str(tier)):
		return maxi(0, int(overrides[str(tier)]))
	# Calibrate the existing curve using repeated ten-bar batches at 80% heat
	# uptime, excluding gathering. Higher tiers retain the 10/20/.../70 ratio.
	var reference_seconds := smelt_seconds(10) / (10.0 * float(config.reference_heat_uptime))
	var unscaled_seconds := 0.0
	for index in range(1, 8):
		var lower := SkillProgression.experience_for_level(required_level(index))
		var upper := SkillProgression.MAX_EXPERIENCE if index == 7 else SkillProgression.experience_for_level(required_level(index + 1))
		unscaled_seconds += float(upper - lower) / float(index * 10) * reference_seconds
	var scale := unscaled_seconds / (float(config.target_hours_to_max) * 3600.0)
	return maxi(1, roundi(float(tier * 10) * scale))

static func category(item_name: String) -> String:
	var lower := item_name.to_lower()
	if "axe" in lower and not "crossbow" in lower:
		return "axe"
	if "sword" in lower or "dagger" in lower:
		return "sword"
	if "helmet" in lower or "helm" in lower:
		return "helmet"
	if "platebody" in lower or "chestplate" in lower:
		return "chestplate"
	if "platelegs" in lower:
		return "legs"
	if "shield" in lower:
		return "shield"
	if "mace" in lower or "maul" in lower:
		return "blunt"
	return "component"

static func pattern_for(item_name: String, config: Dictionary = {}) -> Array:
	var values := settings()
	values.merge(config, true)
	return Array(values.patterns.get(category(item_name), values.patterns.component)).duplicate(true)
