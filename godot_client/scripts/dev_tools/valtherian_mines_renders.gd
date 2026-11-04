extends SceneTree
## Genuine GPU renders of installed content. No source textures are edited.
const CONTENT := "res://scenes/ValtherianMinesContent.tscn"
const LAYOUT := "res://Assets/Maps/ValtherianMines/layout.json"
const WALLS := "res://Assets/Maps/ValtherianMines/wall-props.json"
const DECOR := "res://Assets/Maps/ValtherianMines/decor-props.json"
const FLOOR := preload("res://scripts/dev_tools/valtherian_native_floor.gd")
var output_dir := ""
var viewport: SubViewport
var camera: Camera2D
var content: Node2D
var actor: ActorSprite
var layout: Dictionary
var rendered: Array[String] = []
var failures: Array[String] = []
var body := RectangleShape2D.new()
var loaded_scene_sha := ""
var loaded_layout_sha := ""
var loaded_wall_sha := ""
var loaded_decor_sha := ""
var overlay_only := false
var overlay_shape_paths: Array[String] = []

func _initialize() -> void:
	output_dir = OS.get_user_data_dir().path_join("valtherian-map-renders")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_dir = argument.trim_prefix("--output=")
		elif argument == "--overlay-only":
			overlay_only = true
	_run.call_deferred()

func vector(pair: Array) -> Vector2:
	return Vector2(pair[0],pair[1])

func make_actor(id: String, parent: Node) -> ActorSprite:
	var result := ActorSprite.new().configure(Vector2(32,32),Color.BLUE,id)
	parent.add_child(result)
	result.set_process(false)
	result.set_physics_process(false)
	result.set_skin("peasant")
	result.animated_sprite.pause()
	return result

func body_clear(point: Vector2) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = body
	query.transform = Transform2D(0,point)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.margin = 0.08
	return content.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()

func capture(name: String, center: Vector2, zoom: float, size: Vector2i) -> void:
	viewport.size = size
	camera.position = center.round()
	camera.zoom = Vector2.ONE * zoom
	camera.force_update_scroll()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var error := viewport.get_texture().get_image().save_png(output_dir.path_join(name))
	if error == OK:
		rendered.append(name)
		print("[Valtherian GPU render] ",name)
	else:
		failures.append("Could not save " + name)

