extends Node2D
## Presentation only. The combat engine owns cells, timestamps and damage.
## Position this root at the authoritative 32px tile center. Sample externally.
const NATIVE_SIZE := Vector2(48, 64)
const GROUND_ANCHOR := Vector2(24, 52)
const TICK_SECONDS := GameTickConfig.TICK_DURATION_SECONDS
const DEFAULT_WARNING_SECONDS := TICK_SECONDS * 2.0
const STEPS_PER_TICK := 30
const STRIKE_FRAME_SECONDS := TICK_SECONDS / STEPS_PER_TICK
const STRIKE_STEPS := STEPS_PER_TICK * 2 + 6
const INACTIVE_FRAME := 4 + STRIKE_STEPS
var current_sample: Dictionary = {"phase":"inactive", "frame":INACTIVE_FRAME, "height_px":0}

func _ready() -> void:
	visible = false

func sample_at_seconds(elapsed: float, warning_seconds: float = DEFAULT_WARNING_SECONDS) -> Dictionary:
	var frame := INACTIVE_FRAME
	var phase := "inactive"
	var height := 0
	if is_finite(elapsed) and is_finite(warning_seconds) and elapsed >= 0.0 and warning_seconds > 0.0:
		if elapsed < warning_seconds:
			frame = mini(3, int(elapsed / warning_seconds * 4.0))
			phase = "warning"
		elif elapsed < warning_seconds + STRIKE_STEPS * STRIKE_FRAME_SECONDS:
			# Tiny tolerance handles floating-point representation of exact tick edges.
			var step := mini(STRIKE_STEPS - 1, floori((elapsed-warning_seconds)/STRIKE_FRAME_SECONDS + 0.0000001))
			frame = 4 + step
			height = _height_for_step(step)
			phase = "eruption" if step < STEPS_PER_TICK else ("retraction" if step < STEPS_PER_TICK * 2 else "cleanup")
		else:
			phase = "complete"
	current_sample = {"phase":phase, "frame":frame, "height_px":height}
	var visual := get_node("Visual") as Sprite2D
	visual.region_rect = Rect2(Vector2(frame * NATIVE_SIZE.x, 0), NATIVE_SIZE)
	visible = phase not in ["inactive", "complete"]
	return current_sample.duplicate()

func _height_for_step(step: int) -> int:
	if step == STEPS_PER_TICK:
		return 51
	if step == 0 or step >= STEPS_PER_TICK * 2:
		return 0
	var progress := float(step if step < STEPS_PER_TICK else step-STEPS_PER_TICK) / STEPS_PER_TICK
	var value := 51.0 * 0.5 * (1.0-cos(PI*progress) if step < STEPS_PER_TICK else 1.0+cos(PI*progress))
	# One peak frame; no duplicated full-height pixels at the turn around.
	return clampi(floori(value + 0.500001), 1, 50)
