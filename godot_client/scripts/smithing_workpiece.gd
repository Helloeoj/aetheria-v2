extends Control
## Reusable staged shaping and quenching display, independent of recipe costs.
const Rules = preload("res://scripts/smithing_rules.gd")
var session: RefCounted
var finished_texture: Texture2D
var hiss: AudioStreamPlayer
var _hissed := false

func _ready() -> void:
	custom_minimum_size = Vector2(660, 270)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	hiss = AudioStreamPlayer.new()
	hiss.stream = _make_hiss()
	hiss.volume_db = -12.0
	add_child(hiss)
	gui_input.connect(_hammer_input)

func show_session(value: RefCounted) -> void:
	session = value
	_hissed = false
	finished_texture = ItemVisualLibrary.texture(session.output_name)
	refresh()

func refresh() -> void:
	if session != null and session.state in [SmithingSession.State.QUENCHING, SmithingSession.State.FINISHED] and session.quench_elapsed >= float(session.config.quench_lower_seconds) and not _hissed:
		_hissed = true
		hiss.play()
	queue_redraw()

func _hammer_input(event: InputEvent) -> void:
	if session != null and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		session.strike(event.position / size, size.x / size.y)
		refresh()
		accept_event()

func _draw() -> void:
	draw_style_box(FantasyUI.box(FantasyUI.INK), Rect2(Vector2.ZERO, size))
	if session == null:
		return
	if session.state in [SmithingSession.State.QUENCHING, SmithingSession.State.FINISHED]:
		_draw_quench()
		return
	# Anvil and pedestal retain the game's slate/gold UI palette.
	draw_rect(Rect2(size * Vector2(0.37, 0.83), size * Vector2(0.26, 0.12)), Color("4a4140"))
	draw_colored_polygon(_points([[0.26, 0.78], [0.74, 0.78], [0.68, 0.86], [0.38, 0.86]]), Color("7e8a92"))
	_draw_shape(session.shape_stage(), Color("ff9b38"))
	if session.state == SmithingSession.State.FORGING:
		var target: Vector2 = session.target_position() * size
		var radius := float(session.config.target_radius) * minf(size.x, size.y)
		draw_circle(target, radius + 6, Color(1.0, 0.82, 0.3, 0.17))
		draw_arc(target, radius, 0, TAU, 32, FantasyUI.GOLD, 3.0, true)
		draw_line(target - Vector2(7, 0), target + Vector2(7, 0), Color.WHITE, 2)
		draw_line(target - Vector2(0, 7), target + Vector2(0, 7), Color.WHITE, 2)

