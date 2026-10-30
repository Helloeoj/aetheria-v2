extends SceneTree
## Graphical review only; never changes runtime catalogs, scenes or gameplay.
## Godot --path godot_client --script res://scripts/dev_tools/golem_titan_animation_review.gd -- --social-no-auto --asset-dir=ABS --output=ABS [--clip=idle|shockwave_slam]

const CONTENT := "res://scenes/GolemKingdomContent.tscn"
const FLOOR_MANIFEST := "res://Assets/Maps/GolemKingdom/manifest.json"
const NATIVE_SIZE := Vector2i(256, 256)
const FOOT_ANCHOR := Vector2(128, 240)
const FOOTPRINT_SIZE := Vector2(144, 64)
const CONTACT_OFFSETS := [Vector2(-50, 8), Vector2(50, 8)]

var asset_dir := ""
var output_dir := ""
var requested_clip := ""
var failures: Array[String] = []
var captures: Array[Dictionary] = []
var floor_polygons: Array[PackedVector2Array] = []
var viewport: SubViewport
var camera: Camera2D
var content: Node2D
var titan: Node2D
var visual: AnimatedSprite2D
var player: ActorSprite
var titan_position := Vector2.ZERO
var player_position := Vector2.ZERO
var chosen_area := ""
var scene_hash := ""
var tested_positions := 0
var source_index_order: Array = []

class ContactGuide extends Node2D:
	func _draw() -> void:
		draw_line(Vector2(-128, 0), Vector2(128, 0), Color(0.2, 1, 0.3), 0.75)
		for point: Vector2 in CONTACT_OFFSETS:
			draw_line(point - Vector2(5, 0), point + Vector2(5, 0), Color(1, 0.3, 0.8), 0.75)
			draw_line(point - Vector2(0, 5), point + Vector2(0, 5), Color(1, 0.3, 0.8), 0.75)
		var rect := Rect2(Vector2(-72, -48), FOOTPRINT_SIZE)
		draw_rect(rect, Color(0.1, 0.8, 1), false, 0.75)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--asset-dir="):
			asset_dir = argument.trim_prefix("--asset-dir=").simplify_path()
		elif argument.begins_with("--output="):
			output_dir = argument.trim_prefix("--output=").simplify_path()
		elif argument.begins_with("--clip="):
			requested_clip = argument.trim_prefix("--clip=")
	var project_dir := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/").to_lower()
	var repository_dir := project_dir.get_base_dir()
	if not asset_dir.is_absolute_path() or not DirAccess.dir_exists_absolute(asset_dir):
		_fail("--asset-dir must identify an existing absolute candidate directory.")
	if not output_dir.is_absolute_path() or output_dir.replace("\\", "/").to_lower().begins_with(repository_dir + "/") or output_dir.to_lower() == repository_dir:
		_fail("--output must be an absolute evidence directory outside the repository.")
	if not requested_clip.is_empty() and requested_clip not in ["idle", "shockwave_slam"]:
		_fail("--clip must be idle or shockwave_slam.")
	if DisplayServer.get_name() == "headless":
		_fail("Actual GPU captures require graphical Godot; omit --headless.")
	if not failures.is_empty():
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		_fail("Cannot create evidence directory.")
		quit(1)
		return
	var manifest: Dictionary = {}
	var manifest_path := asset_dir.path_join("manifest.json")
	if FileAccess.file_exists(manifest_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if parsed is Dictionary:
			manifest = parsed
	var floor_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FLOOR_MANIFEST))
	for source: Array in floor_data.walkable_polygons_source.values():
		var polygon := PackedVector2Array()
		for point: Array in source:
			polygon.append(Vector2(point[0], point[1]) * float(floor_data.world_scale))
		floor_polygons.append(polygon)
	scene_hash = FileAccess.get_sha256(CONTENT)
	root.position = Vector2i(-10000, -10000)
	root.size = Vector2i(320, 240)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 1280)
	viewport.disable_3d = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	var review_root := Node2D.new()
	review_root.y_sort_enabled = true
	viewport.add_child(review_root)
	print("[Titan review] Loading actual unchanged content scene.")
	content = (load(CONTENT) as PackedScene).instantiate()
	review_root.add_child(content)
	print("[Titan review] Content loaded; registering actual physics.")
	await physics_frame
	await physics_frame
	if not _choose_floor():
		_fail("No tested floor position fits the review footprint, both contact guides and player approach.")
		_finish()
		return
	titan = Node2D.new()
	titan.position = titan_position
	review_root.add_child(titan)
	visual = AnimatedSprite2D.new()
	visual.offset = Vector2(NATIVE_SIZE) * 0.5 - FOOT_ANCHOR
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	titan.add_child(visual)
	player = ActorSprite.new().configure(Vector2(32, 32), Color.BLUE, "titan_review_only_peasant")
	review_root.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.set_skin("peasant")
	player.animated_sprite.pause()
	player.position = player_position
	if not player.animated_sprite.scale.is_equal_approx(Vector2(0.75, 0.75)):
		_fail("The unchanged peasant must retain its actual runtime 0.75 visual scale.")
	camera = Camera2D.new()
	viewport.add_child(camera)
	camera.position = titan_position + Vector2(24, -84)
	camera.make_current()
	titan.hide()
	await _capture("context", -1, 0.68, "actual-map-and-player", "baseline")
	await _capture("context", -1, 4.0, "actual-map-and-player", "baseline")
	titan.show()
	for clip: String in ["idle", "shockwave_slam"]:
		if not requested_clip.is_empty() and clip != requested_clip:
			continue
		await _capture_clip(clip, manifest.get("clips", {}).get(clip, {}))
	_finish()

