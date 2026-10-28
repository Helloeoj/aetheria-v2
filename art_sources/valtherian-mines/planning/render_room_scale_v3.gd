extends SceneTree
var out_dir:String=get_script().resource_path.get_base_dir()+"/"
class TileRoom extends Node2D:
	var cells:=Vector2i(20,16)
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,Vector2(cells)*32.0),Color("9d805b"))
		for x in range(cells.x+1):
			draw_line(Vector2(x*32,0),Vector2(x*32,cells.y*32),Color("604f39"),1)
		for y in range(cells.y+1):
			draw_line(Vector2(0,y*32),Vector2(cells.x*32,y*32),Color("604f39"),1)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	root.position=Vector2i(-10000,-10000)
	root.size=Vector2i(320,240)
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(2560,2048)
	viewport.disable_3d=true
	viewport.world_2d=World2D.new()
	viewport.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var floor_check:=TileRoom.new()
	viewport.add_child(floor_check)
	var camera:=Camera2D.new()
	camera.position=Vector2(320,256)
	camera.zoom=Vector2(4,4)
	viewport.add_child(camera)
	camera.make_current()
	camera.force_update_scroll()
	var actor:=ActorSprite.new().configure(Vector2(32,32),Color.BLUE,"tile_room_scale_check_only")
	viewport.add_child(actor)
	actor.position=Vector2(336,368)
	actor.set_process(false)
	actor.set_skin("peasant")
	actor.animated_sprite.pause()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(out_dir+"combat-room-20x16-tile-scale-4x.png")
	floor_check.cells=Vector2i(18,14)
	floor_check.queue_redraw()
	viewport.size=Vector2i(2304,1792)
	camera.position=Vector2(288,224)
	camera.force_update_scroll()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(out_dir+"mining-room-18x14-tile-scale-4x.png")
	print("Structural scale previews only:32pxcells,unscaledoriginalcharacter,camera4x; combat640x512,mining576x448. No art, prop placement, collision or runtime scene installation certified.")
	viewport.queue_free()
	await process_frame
	quit(0)
