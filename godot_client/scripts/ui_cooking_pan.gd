extends Control
## Pixel-grid pan and short effects, using the shared inventory food texture.
## Pure presentation: animation callbacks never grant items or change session state.
var session: CookingSession
var raw_item := ""
var clock := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func set_cooking(current: CookingSession, selected: String) -> void:
	session = current
	raw_item = selected
	queue_redraw()

func _process(delta: float) -> void:
	if is_visible_in_tree():
		clock += delta
		queue_redraw()

func _draw() -> void:
	draw_style_box(FantasyUI.box(FantasyUI.INK, Color("4b453d")), Rect2(Vector2.ZERO, size))
	var center := Vector2(floorf(size.x * 0.5), 69)
	var pending := session != null and session.state == CookingSession.State.FLIP_PENDING
	var feedback := session != null and session.state == CookingSession.State.FEEDBACK
	var burnt := session != null and not session.last_result.is_empty() and bool(session.last_result.burnt) and session.state != CookingSession.State.COOKING and not pending
	var hot := session != null and session.is_active()
	var edge := FantasyUI.GOLD if pending else Color("68727c")
	if pending:
		var pulse := 0.5 + 0.5 * sin(clock * 8.0)
		draw_rect(Rect2(center + Vector2(-102, -49), Vector2(204, 92)), Color(edge, 0.08 + 0.12 * pulse))
	# Stepped silhouette and square handle maintain the existing pixel-art style.
	draw_rect(Rect2(center + Vector2(78, -8), Vector2(79, 17)), Color("141b24"))
	draw_rect(Rect2(center + Vector2(92, -4), Vector2(60, 9)), Color("55606a"))
	draw_colored_polygon(PackedVector2Array([center+Vector2(-90,-24),center+Vector2(-70,-42),center+Vector2(64,-42),center+Vector2(88,-24),center+Vector2(88,24),center+Vector2(64,40),center+Vector2(-70,40),center+Vector2(-90,24)]), edge)
	draw_rect(Rect2(center + Vector2(-80, -22), Vector2(160, 44)), Color("222b36"))
	draw_rect(Rect2(center + Vector2(-64, -32), Vector2(128, 64)), Color("222b36"))
	if hot and not burnt:
		for index in range(5):
			var step := floorf(fmod(clock * 5.0 + index * 2.0, 4.0))
			draw_rect(Rect2(center + Vector2(-60 + index * 28, 43 - step * 2), Vector2(9, 4)), Color("de8248"))
	var item := raw_item
	var tint := Color.WHITE
	if session != null and (feedback or session.state == CookingSession.State.FINISHED or session.state == CookingSession.State.CANCELLED) and not session.last_result.is_empty():
		item = String(session.last_result.output)
	if burnt:
		tint = Color("40372e")
	var texture := ItemVisualLibrary.texture(item)
	var lift := 0.0
	var angle := 0.0
	if feedback and not burnt:
		var phase := clampf(session.feedback_elapsed / CookingSession.FEEDBACK_SECONDS, 0.0, 1.0)
		lift = floorf(sin(phase * PI) * 32.0)
		angle = phase * TAU
	elif hot and not pending and not burnt:
		lift = floorf(sin(clock * 9.0) * 1.5)
	if texture != null:
		draw_set_transform(center + Vector2(0, -lift), angle)
		draw_texture_rect(texture, Rect2(-38, -25, 76, 50), false, tint)
		draw_set_transform(Vector2.ZERO)
	if burnt:
		for index in range(4):
			var rise := floorf(fmod(clock * 24.0 + index * 13.0, 54.0))
			draw_rect(Rect2(center + Vector2(-28 + index * 18, -24 - rise), Vector2(9, 7)), Color(0.5, 0.5, 0.52, 0.6 * (1.0 - rise / 60.0)))
	elif feedback:
		for index in range(4):
			var at := center + Vector2(-70 + index * 46, -35 - (index % 2) * 8)
			draw_rect(Rect2(at, Vector2(4, 10)), FantasyUI.TEAL)
			draw_rect(Rect2(at + Vector2(-3, 3), Vector2(10, 4)), FantasyUI.TEAL)
