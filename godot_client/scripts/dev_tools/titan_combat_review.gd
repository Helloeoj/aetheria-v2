extends SceneTree
## Real-map integration exercise. Never saves the isolated development character.
var output := ""
func _initialize() -> void: run.call_deferred()
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
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
	game.player.current_target = boss.entity_id
	boss.aggro_attacker_ids.append(target.entity_id)
	target.hp = 1000000
	target.max_hp = 1000000
	game.combat.random.seed = 719
	var camera: Camera2D = scene.get_node("MapCamera")
	camera.set_process(false)
	camera.set_physics_process(false)
	camera.position_smoothing_enabled = false
	camera.position = game.actor_sprites[boss.entity_id].global_position + Vector2(0, -85)
	camera.zoom = Vector2(4, 4)
	DirAccess.make_dir_recursive_absolute(output)
	var captures := {}
	for tick in 70:
		game._handle_combat_events(game.world.tick())
		for frame in 36:
			var events: Array[Dictionary] = game.combat.process_realtime(game.world, 1.0/60.0)
			game._handle_combat_events(events)
			game._sync_actor_states()
			game.titan_visuals._process(0.0)
			var packet: Dictionary = game.combat.titan_encounters.snapshot(game.combat)
			for action: Dictionary in packet.titan_actions:
				var age := float(action.age)
				var key := String(action.kind)
				var desired := 1.8 if key in ["slam", "eruption"] else 1.25
				if not captures.has(key) and age >= desired:
					await process_frame
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(output.path_join(key+"-4x.png"))
					captures[key] = true
					print("[Titan live] captured ", key, " tiles=", action.cells.size())
			if not packet.titan_projectiles.is_empty() and not captures.has("homing"):
				# Move after launch so this shot must turn in the actual map simulation.
				game.world.move_actor_continuous(target.entity_id, Vector2(2.0, 0))
				for i in 8: game._handle_combat_events(game.combat.process_realtime(game.world, 1.0/60.0))
				game._sync_actor_states()
				game.titan_visuals._process(0.0)
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join("homing-4x.png"))
				captures.homing = true
		if captures.size() == 5: break
	var rooted := Vector2(boss.x, boss.y) == anchor
	print("[Titan live] ", captures.keys(), " rooted=", rooted)
	quit(0 if captures.size() == 5 and rooted else 1)
