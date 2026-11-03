extends SceneTree
const RIG := preload("res://scripts/dev_tools/golem_titan_casting_skeleton.gd")
var output := ""
var failures: Array[String]=[]
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	if output.is_empty() or DisplayServer.get_name()=="headless":
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
	root.position=Vector2i(-10000,-10000)
	root.size=Vector2i(320,240)
	var view := SubViewport.new()
	view.size=Vector2i(336,288)
	view.transparent_bg=true
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(view)
	var rig := RIG.new()
	rig.position=Vector2(40,16)
	view.add_child(rig)
	var neutral: Image
	var fixed := [Rect2i(80,153,96,89),Rect2i(60,217,56,26),Rect2i(143,217,56,26),Rect2i(25,217,33,26),Rect2i(203,217,32,26)]
	for i in 121:
		rig.sample_at_seconds(float(i)*0.02)
		await process_frame
		await RenderingServer.frame_post_draw
		var image := view.get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		if i==0: neutral=image.duplicate()
		for rectangle: Rect2i in fixed:
			var shifted := Rect2i(rectangle.position+Vector2i(40,16),rectangle.size)
			if image.get_region(shifted).get_data()!=neutral.get_region(shifted).get_data():
				failures.append("Anchored lower-body pixels changed at frame"+str(i))
		var filename := "frames/%03d.png" % i if i<120 else "endpoint.png"
		image.save_png(output.path_join(filename))
		if i==120 and image.get_data()!=neutral.get_data(): failures.append("Endpoint differs from neutral")
	var report := {"frames":120,"frame_ms":20,"native_canvas":[336,288],"foot_anchor":[168,256],"source_canvas_offset":[40,16],"source":RIG.SOURCE,"bones":rig.bones.size(),"failures":failures,"scope":"candidate casting motion; original source pixels and rigid whole fists; legs/feet/bindings fixed"}
	FileAccess.open(output.path_join("bake-report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("[Magic bake]120 frames; ",rig.bones.size()," bones; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
