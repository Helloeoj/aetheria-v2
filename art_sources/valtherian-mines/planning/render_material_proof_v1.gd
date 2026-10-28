extends SceneTree
## Actual material-proof scene only. Actors are added here, never baked in art.
const CONTENT:="res://scenes/dev_tools/valtherian_material_proof_v1.tscn"
var output_dir:String=OS.get_user_data_dir().path_join("valtherian-material-proof-v1")
func _initialize() -> void:
	var arguments:=OS.get_cmdline_user_args()
	if arguments.size()>0:
		output_dir=arguments[0]
	_run.call_deferred()
func _run() -> void:
	root.position=Vector2i(-10000,-10000)
	root.size=Vector2i(320,240)
	DirAccess.make_dir_recursive_absolute(output_dir)
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(1536,1024)
	viewport.disable_3d=true
	viewport.world_2d=World2D.new()
	viewport.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var content:Node2D=(load(CONTENT) as PackedScene).instantiate()
	viewport.add_child(content)
	var actor:=ActorSprite.new().configure(Vector2(32,32),Color.BLUE,"native_material_proof_only")
	viewport.add_child(actor)
	actor.position=Vector2(240,176)
	actor.set_process(false)
	actor.set_skin("peasant")
	actor.animated_sprite.pause()
	var camera:=Camera2D.new()
	camera.position=Vector2(192,128)
	camera.zoom=Vector2(4,4)
	viewport.add_child(camera)
	camera.make_current()
	camera.force_update_scroll()
	await physics_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var result:=viewport.get_texture().get_image().save_png(output_dir.path_join("native-material-proof-v1-godot-4x.png"))
	if result!=OK:
		quit(result)
		return
	camera.zoom=Vector2.ONE
	viewport.size=Vector2i(384,256)
	camera.force_update_scroll()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	result=viewport.get_texture().get_image().save_png(output_dir.path_join("native-material-proof-v1-godot-1x.png"))
	print("Actual material-proof scene rendered with unchanged original character and canonical copper. Source1536x1024,world384x256,density0.25,nearest,zooms4xand1x. Not a final dungeon certificate. save_result=",result)
	viewport.queue_free()
	await process_frame
	quit(result)
