extends SceneTree
## GPU-only native-density composition evidence. No gameplay/art resources are saved.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var output := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	if not output.is_absolute_path():
		printerr("Supply --output=<absolute PNG path>")
		quit(1)
		return
	root.position = Vector2i(-10000,-10000)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1254,1254)
	viewport.disable_3d = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var content := (load("res://scenes/TavernContent.tscn") as PackedScene).instantiate()
	viewport.add_child(content)
	var camera := Camera2D.new()
	viewport.add_child(camera)
	camera.position = Vector2(627,627) * 0.75
	camera.zoom = Vector2.ONE / 0.75
	camera.make_current()
	for index in range(5):
		await process_frame
	camera.force_update_scroll()
	await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image().save_png(output)
	print("[Tavern art] Saved native-density scene composition: ", output)
	viewport.queue_free()
	await process_frame
	quit(0 if result == OK else 1)
