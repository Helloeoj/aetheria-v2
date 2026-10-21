@tool
class_name FishingSpot
extends Node2D
## Separate animated water overlay; no creatures are baked into terrain art.
@export var spot_name := "Harbor shoal"
@export var shore_offset := Vector2(-64, 0)
@export var interact_radius := 110.0
var phase := 0.0
var fishing_session: FishingSession

func _process(delta: float) -> void:
	phase += delta
	queue_redraw()

func _draw() -> void:
	for index in range(3):
		var cycle := fmod(phase * 0.4 + float(index) / 3.0, 1.0)
		var points := PackedVector2Array()
		for step in range(33):
			var angle := float(step) / 32.0 * TAU + phase * 0.25
			points.append(Vector2(cos(angle), sin(angle) * 0.4) * lerpf(8.0, 32.0, cycle))
		draw_polyline(points, Color(0.65, 0.94, 1.0, (1.0 - cycle) * 0.8), 1.6, true)
	for index in range(5):
		var angle := phase * 0.65 + float(index) * TAU / 5.0
		draw_circle(Vector2(cos(angle) * 19, sin(angle) * 7), 1.6, Color(0.84, 1.0, 0.91, 0.7))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-45, -23), "Fishing [F]", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.97, 1.0))
	if fishing_session != null and fishing_session.state in [FishingSession.State.CASTING, FishingSession.State.WAITING, FishingSession.State.BITE, FishingSession.State.FIGHT]:
		var bobber := Vector2(fishing_session.lateral * 20, sin(phase * 4) * 2)
		draw_line(shore_offset + Vector2(0, -18), bobber, Color(0.9, 0.95, 0.9, 0.8), 1, true)
		draw_circle(bobber, 3, Color("e76b5a"))
		if fishing_session.state == FishingSession.State.BITE:
			draw_string(font, Vector2(-4, -24), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("ffe199"))

func contains_global_point(point: Vector2) -> bool:
	return to_local(point).length() <= 38.0

func shore_position() -> Vector2:
	return to_global(shore_offset)