func _fail(message: String) -> void:
	failures.append(message)
	printerr("[Titan review] ", message)

func _floor_contains(point: Vector2) -> bool:
	for polygon: PackedVector2Array in floor_polygons:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false

func _clear(center: Vector2, dimensions: Vector2) -> bool:
	var rectangle := Rect2(center - dimensions * 0.5, dimensions)
	for y in range(0, ceili(dimensions.y) + 1, 8):
		for x in range(0, ceili(dimensions.x) + 1, 8):
			if not _floor_contains(rectangle.position + Vector2(x, y)):
				return false
	var shape := RectangleShape2D.new()
	shape.size = dimensions
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0, center)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.margin = 0.08
	return viewport.world_2d.direct_space_state.intersect_shape(query, 1).is_empty()

func _choose_floor() -> bool:
	var areas := {"CentralCourtyard": Vector2(2037, 2110), "RoyalCourt": Vector2(1305, 1170), "StoneWorkyard": Vector2(1152, 2394), "NortheastTerrace": Vector2(2544, 810)}
	for area: String in areas:
		for dy in [0, 16, 32, -16, -32, 48, -48, 64]:
			for dx in [0, 16, -16, 32, -32, 48, -48]:
				var anchor: Vector2 = areas[area] + Vector2(dx, dy)
				tested_positions += 1
				if not _clear(anchor + Vector2(0, -16), FOOTPRINT_SIZE):
					continue
				if not _clear(anchor + CONTACT_OFFSETS[0], Vector2(16, 16)) or not _clear(anchor + CONTACT_OFFSETS[1], Vector2(16, 16)):
					continue
				for approach: Vector2 in [Vector2(0, 64), Vector2(156, 24), Vector2(-156, 24)]:
					if _clear(anchor + approach, Vector2(24, 24)):
						titan_position = anchor
						player_position = anchor + approach
						chosen_area = area
						print("[Titan review] Chosen actual floor: ", area, " Titan=", anchor, " player=", player_position)
						return true
	return false

