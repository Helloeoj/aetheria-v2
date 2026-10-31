extends SceneTree
## Capture installed clarity artwork and all marked ore approaches in real Godot.
## Saving captures is automatic evidence, not artwork approval.
const CONTENT:="res://scenes/ValtherianMinesContent.tscn"
const LAYOUT:="res://Assets/Maps/ValtherianMines/layout.json"
var output_dir:String
var rendered:Array[String]=[]
class PhysicsOverlay extends Node2D:
	var outlines:Array[PackedVector2Array]=[]
	func _draw() -> void:
		for outline in outlines:
			draw_polyline(outline,Color(0.1,1,0.3),0.75)
func _initialize() -> void:
	output_dir=OS.get_user_data_dir().path_join("valtherian-clarity-review")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_dir=argument.trim_prefix("--output=")
	_run.call_deferred()
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output_dir)
	root.position=Vector2i(-10000,-10000)
	root.size=Vector2i(320,240)
	var layout:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var scene_hash:=FileAccess.get_sha256(CONTENT)
	var layout_hash:=FileAccess.get_sha256(LAYOUT)
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(1703,924)
	viewport.world_2d=World2D.new()
	viewport.disable_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	var content:Node2D=load(CONTENT).instantiate()
	viewport.add_child(content)
	var camera:=Camera2D.new()
	viewport.add_child(camera)
	camera.position=Vector2(3072,1664)
	camera.zoom=Vector2(1703.0/6144.0,924.0/3328.0)
	camera.make_current()
	content.get_node("Ores").hide()
	await capture(viewport,camera,"detail-source-render-native.png")
	content.get_node("Ores").show()
	await capture(viewport,camera,"detail-map-with-marked-ores.png")
	var actor:=ActorSprite.new().configure(Vector2(32,32),Color.BLUE,"clarity_review_only")
	content.add_child(actor)
	actor.set_process(false)
	actor.set_skin("peasant")
	actor.animated_sprite.pause()
	viewport.size=Vector2i(1024,768)
	for ore:Dictionary in layout.ores:
		actor.position=Vector2(ore.approach_world_xy[0],ore.approach_world_xy[1])
		camera.position=Vector2(ore.position[0],ore.position[1])-Vector2(0,24)
		camera.zoom=Vector2(4,4)
		await capture(viewport,camera,"detail-"+str(ore.id)+"-4x.png")
	var rooms_seen:={}
	for ore:Dictionary in layout.ores:
		if rooms_seen.has(ore.room_id):
			continue
		rooms_seen[ore.room_id]=true
		actor.position=Vector2(ore.approach_world_xy[0],ore.approach_world_xy[1])
		camera.position=Vector2(ore.position[0],ore.position[1])-Vector2(0,24)
		var overlay:=PhysicsOverlay.new()
		overlay.z_index=1000
		viewport.add_child(overlay)
		collect_physics(content,overlay)
		overlay.queue_redraw()
		await capture(viewport,camera,"detail-physics-"+str(ore.room_id)+"-4x.png")
		overlay.queue_free()
		await process_frame
	actor.position=Vector2(6032,2064)
	camera.position=actor.position
	camera.zoom=Vector2.ONE
	viewport.size=Vector2i(1280,720)
	await capture(viewport,camera,"detail-arrival-1x.png")
	var passed:=scene_hash==FileAccess.get_sha256(CONTENT) and layout_hash==FileAccess.get_sha256(LAYOUT)
	var report:={"passed":passed,"scene_sha256":scene_hash,"layout_sha256":layout_hash,"source_sha256":FileAccess.get_sha256(layout.approved_art.texture),"rendered":rendered,"scope":"Installed detail restoration and all29 unchanged ore approaches; actual4x and1x. Capture integrity only; physics, source/import identity and visual review are separate.","native_map_size":layout.detail_art.native_size,"world_size":layout.world_size,"ore_native_size":[128,128],"ore_visual_density":0.75,"artwork_approval":false}
	var file:=FileAccess.open(output_dir.path_join("detail-render-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print(JSON.stringify({"passed":passed,"renders":rendered.size(),"scene_sha256":scene_hash}))
	quit(0 if passed else 1)
func collect_physics(node:Node,overlay:PhysicsOverlay) -> void:
	var points:=PackedVector2Array()
	if node is CollisionPolygon2D and not node.disabled:
		for point:Vector2 in node.polygon:
			points.append(node.to_global(point))
	elif node is CollisionShape2D and not node.disabled and node.shape is RectangleShape2D:
		var half:Vector2=node.shape.size*0.5
		for point:Vector2 in [-half,Vector2(half.x,-half.y),half,Vector2(-half.x,half.y)]:
			points.append(node.to_global(point))
	if not points.is_empty():
		points.append(points[0])
		overlay.outlines.append(points)
	for child:Node in node.get_children():
		collect_physics(child,overlay)
func capture(viewport:SubViewport,camera:Camera2D,name:String) -> void:
	camera.force_update_scroll()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var error:=viewport.get_texture().get_image().save_png(output_dir.path_join(name))
	if error!=OK:
		printerr("Cannot save clarity evidence: ",name)
		quit(error)
		return
	rendered.append(name)
