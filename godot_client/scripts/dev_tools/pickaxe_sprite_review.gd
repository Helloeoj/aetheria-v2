extends SceneTree
## Real registered ActorSprite equipment, not manually pasted tool artwork.
const MANIFEST := "res://Assets/Equipment/Pickaxes/Held/manifest.json"
const VECTORS := [Vector2.DOWN,Vector2(1,1),Vector2.RIGHT,Vector2(1,-1),Vector2.UP,Vector2(-1,-1),Vector2.LEFT,Vector2(-1,1)]
var output := ""
var viewport: SubViewport
var camera: Camera2D
var failures: Array[String] = []
var records: Array[Dictionary] = []
var actors: Array[ActorSprite] = []

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output=argument.trim_prefix("--output=")
	if output.is_empty():
		printerr("Supply --output=<external-review-folder>")
		quit(1)
		return
	_run.call_deferred()

func _run() -> void:
	create_timer(120).timeout.connect(func() -> void: quit(1))
	DirAccess.make_dir_recursive_absolute(output)
	root.position=Vector2i(-10000,-10000)
	root.size=Vector2i(1600,1000)
	viewport=SubViewport.new()
	viewport.size=Vector2i(2048,1792)
	viewport.world_2d=World2D.new()
	viewport.disable_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	var background:=CanvasLayer.new()
	background.layer=-100
	viewport.add_child(background)
	var ground:=ColorRect.new()
	ground.size=Vector2(4096,4096)
	ground.color=Color("252b32")
	background.add_child(ground)
	camera=Camera2D.new()
	camera.zoom=Vector2(4,4)
	viewport.add_child(camera)
	camera.make_current()
	var labels:=CanvasLayer.new()
	labels.layer=10
	viewport.add_child(labels)
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	for row in range(manifest.entries.size()):
		var entry: Dictionary=manifest.entries[row]
		for column in range(manifest.directions.size()):
			var direction: String=manifest.directions[column]
			var actor:=ActorSprite.new().configure(Vector2(32,32),Color.BLUE,"registered_pickaxe_review")
			viewport.add_child(actor)
			actor.position=Vector2((column-3.5)*64,(row-3)*64+20)
			actor.set_skin("peasant")
			actor.set_process(false)
			actor.face_direction(VECTORS[column])
			actor.animated_sprite.pause()
			actor.set_equipment({"weapon":{"name":entry.name}})
			actors.append(actor)
			var held:=actor.attachment_rig.get_equipped_visual("weapon") as EquipmentVisual2D
			if held==null:
				failures.append(str(entry.name)+" missing registered attachment")
				continue
			var art:=held.get_node("Artwork") as Sprite2D
			var grip: Vector2=held.grip_positions[direction]
			var socket:=actor.attachment_rig.get_socket("right_hand")
			var drift:=art.to_global(grip).distance_to(socket.global_position)
			var density:=art.global_transform.x.length()
			var imported:=art.texture.get_image()
			if imported.is_compressed():
				imported.decompress()
			imported.convert(Image.FORMAT_RGBA8)
			var source:=Image.new()
			source.load_png_from_buffer(FileAccess.get_file_as_bytes(art.texture.resource_path))
			source.convert(Image.FORMAT_RGBA8)
			var mismatch:=imported.get_size()!=source.get_size()
			if not mismatch:
				for y in range(source.get_height()):
					for x in range(source.get_width()):
						var a:=source.get_pixel(x,y)
						var b:=imported.get_pixel(x,y)
						if a.a!=b.a or (a.a>0 and a!=b):
							mismatch=true
			if mismatch or drift>0.0001 or absf(density-0.75)>0.0001:
				failures.append(str(entry.id)+"/"+direction+" import/grip/density")
			records.append({"material":entry.id,"direction":direction,"grip_drift":drift,"world_pixels_per_texel":density,"source_import_match":not mismatch,"behind_body":socket.show_behind_parent})
			var label:=Label.new()
			label.text=entry.name+"\n"+direction
			label.position=Vector2(column*256+12,row*256+6)
			label.add_theme_font_size_override("font_size",18)
			labels.add_child(label)
	await capture("held-pickaxes-all-views-4x.png")
	labels.hide()
	viewport.size=Vector2i(2048,320)
	for i in range(actors.size()):
		actors[i].visible=i>=8 and i<16
	camera.position=Vector2(0,actors[8].position.y-20)
	await capture("held-iron-eight-directions-4x.png")
	for i in range(actors.size()):
		actors[i].visible=i%8==0
		if actors[i].visible:
			actors[i].position=Vector2((i/8-3)*70,0)
	camera.position=Vector2(0,-20)
	await capture("held-materials-south-4x.png")
	for actor: ActorSprite in actors:
		actor.visible=actor==actors[8]
	actors[8].position=Vector2.ZERO
	viewport.size=Vector2i(640,512)
	camera.position=Vector2(-8,-20)
	await capture("held-iron-closeup-4x.png")
	# Release the full contact sheet before opening the existing F7 interface.
	for actor: ActorSprite in actors:
		actor.free()
	actors.clear()
	viewport.queue_free()
	await process_frame
	# Instantiate the existing F7 interface and select the registered tool.
	var preview: Variant=load("res://scripts/sprite_preview.gd").new()
	root.add_child(preview)
	await process_frame
	preview._select_skin(preview.skin_ids.find("peasant"))
	var choice: int=preview.equipment_names.find("Iron Pickaxe")
	preview.equipment_picker.select(choice)
	preview._change_equipment(choice)
	preview._change_review_zoom(2)
	preview._set_review_paused(true)
	preview.socket_check.button_pressed=true
	preview.actor.set_socket_debug(true)
	preview.show_preview()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("actual-f7-iron-pickaxe-4x.png"))
	var report:={"passed":failures.is_empty(),"failures":failures,"camera_zoom":4,"registered_material_facing_combinations":records.size(),"records":records,"existing_f7_choice":choice,"actual_skeleton":"CharacterAttachmentRig/right_hand","artwork_approval":false,"mining_animation_added":false}
	var file:=FileAccess.open(output.path_join("pickaxe-review.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print(JSON.stringify({"passed":failures.is_empty(),"registered_views":records.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func capture(filename: String) -> void:
	camera.force_update_scroll()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var error:=viewport.get_texture().get_image().save_png(output.path_join(filename))
	if error!=OK:
		failures.append("Cannot save "+filename)