func _points(values: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for value: Array in values:
		result.append(Vector2(float(value[0]), float(value[1])) * size)
	return result

func _draw_shape(stage: int, glow: Color) -> void:
	var category: String = Rules.category(session.output_name)
	var shape: Array
	if stage == 0:
		shape = [[0.40, 0.25], [0.60, 0.25], [0.60, 0.77], [0.40, 0.77]]
	elif stage == 1:
		shape = [[0.46, 0.18], [0.58, 0.30], [0.61, 0.58], [0.55, 0.77], [0.45, 0.77], [0.39, 0.58]]
	else:
		match category:
			"sword": shape = [[0.50, 0.15], [0.56, 0.30], [0.55, 0.65], [0.62, 0.67], [0.62, 0.71], [0.53, 0.71], [0.53, 0.80], [0.47, 0.80], [0.47, 0.71], [0.38, 0.71], [0.38, 0.67], [0.45, 0.65], [0.44, 0.30]]
			"axe": shape = [[0.46, 0.22], [0.54, 0.22], [0.54, 0.32], [0.69, 0.24], [0.80, 0.35], [0.78, 0.59], [0.68, 0.65], [0.54, 0.55], [0.54, 0.79], [0.46, 0.79]]
			"helmet": shape = [[0.30, 0.62], [0.30, 0.41], [0.38, 0.26], [0.50, 0.20], [0.62, 0.26], [0.70, 0.41], [0.70, 0.62], [0.61, 0.70], [0.56, 0.52], [0.44, 0.52], [0.39, 0.70]]
			"chestplate": shape = [[0.22, 0.26], [0.40, 0.22], [0.44, 0.32], [0.56, 0.32], [0.60, 0.22], [0.78, 0.26], [0.72, 0.42], [0.65, 0.42], [0.64, 0.76], [0.36, 0.76], [0.35, 0.42], [0.28, 0.42]]
			"legs": shape = [[0.34, 0.24], [0.66, 0.24], [0.70, 0.77], [0.55, 0.77], [0.50, 0.45], [0.45, 0.77], [0.30, 0.77]]
			"shield": shape = [[0.29, 0.24], [0.71, 0.24], [0.68, 0.56], [0.50, 0.78], [0.32, 0.56]]
			"blunt": shape = [[0.30, 0.22], [0.70, 0.22], [0.70, 0.43], [0.54, 0.43], [0.54, 0.80], [0.46, 0.80], [0.46, 0.43], [0.30, 0.43]]
			_: shape = [[0.28, 0.31], [0.72, 0.31], [0.72, 0.67], [0.28, 0.67]]
	var polygon := _points(shape)
	draw_colored_polygon(polygon, glow)
	draw_polyline(polygon + PackedVector2Array([polygon[0]]), Color("ffe6a1"), 2.0, true)
	if stage >= int(session.config.shaping_stages) - 1:
		# A final scoring line distinguishes refined shaping from the rough outline.
		draw_line(size * Vector2(0.50, 0.31), size * Vector2(0.50, 0.64), Color("ffd47e"), 3.0)

func _draw_quench() -> void:
	var elapsed: float = session.quench_elapsed
	var lower := float(session.config.quench_lower_seconds)
	var immersed := lower + float(session.config.quench_immerse_seconds)
	var raise_seconds := float(session.config.quench_raise_seconds)
	var y := lerpf(0.26, 0.68, clampf(elapsed / lower, 0, 1))
	if elapsed > immersed:
		y = lerpf(0.68, 0.25, clampf((elapsed - immersed) / raise_seconds, 0, 1))
	var barrel := Rect2(size * Vector2(0.32, 0.55), size * Vector2(0.36, 0.37))
	draw_rect(barrel, Color("61452e"))
	draw_rect(barrel, FantasyUI.GOLD, false, 2)
	draw_ellipse_water(Vector2(0.50, 0.57), Vector2(0.18, 0.065))
	var hot := elapsed < immersed
	var object_rect := Rect2(Vector2(size.x * 0.5 - 43, size.y * y - 43), Vector2(86, 86))
	if finished_texture != null:
		draw_texture_rect(finished_texture, object_rect, false, Color("ff9748") if hot else Color.WHITE)
	else:
		draw_rect(object_rect.grow(-20), Color("ff9748") if hot else FantasyUI.IVORY)
	# Front water/body occludes the submerged object; steam stays in front.
	var submerged := maxf(size.y * 0.61, object_rect.position.y)
	if object_rect.end.y > submerged:
		draw_rect(Rect2(Vector2(barrel.position.x + 2, submerged), Vector2(barrel.size.x - 4, barrel.end.y - submerged - 2)), Color("61452e"))
	for belt in [0.69, 0.85]:
		draw_line(size * Vector2(0.32, belt), size * Vector2(0.68, belt), Color("a0a5aa"), 5)
	if elapsed >= lower and elapsed < immersed:
		for index in range(9):
			var wave := fmod(elapsed * 0.8 + float(index) * 0.19, 1.0)
			var x := 0.38 + float(index % 5) * 0.055
			draw_arc(size * Vector2(x, 0.59 - wave * 0.07), 3.0 + wave * 3, 0, TAU, 16, Color(0.6, 0.9, 1, 0.8), 1.5)
			draw_circle(size * Vector2(x + sin(elapsed * 3 + index) * 0.02, 0.49 - wave * 0.29), 6 + wave * 8, Color(0.85, 0.91, 0.94, (1 - wave) * 0.65))

func draw_ellipse_water(center: Vector2, radius: Vector2) -> void:
	var points := PackedVector2Array()
	for index in range(40):
		var angle := TAU * float(index) / 40.0
		points.append((center + Vector2(cos(angle), sin(angle)) * radius) * size)
	draw_colored_polygon(points, Color("37677c"))

func _make_hiss() -> AudioStreamWAV:
	# Filtered noise with a sharp attack and decaying steam tail, synthesized
	# once per view. Reusable and free of per-item audio/asset dependencies.
	var rate := 22050
	var samples := PackedByteArray()
	var random := RandomNumberGenerator.new()
	random.seed = 42817
	var filtered := 0.0
	for index in range(rate * 2):
		var t := float(index) / float(rate)
		var noise := random.randf_range(-1.0, 1.0)
		filtered = lerpf(filtered, noise, 0.35)
		var envelope := minf(1.0, t * 40.0) * exp(-t * 2.0)
		var sample := int(clampf((noise * 0.5 + filtered * 0.5) * envelope, -1, 1) * 22000)
		samples.append(sample & 255)
		samples.append((sample >> 8) & 255)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = samples
	return stream
