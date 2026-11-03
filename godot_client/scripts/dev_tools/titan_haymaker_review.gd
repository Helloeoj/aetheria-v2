extends SceneTree
const PRESENTATION := preload("res://scenes/Effects/TitanHaymaker.tscn")
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
	root.size=Vector2i(1000,1000)
	root.get_node("SceneTravel").clear_online_binding()
	var scene := (load("res://scenes/GolemKingdom.tscn") as PackedScene).instantiate()
	scene.get_node("SpawnPoints/EastCave").position=Vector2(2032,2160)
	root.add_child(scene)
	current_scene=scene
	var game: Node=scene.get_node("Combat")
	game.set_physics_process(false)
	for i in 180:
		await physics_frame
		if game.grid_adapter!=null and game.grid_adapter.completed: break
	if not game.spawn_monster_by_id(1029):
		printerr("No actual Titan spawn")
		quit(1)
		return
	var monster: MonsterState=game.world.monsters[-1]
	var actor: ActorSprite=game.actor_sprites[monster.entity_id]
	actor.set_process(false)
	actor.animated_sprite.pause()
	actor.animated_sprite.frame=0
	actor.animated_sprite.hide()
	var animation := PRESENTATION.instantiate()
	actor.add_child(animation)
	if animation.visible: failures.append("Presentation must start hidden")
	var player: ActorSprite=game.actor_sprites[game.player.entity_id]
	player.set_process(false)
	player.animated_sprite.pause()
	# A normal diagonal grid step: (64,0) toward (32,32), at1/8 progress.
	# Keep existing depth sorting; do not hide the reference player behind a leg.
	player.global_position=actor.global_position+Vector2(60,4)
	var player_texture: Texture2D=player.animated_sprite.sprite_frames.get_frame_texture(player.animated_sprite.animation,player.animated_sprite.frame)
	var player_used := player_texture.get_image().get_used_rect()
	var target_origin: Vector2=player.animated_sprite.offset
	if player.animated_sprite.centered: target_origin-=player_texture.get_size()*0.5
	var target_top := player.animated_sprite.to_global(target_origin+Vector2(player_used.position))
	var target_bottom := player.animated_sprite.to_global(target_origin+Vector2(player_used.end))
	var camera: Camera2D=scene.get_node("MapCamera")
	camera.set_process(false)
	camera.set_physics_process(false)
	camera.position_smoothing_enabled=false
	camera.position=actor.global_position+Vector2(0,-60)
	camera.zoom=Vector2(2,2)
	var elapsed := 0.0
	var captures := 0
	for frame in animation.frames.size():
		var milliseconds := float(animation.timeline.durations_ms[frame])
		var sample: Dictionary=animation.sample_at_seconds((elapsed+milliseconds*0.5)/1000.0)
		if sample.frame!=frame or not animation.visible: failures.append("Frame clock mismatch:"+str(frame))
		camera.force_update_scroll()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("frames/%03d.png" % frame))
		captures+=1
		elapsed+=milliseconds
	var end: Dictionary=animation.sample_at_seconds(float(animation.timeline.duration_ms)/1000.0)
	if end.phase!="complete" or animation.visible: failures.append("Presentation must finish hidden")
	actor.animated_sprite.show()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("endpoint.png"))
	actor.animated_sprite.hide()
	var contact_seconds := float(animation.timeline.contact_ms)/1000.0
	var previous_frame := maxi(0,int(animation.timeline.contact_frame)-1)
	animation.sample_at_seconds(contact_seconds-float(animation.timeline.durations_ms[previous_frame])/2000.0)
	root.size=Vector2i(1400,1400)
	camera.zoom=Vector2(4,4)
	camera.position=actor.global_position+Vector2(0,-80)
	camera.force_update_scroll()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("windup-4x.png"))
	animation.sample_at_seconds(contact_seconds)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("contact-4x.png"))
	var contact_native := Vector2(float(animation.timeline.contact_point[0]),float(animation.timeline.contact_point[1]))
	var anchor := Vector2(float(animation.timeline.foot_anchor[0]),float(animation.timeline.foot_anchor[1]))
	var fist_world := actor.global_position+contact_native-anchor
	var body_top := target_top.y+(target_bottom.y-target_top.y)*0.40
	var body_contact := fist_world.y>=body_top and fist_world.y<=target_bottom.y and fist_world.x>=target_top.x and fist_world.x<=target_bottom.x
	var contact_image: Image=animation.visual.texture.get_image()
	if contact_image.get_pixelv(Vector2i(contact_native)).a<0.5: failures.append("Authored contact point has no sprite pixels")
	if not body_contact: failures.append("Fist contact is outside actual player body height")
	var report := {"scene":"res://scenes/GolemKingdom.tscn","actor_id":1029,"captures":captures+3,"native_frames":animation.frames.size(),"duration_ms":elapsed,"contact_ms":animation.timeline.contact_ms,"world_pixels_per_source_pixel":1,"player_present":true,"player_relative_foot":[60,4],"player_reference":"interpolated grid step, no depth override","player_sprite_world_top":[target_top.x,target_top.y],"player_sprite_world_bottom":[target_bottom.x,target_bottom.y],"contact_zoom":4,"fist_contact_world":[fist_world.x,fist_world.y],"player_body_top_y":body_top,"contact_below_head":body_contact,"failures":failures,"scope":"physical punch presentation; no combat damage, AI or map changes"}
	FileAccess.open(output.path_join("review.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("[Titan haymaker] ",captures+3," actual game captures; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
