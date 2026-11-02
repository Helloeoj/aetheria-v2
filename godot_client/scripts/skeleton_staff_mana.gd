extends Sprite2D

## Decorative staff-tip mana, synchronized to the authored Acolyte cast poses.
## It never spawns or changes the gameplay spell projectile.
const DATA_PATH := "res://data/skeleton_acolyte_staff_mana.json"
static var _definition: Dictionary = {}
var visual: AnimatedSprite2D

func _ready() -> void:
	if _definition.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			_definition = parsed
	texture = load(String(_definition.get("sheet", ""))) as Texture2D
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	centered = false
	region_enabled = true
	z_index = 1
	visible = false

func _process(_delta: float) -> void:
	visible = false
	if visual == null or not visual.is_playing():
		return
	var animation := String(visual.animation)
	if not animation.begins_with("attack_"):
		return
	var direction := animation.trim_prefix("attack_")
	var anchors: Array = _definition.get("staff_tip_positions", {}).get(direction, [])
	var frame := visual.frame
	var start := int(_definition.get("start_frame",1))
	var count := int(_definition.get("frame_count",9))
	if anchors.size() != 12 or frame < start or frame >= start + count:
		return
	var size: Array = _definition["tile_size"]
	var columns := int(_definition["columns"])
	var tile := frame-start
	region_rect = Rect2(float(tile%columns)*float(size[0]),floorf(float(tile)/float(columns))*float(size[1]),float(size[0]),float(size[1]))
	var point: Array = anchors[frame]
	var canvas: Array = _definition["source_canvas"]
	var offset_from_tip: Array = _definition["origin_offset"]
	# Sprite offsets move texture pixels, not child nodes. Apply the same
	# native canvas center and feet offset before the shared parent scale.
	position = Vector2(float(point[0]),float(point[1])) - Vector2(float(canvas[0]),float(canvas[1]))*0.5 + visual.offset + Vector2(float(offset_from_tip[0]),float(offset_from_tip[1]))
	visible = texture != null
