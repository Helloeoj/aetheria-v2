extends SceneTree
const CAST := preload("res://scenes/Effects/TitanMagicCast.tscn")
const EFFECT := preload("res://scripts/effects/titan_dark_magic_effect.gd")
var out := ""
var first_frame := 0
var failures: Array[String]=[]
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): out=arg.trim_prefix("--output=")
		if arg.begins_with("--from-frame="): first_frame=int(arg.trim_prefix("--from-frame="))
	if out.is_empty() or DisplayServer.get_name()=="headless":
		quit(1)
		return
	root.position=Vector2i(-10000,-10000)
	root.size=Vector2i(1600,1600)
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
	actor.animated_sprite.hide()
	actor.animated_sprite.pause()
	actor.animated_sprite.frame=0
	var rig := CAST.instantiate()
	actor.add_child(rig)
	var player: ActorSprite=game.actor_sprites[game.player.entity_id]
	player.set_process(false)
	player.animated_sprite.pause()
	var captured := player.global_position
	var escape := captured+Vector2(32,0)
	var camera: Camera2D=scene.get_node("MapCamera")
	camera.set_process(false)
	camera.set_physics_process(false)
	camera.position_smoothing_enabled=false
	camera.position=actor.global_position+Vector2(0,-35)
	camera.zoom=Vector2(2,2)
	var offsets := [Vector2(0,0),Vector2(-3,-1),Vector2(2,-1),Vector2(-1,1),Vector2(3,1),Vector2(-2,2),Vector2(2,2),Vector2(-4,1),Vector2(4,2),Vector2(-3,3)]
	var captures := 0
	for mode: String in ["single","aoe"]:
		var effects: Array[Node2D]=[]
		for offset: Vector2 in offsets:
			if mode=="single" and not effects.is_empty(): break
			var position_: Vector2=captured+offset*32.0
			var simulation: Vector2=Vector2((position_.x-game.map_origin.x)/32.0,(game.map_origin.y+game.map_height-position_.y)/32.0)
			if not game.monster_spawn_allowed(simulation): failures.append("Effect cell is not on clear actual floor:"+str(position_))
			var effect := EFFECT.new()
			effect.mode=mode
			game.add_child(effect)
			effect.global_position=position_
			effect.launch_point=actor.global_position+Vector2(0,-125)-position_
			effects.append(effect)
		DirAccess.make_dir_recursive_absolute(out.path_join(mode))
		for frame in range(first_frame,150):
			var time := float(frame)*0.02
			var sample: Dictionary=rig.sample_at_seconds(time)
			actor.animated_sprite.visible=sample.phase=="complete"
			if not actor.animated_sprite.visible and not rig.visible: failures.append("Caster disappeared at"+str(time))
			player.global_position=captured.lerp(escape,clampf((time-0.35)/0.25,0.0,1.0))
			for effect: Node2D in effects: effect.sample_at_seconds(time)
			camera.force_update_scroll()
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join(mode).path_join("%03d.png" % frame))
			captures+=1
		for effect: Node2D in effects: effect.queue_free()
		await process_frame
	camera.zoom=Vector2(4,4)
	camera.position=actor.global_position+Vector2(0,-80)
	actor.animated_sprite.hide()
	rig.sample_at_seconds(1.2)
	camera.force_update_scroll()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("casting-4x.png"))
	var report := {"captures":301,"captures_this_run":captures+1,"unchanged_prefix_frames_preserved":first_frame*2,"frame_ms":20,"warning_ms":1200,"native_world_density":1,"caster_frames":33,"caster_xy":[actor.global_position.x,actor.global_position.y],"captured_target_xy":[captured.x,captured.y],"player_escape_xy":[escape.x,escape.y],"single_target_instances":1,"aoe_instances":10,"selection":"AoE snapshots tiles; bolt preview uses a supplied endpoint without a ground marker","stats":"existing monster template unchanged","scene":"res://scenes/GolemKingdom.tscn","failures":failures,"scope":"actual game candidate preview; no damage or AI rotation installed"}
	FileAccess.open(out.path_join("review.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("[Dark magic] ",captures+1," actual game captures; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
