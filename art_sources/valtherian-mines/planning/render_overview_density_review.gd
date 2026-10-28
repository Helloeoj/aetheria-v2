extends SceneTree
## Rejection test only. Never install the overview with these transforms.
var output_dir:String=OS.get_user_data_dir().path_join("valtherian-density-review")
func _initialize() -> void:
	var arguments:=OS.get_cmdline_user_args()
	if arguments.size()>0:
		output_dir=arguments[0]
	_run.call_deferred()
func _run() -> void:
	root.position=Vector2i(-10000,-10000)
	root.size=Vector2i(320,240)
	var source_path:String=get_script().resource_path.get_base_dir().path_join("whole-map-candidate-v3.png")
	if not FileAccess.file_exists(source_path):
		source_path=get_script().resource_path.get_base_dir().get_base_dir().path_join("unapproved/whole-map-v3.png")
	var source:=Image.load_from_file(source_path)
	if source==null:
		printerr("Missing preserved v3 source")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(1280,960)
	viewport.disable_3d=true
	viewport.world_2d=World2D.new()
	viewport.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var artwork:=Sprite2D.new()
	artwork.centered=false
	artwork.texture=ImageTexture.create_from_image(source)
	artwork.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	artwork.scale=Vector2(6144.0/source.get_width(),3328.0/source.get_height())
	viewport.add_child(artwork)
	var actor:=ActorSprite.new().configure(Vector2(32,32),Color.BLUE,"density_rejection_preview_only")
	viewport.add_child(actor)
	actor.set_process(false)
	actor.set_skin("peasant")
	actor.animated_sprite.pause()
	actor.position=Vector2(140,160)*artwork.scale
	var camera:=Camera2D.new()
	camera.position=actor.position-Vector2(0,24)
	camera.zoom=Vector2(4,4)
	viewport.add_child(camera)
	camera.make_current()
	camera.force_update_scroll()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var error:=viewport.get_texture().get_image().save_png(output_dir.path_join("overview-stretched-to-planned-world-rejected-4x.png"))
	if error!=OK:
		printerr("Failed saving density test: ",error)
		quit(1)
		return
	var scale_data:=CharacterSpriteLibrary.get_skin("peasant")
	var review:={"test":"rejection of overview-as-runtime texture; not production scene certification",
		"source_size":source.get_size(),"planned_world_size":Vector2i(6144,3328),
		"rejected_world_pixels_per_art_pixel":artwork.scale,"camera_zoom":4,
		"screen_pixels_per_overview_pixel":artwork.scale*4,
		"player_source_size":scale_data.get("size"),"player_display_height":scale_data.get("display_height"),
		"actual_player_visual_scale":actor.animated_sprite.scale,
		"nearest_filtering":true,"viewport_size":viewport.size,
		"render_file":"overview-stretched-to-planned-world-rejected-4x.png",
		"limitations":"No final native terrain, placements, physics or gameplay installed or certified."}
	var file:=FileAccess.open(output_dir.path_join("overview-density-review.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(review,"  ")+"\n")
	file.close()
	print(JSON.stringify(review))
	viewport.queue_free()
	await process_frame
	quit(0)