func _run() -> void:
	if not ResourceLoader.exists(CONTENT) or not FileAccess.file_exists(LAYOUT):
		printerr("Actual Valtherian content/layout missing; no render performed")
		quit(1)
		return
	body.size = Vector2(24,24)
	DirAccess.make_dir_recursive_absolute(output_dir)
	loaded_scene_sha = FileAccess.get_sha256(CONTENT)
	loaded_layout_sha = FileAccess.get_sha256(LAYOUT)
	loaded_wall_sha = FileAccess.get_sha256(WALLS)
	loaded_decor_sha = FileAccess.get_sha256(DECOR)
	layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	root.position = Vector2i(-10000,-10000)
	root.size = Vector2i(320,240)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1536,1024)
	viewport.disable_3d = true
	viewport.world_2d = World2D.new()
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var backdrop := ColorRect.new()
	backdrop.position = Vector2(-256,-256)
	backdrop.size = Vector2(6656,3840)
	backdrop.color = Color(0.02,0.025,0.028)
	backdrop.z_index = -200
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(backdrop)
	content = (load(CONTENT) as PackedScene).instantiate()
	viewport.add_child(content)
	actor = make_actor("valtherian_actual_content_visual_review_only",content)
	actor.position = Vector2(6032,2064)
	camera = Camera2D.new()
	viewport.add_child(camera)
	camera.make_current()
	await physics_frame
	await physics_frame
	if overlay_only:
		await physics_overlays()
		await finish_render_report("valtherian-mine-overlay-report.json")
		return
	await capture("valtherian-native-overview-1x.png",Vector2(3072,1664),1,Vector2i(6400,3584))
	await capture("valtherian-entrance-gameplay-1x.png",Vector2(5856,2048),1,Vector2i(1280,720))
	# Save one marked node immediately so art review can run during the rest.
	var first: Dictionary = layout.ores[0]
	actor.position = vector(first.approach_world_xy)
	await capture("valtherian-ore-"+str(first.id)+"-4x.png",vector(first.position)-Vector2(0,32),4,Vector2i(1536,1024))
	for ore: Dictionary in layout.ores:
		if ore.id == first.id:
			continue
		actor.position = vector(ore.approach_world_xy)
		await capture("valtherian-ore-"+str(ore.id)+"-4x.png",vector(ore.position)-Vector2(0,32),4,Vector2i(1536,1024))
	for room: Dictionary in layout.rooms:
		var rect: Array = room.clear_rect_cells
		var center_x := (float(rect[0])+float(rect[2])*0.5)*32.0
		var candidate := Vector2(floorf(center_x/32.0)*32.0+16.0,float(rect[1])*32.0+112.0)
		var placed := false
		for delta in [Vector2.ZERO,Vector2(32,0),Vector2(-32,0),Vector2(0,32),Vector2(64,32),Vector2(-64,32)]:
			if body_clear(candidate+delta):
				actor.position = candidate+delta
				placed = true
				break
		if not placed:
			failures.append("No safe render-only player position for " + str(room.id))
		await capture("valtherian-room-"+str(room.id)+"-4x.png",Vector2(center_x,float(rect[1])*32.0+32.0),4,Vector2i(1536,1024))
		var south_y := (float(rect[1])+float(rect[3])+1.0)*32.0
		var south_candidate := Vector2(floorf(center_x/32.0)*32.0+16.0,south_y-16.0)
		placed = false
		for offset in [0,32,-32,64,-64,96,-96]:
			if body_clear(south_candidate+Vector2(offset,0)):
				actor.position = south_candidate+Vector2(offset,0)
				placed = true
				break
		if not placed:
			failures.append("No safe near-south-wall player position for "+str(room.id))
		await capture("valtherian-south-depth-"+str(room.id)+"-4x.png",Vector2(center_x,south_y-64.0),4,Vector2i(1536,1024))
		var room_center := Vector2(floorf(center_x/32.0)*32.0+16.0,(float(rect[1])+floorf(float(rect[3])*0.5))*32.0+16.0)
		if body_clear(room_center):
			actor.position = room_center
		else:
			failures.append("Room center obstructed at gameplay render "+str(room.id))
		await capture("valtherian-gameplay-"+str(room.id)+"-1x.png",Vector2(center_x,(float(rect[1])+float(rect[3])*0.5)*32.0),1,Vector2i(1280,720))
	for decor: Dictionary in layout.decor_props:
		var anchor := vector(decor.position)
		var candidate := anchor+Vector2(0,80)
		var placed := false
		for offset in [0,32,-32,64,-64]:
			if body_clear(candidate+Vector2(offset,0)):
				actor.position = candidate+Vector2(offset,0)
				placed = true
				break
		if not placed:
			failures.append("No safe player comparison at "+str(decor.name))
		await capture("valtherian-support-"+str(decor.name)+"-4x.png",anchor+Vector2(-16,16),4,Vector2i(1536,1024))
	content.visible = false
	backdrop.visible = false
	await wall_previews()
	await finish_render_report("valtherian-mine-render-report.json")

