class_name SkillTrainingSession
extends RefCounted
## Measures earned XP during play. Practice level setters never feed this meter.

const RATE_WARMUP_SECONDS := 60.0

var _experience_gained: Dictionary = {}
var _elapsed_seconds := 0.0
var _started := false

func advance(delta: float) -> void:
	if _started:
		_elapsed_seconds += maxf(0.0, delta)

func record_event(event: Dictionary) -> void:
	if String(event.get("type", "")) != "skill_experience_gained":
		return
	var skill := SkillProgression.normalize_skill(String(event.get("skill", "")))
	var amount := maxi(0, int(event.get("experience_gained", 0)))
	if skill not in SkillProgression.SKILL_IDS or amount == 0:
		return
	_started = true
	_experience_gained[skill] = int(_experience_gained.get(skill, 0)) + amount

func get_elapsed_seconds() -> float:
	return _elapsed_seconds

func get_progress(skill: String) -> Dictionary:
	var skill_id := SkillProgression.normalize_skill(skill)
	var gained := int(_experience_gained.get(skill_id, 0))
	var ready := _started and _elapsed_seconds >= RATE_WARMUP_SECONDS
	return {
		"experience_gained": gained,
		"elapsed_seconds": _elapsed_seconds,
		"experience_per_hour": roundi(float(gained) * 3600.0 / _elapsed_seconds) if ready else 0,
		"rate_ready": ready
	}

func reset() -> void:
	_experience_gained.clear()
	_elapsed_seconds = 0.0
	_started = false
