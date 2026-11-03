extends SceneTree
## Focused real-game spawn check. Does not save a character or change maps.
var failures: Array[String] = []
var checks := 0
var output := ""
var game: Node

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("[Titan spawn FAIL] ",label)

func _run() -> void:
	create_timer(120).timeout.connect(func() -> void: quit(1))
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output=argument.trim_prefix("--output=")
	var skin := CharacterSpriteLibrary.get_skin("golem_titan")
	var dimensions: Array=skin.get("size",[0,0])
	check(float(dimensions[0])==256.0 and float(dimensions[1])==256.0 and float(skin.get("display_height",0))==256.0,"approved Titan has native giant scale")
	if not failures.is_empty():
		_finish()
		return
	var frames := CharacterSpriteLibrary.get_frames("golem_titan")
	for direction: String in CharacterSpriteLibrary.DIRECTIONS:
		check(frames.get_frame_count("idle_"+direction)==48,"approved skeletal idle on "+direction)
		check(frames.get_frame_count("attack_"+direction)==18,"approved slam on "+direction)
	var duration := 0.0
	for frame in 18:
		duration += frames.get_frame_duration("attack_south",frame)/frames.get_animation_speed("attack_south")
	check(is_equal_approx(duration,2.31),"approved nonuniform slam timing preserved")
	root.size=Vector2i(1600,1600)
	root.position=Vector2i(-10000,-10000)
	root.get_node("SceneTravel").clear_online_binding()
	var scene := (load("res://scenes/GolemKingdom.tscn") as PackedScene).instantiate()
	# Fresh isolated development player starts on the previously reviewed courtyard.
	scene.get_node("SpawnPoints/EastCave").position=Vector2(2032,2160)
	root.add_child(scene)
	current_scene=scene
	game=scene.get_node("Combat")
	game.set_physics_process(false)
	for frame in 180:
		await physics_frame
		if game.grid_adapter != null and game.grid_adapter.completed:
			break
	check(game.grid_adoption_report().get("enabled",false),"actual Golem Kingdom grid ready")
	game.spawn_menu.visible=true
	game.spawn_menu.input_text="1029"
	var enter := InputEventKey.new()
	enter.keycode=KEY_ENTER
	var before: int=game.world.monsters.size()
	game.spawn_menu.on_key_press(enter)
	check(game.world.monsters.size()==before+1,"existing F5 ID1029 spawns Titan")
	game.spawn_menu.hide()
	if game.world.monsters.size() != before+1:
		_finish()
		return
	var monster: MonsterState=game.world.monsters[-1]
	var baseline := MonsterState.new(game._active_monster_database()[1029],monster.x,monster.y)
	check(monster.get_combat_stats()==baseline.get_combat_stats(),"all original combat stats retained")
	var actor: ActorSprite=game.actor_sprites[monster.entity_id]
	actor.set_process(false)
	actor.animated_sprite.pause()
	check(actor.skin_id=="golem_titan" and actor.animated_sprite.scale==Vector2.ONE,"actual spawned actor uses full native scale")
	check(actor.animated_sprite.offset==Vector2(0,-112),"approved foot anchor retained")
	check(actor.animated_sprite.sprite_frames.get_frame_texture("idle_south",0).get_size()==Vector2(256,256),"spawn uses new256px art")
	check(game.world.cell_grid.clear_point(monster.get_position()),"spawn retains actual terrain/body clearance")
	var player_visual: ActorSprite=game.actor_sprites[game.player.entity_id]
	check(actor.global_position.y<=player_visual.global_position.y-64.0,"giant spawns two tiles in front without covering player")
	check(not game.world.cell_grid.path(game.player.get_position(),monster.get_position()).is_empty(),"spawn reachable from player")
	actor.play_attack(Vector2.UP)
	check(is_equal_approx(actor.get("_attack_duration"),2.31),"actual actor uses full authored slam duration")
	actor.animated_sprite.pause()
	if not output.is_empty():
		check(DisplayServer.get_name()!="headless","capture requires actual graphical Godot")
		DirAccess.make_dir_recursive_absolute(output)
		var camera: Camera2D=scene.get_node("MapCamera")
		camera.set_process(false)
		camera.set_physics_process(false)
		camera.position_smoothing_enabled=false
		camera.position=actor.global_position+Vector2(-64,-80)
		for zoom: float in [1.5,4.0]:
			camera.zoom=Vector2.ONE*zoom
			for pose: String in ["idle_south","attack_north"]:
				actor.animated_sprite.animation=pose
				actor.animated_sprite.frame=9 if pose.begins_with("attack") else 0
				await _capture(camera,"spawn-%s-%sx.png" % [pose,str(zoom)])
		var report={"checks":checks,"failures":failures,"template_id":1029,"native_size":[256,256],"world_scale":1,
			"monster_world_xy":[actor.global_position.x,actor.global_position.y],"player_world_xy":[game.actor_sprites[game.player.entity_id].global_position.x,game.actor_sprites[game.player.entity_id].global_position.y],
			"stats_retained":monster.get_combat_stats()==baseline.get_combat_stats(),"scope":"actual F5 spawn on unchanged Golem Kingdom, isolated test player; no production map placements or collider changes"}
		FileAccess.open(output.path_join("spawn-review.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	_finish()

func _capture(camera: Camera2D,filename: String) -> void:
	camera.force_update_scroll()
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(filename))==OK,"saved actual game "+filename)

func _finish() -> void:
	print("[Titan spawn] ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
