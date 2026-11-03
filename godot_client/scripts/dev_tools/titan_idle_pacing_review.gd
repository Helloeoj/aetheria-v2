extends SceneTree
## Real-map integration exercise. Never saves the isolated development character.
var output := ""
var ranged := false
var stop_attacking := false
var benchmark_only := false
func _initialize() -> void: run.call_deferred()
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg == "--ranged": ranged = true
		if arg == "--stop-attacking": stop_attacking = true
		if arg == "--benchmark-only": benchmark_only = true
	create_timer(90).timeout.connect(func() -> void: quit(1))
	root.size = Vector2i(1800, 1200)
	root.position = Vector2i(-10000, -10000)
	root.get_node("SceneTravel").clear_online_binding()
	var scene := (load("res://scenes/GolemKingdom.tscn") as PackedScene).instantiate()
	scene.get_node("SpawnPoints/EastCave").position = Vector2(2032,2160)
	root.add_child(scene)
	current_scene = scene
	var game: Node = scene.get_node("Combat")
	game.set_physics_process(false)
	for i in 180:
		await physics_frame
		if game.grid_adapter != null and game.grid_adapter.completed: break
	if not game.spawn_monster_by_id(1029):
		printerr("[Titan live] cannot spawn")
		quit(1)
		return
	var monster: MonsterState = game.world.monsters[-1]
	var boss: CombatActor = game.combat.actors[monster.entity_id]
	var target: CombatActor = game.combat.actors[game.player.entity_id]
	var anchor := Vector2(boss.x, boss.y)
	var actor: ActorSprite = game.actor_sprites[boss.entity_id]
	var camera: Camera2D = scene.get_node("MapCamera")
	camera.set_process(false)
	camera.set_physics_process(false)
	camera.position_smoothing_enabled = false
	camera.position = actor.global_position + Vector2(0,-85)
	camera.zoom = Vector2(4,4)
	Engine.max_fps = 60
	var visual: AnimatedSprite2D = actor.animated_sprite
	var hashes: Array[String] = []
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/golem_titan_approved_animations.json"))
	for path: String in data.animations.idle.directions.south: hashes.append(FileAccess.get_sha256(path))
	await create_timer(2.6).timeout
	var previous := hashes[visual.frame]
	var start := Time.get_ticks_msec()
	var changed := start
	var longest := 0
	var max_delta := 0
	var last := start
	while Time.get_ticks_msec()-start < 2800:
		await process_frame
		var now := Time.get_ticks_msec()
		max_delta = maxi(max_delta,now-last)
		last=now
		var current := hashes[visual.frame]
		if current != previous:
			longest = maxi(longest,now-changed)
			changed=now
			previous=current
	print("[Titan idle] real-playback longest identical pose=",longest,"ms; longest render interval=",max_delta,"ms")
	DirAccess.make_dir_recursive_absolute(output)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("idle-4x.png"))
	var failed := longest>100
	if not benchmark_only:
		# The approved body returns to neutral; resuming a hidden mid-cycle idle must not pop.
		var action := {"attack_id":"idle_handoff","kind":"haymaker","caster_id":boss.entity_id,"target_id":target.entity_id,"cells":[],"age":0.2}
		var previous_view: Node=game.online_view
		game.online_view=Node.new()
		game.titan_visuals.apply_snapshot({"titan_actions":[action],"titan_projectiles":[]})
		game.titan_visuals._process(0)
		visual.set_frame_and_progress(20,0.5)
		game.titan_visuals.apply_snapshot({"titan_actions":[],"titan_projectiles":[]})
		game.titan_visuals._process(0)
		print("[Titan idle] after attack frame=",visual.frame," progress=",visual.frame_progress)
		failed = failed or visual.frame!=0 or visual.frame_progress!=0.0
		game.online_view.free()
		game.online_view=previous_view
	var rooted := Vector2(boss.x,boss.y)==anchor
	print("[Titan idle] rooted=",rooted," failed=",failed)
	quit(0 if not failed and rooted else 1)
