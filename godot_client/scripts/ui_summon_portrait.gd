extends Control
## Native idle frames retain their exact source pixels and ground anchors.
var frames: Array = []
var textures: Array[Texture2D] = []
var fps := 6.0
var elapsed := 0.0
var frame_index := 0

func configure(clip: Dictionary) -> void:
	frames = clip.frames
	fps = float(clip.fps)
	textures.clear()
	for frame: Dictionary in frames:
		textures.append(load(String(frame.src)))
	custom_minimum_size = Vector2(0, 200)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _process(delta: float) -> void:
	if not is_visible_in_tree() or frames.is_empty():
		return
	elapsed += delta
	var next_frame := int(elapsed * fps) % frames.size()
	if next_frame != frame_index:
		frame_index = next_frame
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), FantasyUI.NAVY)
	if frames.is_empty():
		return
	var frame: Dictionary = frames[frame_index]
	var ground := Vector2(floorf(size.x * 0.5), size.y - 32.0)
	var anchor := Vector2(float(frame.anchor[0]), float(frame.anchor[1]))
	var native_size := Vector2(float(frame.w), float(frame.h))
	draw_texture_rect(textures[frame_index], Rect2((ground - anchor * 2.0).round(), native_size * 2.0), false)