func _capture_clip(clip: String, definition: Dictionary) -> void:
	var frame_dir := asset_dir.path_join(clip).path_join("frames")
	var paths: Array[String] = []
	for filename: String in DirAccess.get_files_at(frame_dir):
		if filename.get_extension().to_lower() == "png":
			paths.append(frame_dir.path_join(filename))
	paths.sort()
	if paths.is_empty():
		_fail("No PNG frames found for " + clip)
		return
	if definition.has("frame_count") and int(definition.frame_count) != paths.size():
		_fail("Manifest frame count differs from source folder for " + clip)
		return
	source_index_order = definition.get("source_index_order", [])
	var frames := SpriteFrames.new()
	frames.add_animation(clip)
	frames.set_animation_speed(clip, 1.0)
	frames.set_animation_loop(clip, clip == "idle")
	var durations: Array = definition.get("durations_ms", [])
	for index in paths.size():
		var image := Image.load_from_file(paths[index])
		if image == null or image.is_empty() or image.get_size() != NATIVE_SIZE:
			_fail("Expected a lossless native 256x256 frame: " + paths[index])
			return
		var milliseconds := float(durations[index]) if index < durations.size() else (220.0 if clip == "idle" else 120.0)
		frames.add_frame(clip, ImageTexture.create_from_image(image), milliseconds / 1000.0)
	visual.sprite_frames = frames
	visual.play(clip)
	visual.pause()
	for index in paths.size():
		visual.frame = index
		for zoom: float in [1.0, 4.0]:
			await _capture(clip, index, zoom, paths[index], "artwork")
		if index == 0 or index == paths.size() / 2:
			await _capture(clip, index, 0.68, paths[index], "artwork")
	var guide := ContactGuide.new()
	guide.position = titan_position
	guide.z_index = 1000
	viewport.add_child(guide)
	visual.frame = clampi(int(definition.get("contact_frame", 6)), 0, paths.size() - 1) if clip == "shockwave_slam" else 0
	await _capture(clip, visual.frame, 4.0, paths[visual.frame], "guide-only-not-contact-proof")
	guide.queue_free()
	await process_frame

func _capture(clip: String, index: int, zoom: float, source: String, kind: String) -> void:
	camera.zoom = Vector2.ONE * zoom
	camera.force_update_scroll()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := output_dir.path_join(clip).path_join("zoom-" + str(zoom))
	DirAccess.make_dir_recursive_absolute(folder)
	var filename := folder.path_join("%s-frame-%02d.png" % [kind, index])
	var rendered := viewport.get_texture().get_image()
	if rendered == null or rendered.is_empty() or rendered.save_png(filename) != OK:
		_fail("Could not save actual Godot render: " + filename)
		return
	var duration_ms := 0.0
	if index >= 0:
		duration_ms = visual.sprite_frames.get_frame_duration(clip, index) / visual.sprite_frames.get_animation_speed(clip) * 1000.0
	captures.append({"path": filename, "clip": clip, "frame": index, "original_source_index": source_index_order[index] if index >= 0 and index < source_index_order.size() else index, "duration_ms": duration_ms, "zoom": zoom, "source": source, "source_sha256": FileAccess.get_sha256(source) if FileAccess.file_exists(source) else "", "kind": kind, "camera_world_xy": [camera.position.x, camera.position.y], "viewport": [viewport.size.x, viewport.size.y]})

func _finish() -> void:
	if scene_hash != FileAccess.get_sha256(CONTENT):
		_fail("Actual content scene changed during rendering; evidence needs rerendering.")
	var report := {"actual_scene": CONTENT, "scene_sha256": scene_hash, "floor_manifest_sha256": FileAccess.get_sha256(FLOOR_MANIFEST), "asset_dir": asset_dir,
		"native_canvas": [256, 256], "foot_anchor": [128, 240], "world_pixels_per_source_pixel": 1, "chosen_area": chosen_area,
		"titan_world_xy": [titan_position.x, titan_position.y], "player_world_xy": [player_position.x, player_position.y], "tested_positions": tested_positions,
		"review_footprint_size": [144, 64], "review_footprint_center_offset": [0, -16], "contact_guide_offsets": [[-50, 8], [50, 8]], "contact_guide_is_artwork_acceptance": false,
		"actual_collision_mask": 1, "floor_grid_sample_step": 8, "player_skin": "peasant", "player_visual_scale": [player.animated_sprite.scale.x, player.animated_sprite.scale.y] if player != null else [],
		"captures": captures, "failures": failures, "rendering_completed": failures.is_empty() and not captures.is_empty(),
		"visual_approval": "pending", "runtime_installation": "not_performed", "integration_and_placement": "pending",
		"scope": "Actual unchanged Golem Kingdom content and materials, temporary review actors only. Floor/body queries support review positioning; they do not certify boss placement, gameplay, hand contact, animation anatomy or visual approval. Animated actor artwork is outside worldbuilding.py passive-prop scope."}
	var file := FileAccess.open(output_dir.path_join("godot-animation-review.json"), FileAccess.WRITE)
	if file == null:
		_fail("Cannot save render report.")
	else:
		file.store_string(JSON.stringify(report, "  ") + "\n")
		file.close()
	print("[Titan review] ", captures.size(), " actual GPU captures; ", failures.size(), " failures. Visual approval and placement pending.")
	quit(0 if failures.is_empty() else 1)
