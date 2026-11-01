extends Node2D
## Presentation only. The combat engine owns cells, timestamps and damage.
## Position this root at the authoritative 32px tile center. Sample externally.
const NATIVE_SIZE := Vector2(48, 64)
const GROUND_ANCHOR := Vector2(24, 52)
const DEFAULT_WARNING_SECONDS := 1.020
const STRIKE_FRAME_MS := 30
const STRIKE_HEIGHTS := [6, 24, 51, 34, 16, 4, 0, 0, 0]
var current_sample: Dictionary = {"phase":"inactive", "frame":13, "height_px":0}

func _ready() -> void:
	visible = false

func sample_at_seconds(elapsed: float, warning_seconds: float = DEFAULT_WARNING_SECONDS) -> Dictionary:
	var frame := 13
	var phase := "inactive"
	var height := 0
	if is_finite(elapsed) and is_finite(warning_seconds) and elapsed >= 0.0 and warning_seconds > 0.0:
		var milliseconds := roundi(elapsed * 1000.0)
		var warning_ms := maxi(1, roundi(warning_seconds * 1000.0))
		if milliseconds < warning_ms:
			frame = mini(3, int(float(milliseconds) / float(warning_ms) * 4.0))
			phase = "warning"
		else:
			var strike_index := int(float(milliseconds - warning_ms) / STRIKE_FRAME_MS)
			if strike_index < STRIKE_HEIGHTS.size():
				frame = 4 + strike_index
				height = STRIKE_HEIGHTS[strike_index]
				phase = "eruption" if strike_index <= 2 else ("retraction" if height > 0 else "cleanup")
			else:
				phase = "complete"
	current_sample = {"phase":phase, "frame":frame, "height_px":height}
	var visual := get_node("Visual") as Sprite2D
	visual.region_rect = Rect2(Vector2(frame * NATIVE_SIZE.x, 0), NATIVE_SIZE)
	visible = phase not in ["inactive", "complete"]
	return current_sample.duplicate()
