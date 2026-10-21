extends "res://scripts/main.gd"
## The catacombs use a closer camera while other areas retain their own clamp.
const CATACOMBS_MIN_ZOOM := 3.0
const CATACOMBS_MAX_ZOOM := 4.0

func _ready() -> void:
	super._ready()
	var camera := get_node("../MapCamera") as Camera2D
	camera.zoom = Vector2.ONE * clampf(camera.zoom.x, CATACOMBS_MIN_ZOOM, CATACOMBS_MAX_ZOOM)

func _zoom_map_camera(wheel_steps: float) -> void:
	var camera := get_node_or_null("../MapCamera") as Camera2D
	if camera == null:
		return
	var next_zoom := clampf(camera.zoom.x * pow(CAMERA_ZOOM_STEP, wheel_steps), CATACOMBS_MIN_ZOOM, CATACOMBS_MAX_ZOOM)
	camera.zoom = Vector2.ONE * next_zoom
	_update_map_camera()