func finish_render_report(report_name: String) -> void:
	if loaded_scene_sha != FileAccess.get_sha256(CONTENT) or loaded_layout_sha != FileAccess.get_sha256(LAYOUT) or loaded_wall_sha != FileAccess.get_sha256(WALLS) or loaded_decor_sha != FileAccess.get_sha256(DECOR):
		failures.append("Scene/layout/prop manifest changed during GPU rendering; rerender the final revision")
	var report := {"actual_scene":CONTENT,"scene_sha256":loaded_scene_sha,"layout_sha256":loaded_layout_sha,"wall_manifest_sha256":loaded_wall_sha,"decor_manifest_sha256":loaded_decor_sha,"render_count":rendered.size(),"rendered":rendered,"failures":failures,
		"camera_zoom4_is_actual":true,"player":"Unchanged64px peasant at runtime0.75visual scale; render-only actor, never baked in environment source",
		"physical_overlay_only":overlay_only,"actual_shape_paths":overlay_shape_paths,
		"scope":"Render evidence only; saving screenshots does not automatically grant visual artwork approval or physics/travel acceptance"}
	var file := FileAccess.open(output_dir.path_join(report_name),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	print("[Valtherian GPU summary] ",JSON.stringify(report))
	viewport.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func make_physics_overlay() -> Node2D:
	var overlay := Node2D.new()
	overlay.z_index = 1000
	viewport.add_child(overlay)
	var actual_actor_base := actor.get_node("BodyCollision")
	for node: Node in content.find_children("*","",true,false):
		var local_points := PackedVector2Array()
		if node is CollisionShape2D:
			if node.disabled or node.shape == null:
				continue
			if not node.get_parent() is CollisionObject2D:
				continue
			if (node.get_parent().collision_layer & 1) == 0 and node != actual_actor_base:
				continue
			if node.shape is RectangleShape2D:
				var half: Vector2 = node.shape.size * 0.5
				local_points = PackedVector2Array([Vector2(-half.x,-half.y),Vector2(half.x,-half.y),Vector2(half.x,half.y),Vector2(-half.x,half.y)])
			else:
				failures.append("Unimplemented exact debug outline for " + str(node.get_path()))
				continue
		elif node is CollisionPolygon2D:
			if node.disabled or not node.get_parent() is CollisionObject2D or (node.get_parent().collision_layer & 1) == 0:
				continue
			local_points = node.polygon
		else:
			continue
		var outline := Line2D.new()
		outline.width = 0.75
		outline.default_color = Color(0.1,1.0,0.25,1.0)
		outline.antialiased = false
		outline.closed = true
		for point: Vector2 in local_points:
			outline.add_point(overlay.to_local(node.to_global(point)))
		overlay.add_child(outline)
		var path := str(content.get_path_to(node))
		if not overlay_shape_paths.has(path):
			overlay_shape_paths.append(path)
	return overlay

func physics_overlays() -> void:
	var seen_rooms := {}
	for ore: Dictionary in layout.ores:
		if seen_rooms.has(ore.room_id):
			continue
		seen_rooms[ore.room_id] = true
		actor.position = vector(ore.approach_world_xy)
		if not body_clear(actor.position):
			failures.append("Overlay actor approach blocked at "+str(ore.id))
		var overlay := make_physics_overlay()
		await capture("valtherian-physics-"+str(ore.room_id)+"-4x.png",vector(ore.position)-Vector2(0,32),4,Vector2i(1536,1024))
		overlay.queue_free()
		await process_frame
	if seen_rooms.size() != 6:
		failures.append("Expected6 populated ore rooms in physical overlay")
	var room: Dictionary = layout.rooms[0]
	var rect: Array = room.clear_rect_cells
	var center_x := (float(rect[0])+float(rect[2])*0.5)*32.0
	var south_y := (float(rect[1])+float(rect[3])+1.0)*32.0
	actor.position = Vector2(floorf(center_x/32.0)*32+16,south_y-16)
	if not body_clear(actor.position):
		failures.append("Last legal floor-row overlay actor body is blocked")
	var overlay := make_physics_overlay()
	await capture("valtherian-physics-south-wall-4x.png",Vector2(center_x,south_y-64),4,Vector2i(1536,1024))
	overlay.queue_free()
	await process_frame

func wall_previews() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WALLS))
	var decor: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DECOR))
	var units: Array = manifest.units.duplicate()
	units.append_array(decor.units)
	var preview := Node2D.new()
	preview.y_sort_enabled = true
	viewport.add_child(preview)
	var background := ColorRect.new()
	background.size = Vector2(384,384)
	background.z_index = -200
	preview.add_child(background)
	var cells: Array = []
	for y in range(12):
		for x in range(12):
			cells.append([x,y])
	var ground := FLOOR.build(cells)
	preview.add_child(ground)
	var index := 0
	for unit: Dictionary in units:
		var origin := Vector2((index%3)*128,(index/3)*128)
		var prop: Node2D = (load(unit.scene) as PackedScene).instantiate()
		preview.add_child(prop)
		prop.position = origin+Vector2(40,104)
		var comparison := make_actor("wall_native_comparison_"+str(index),preview)
		comparison.position = origin+Vector2(96,104)
		index += 1
	ground.visible = false
	background.color = Color.WHITE
	await capture("valtherian-wall-props-white-4x.png",Vector2(192,192),4,Vector2i(1536,1536))
	background.color = Color(0.02,0.025,0.028)
	await capture("valtherian-wall-props-dark-4x.png",Vector2(192,192),4,Vector2i(1536,1536))
	ground.visible = true
	await capture("valtherian-wall-props-ground-4x.png",Vector2(192,192),4,Vector2i(1536,1536))
	preview.queue_free()
	await process_frame
