extends SceneTree
## Real-map integration exercise. Never saves the isolated development character.
var output := ""
var ranged := false
var stop_attacking := false
func _initialize() -> void: run.call_deferred()
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg == "--ranged": ranged = true
		if arg == "--stop-attacking": stop_attacking = true
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
	if ranged:
		var chosen := false
		for x in range(-8, 9):
			for y in range(-8, 9):
				var point := anchor + Vector2(x,y)
				if point.distance_to(anchor)<6 or point.distance_to(anchor)>9: continue
				if not game.world.cell_grid.clear_point(point) or not game.world.has_line_of_sight(anchor,point): continue
				game.world.move_actor_continuous(target.entity_id, point-Vector2(target.x,target.y))
				if Vector2(target.x,target.y).distance_to(anchor)>5:
					chosen = true
					break
			if chosen: break
		if not chosen:
			printerr("[Titan live] no clear ranged position")
			quit(1)
			return
	if ranged:
		game._sync_actor_states()
		root.size = Vector2i(2400, 1400)
		camera.position.x = (game.actor_sprites[boss.entity_id].global_position.x + game.actor_sprites[target.entity_id].global_position.x) * 0.5
	var last_start := -1
	var largest_gap := 0
	var failed := false
	var captures := {}
	for tick in 70:
		if stop_attacking and tick == 1: game._clear_target()
		var tick_events: Array[Dictionary] = game.world.tick()
		for event: Dictionary in tick_events:
			if event.type == "titan_attack_started" and event.kind != "haymaker":
				if last_start >= 0: largest_gap = maxi(largest_gap, tick-last_start)
				last_start = tick
				print("[Titan live] tick=",tick," kind=",event.kind," distance=",Vector2(target.x,target.y).distance_to(anchor))
			if ranged and event.type == "titan_attack_started" and event.kind == "haymaker": failed = true
		game._handle_combat_events(tick_events)
		for frame in 36:
			var events: Array[Dictionary] = game.combat.process_realtime(game.world, 1.0/60.0)
			game._handle_combat_events(events)
			game._sync_actor_states()
			game.titan_visuals._process(0.0)
			var packet: Dictionary = game.combat.titan_encounters.snapshot(game.combat)
			for action: Dictionary in packet.titan_actions:
				var age := float(action.age)
				var key := String(action.kind)
				if key in ["slam", "eruption"]:
					if age < 1.2 and not action.cells.is_empty(): failed = true
					if not captures.has(key+"-warning") and age>=1.2 and age<1.3 and not action.cells.is_empty():
						await process_frame
						await RenderingServer.frame_post_draw
						root.get_texture().get_image().save_png(output.path_join(key+"-warning-4x.png"))
						captures[key+"-warning"] = true
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
		if captures.size() >= (6 if ranged else 7) and tick>=20: break
	var rooted := Vector2(boss.x, boss.y) == anchor
	print("[Titan live] ", captures.keys(), " rooted=", rooted, " largest_main_gap=",largest_gap," failed=",failed," retained_after_stop=",not stop_attacking or boss.current_target_id==target.entity_id)
	quit(0 if captures.size() >= (6 if ranged else 7) and rooted and not failed and (not ranged or largest_gap<=4) and (not stop_attacking or boss.current_target_id==target.entity_id) else 1)
