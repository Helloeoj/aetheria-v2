extends SceneTree
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Grid parity FAIL] ", label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var grid := HiddenGrid.new()
	grid.configure(Vector2.ZERO, Vector2(-10, -10), Vector2(10, 10))
	var path := grid.path(Vector2(0.5, 0.5), Vector2(1.01, 0.5), 0.1)
	check(path.is_empty(), "interaction ranges smaller than a cell cannot be silently enlarged")
	check(grid.path(Vector2(0.5, 0.5), Vector2(1.5, 0.5), 0.0, Callable(), func(_p: Vector2) -> bool: return false).is_empty(), "goal predicate cannot be bypassed by clicked cell")
	var player = load("res://scripts/player_state.gd").new("Parity")
	player.entity_id = "parity"
	player.x = 0.7
	player.y = 0.6
	var world = load("res://scripts/world_state.gd").new(player)
	world.register_player_actor(CombatActor.new().configure({"entity_id":"parity", "x":0.7, "y":0.6, "hp":10, "max_hp":10}))
	world.set_grid(grid)
	world.move_grid_toward("parity", Vector2(0.7, 0.6), 0.01, 4.0, 1.0)
	check(player.get_position().distance_to(Vector2(0.7, 0.6)) > 0.001, "nearby interaction still recovers off-grid save to a center")
	var remote = load("res://network/snapshot_interpolation.gd").new()
	if remote.get_method_list().filter(func(m: Dictionary) -> bool: return m.name == "push")[0].args.size() < 3:
		check(false, "remote interpolation consumes authoritative turn history")
	else:
		remote.push(1.0, Vector2(0.9, 0.5), {"epoch":1,"arrival":0,"trail":[]})
		remote.push(1.25, Vector2(1.5, 0.9), {"epoch":1,"arrival":1,"trail":[{"serial":1,"point":[1.5,0.5]}]})
		check(remote.sample(1.125).is_equal_approx(Vector2(1.4, 0.5)), "remote interpolation follows corner rather than diagonal shortcut")
		remote.push(1.3, Vector2(1.8, 0.9), {"epoch":2,"arrival":0,"trail":[]})
		check(remote.sample(1.26).is_equal_approx(Vector2(1.8, 0.9)), "small forced displacement resets interpolation")
	var prediction = load("res://network/movement_prediction.gd").new()
	prediction.use_grid(grid)
	prediction.reset(Vector2(0.5, 0.5))
	prediction.reconcile(Vector2(0.5, 0.5), -1, 0.0, true, {"epoch":1,"cell":[0,0],"target":[0.5,0.5],"active":false})
	prediction.advance(0.05, Vector2.RIGHT)
	prediction.reconcile(Vector2(1.0, 0.5), -1, 0.0, true, {"epoch":2,"cell":[1,0],"target":[1.0,0.5],"active":false})
	check(prediction.render_position().is_equal_approx(Vector2(1.0, 0.5)), "forced epoch clears stale local prediction even for short knockback")
	var region = load("res://network/authoritative_region.gd").new()
	region.configure("parity-wall", null)
	region.world.set_movement_bounds(Vector2(-10,-10), Vector2(10,10))
	var wall_grid := HiddenGrid.new()
	wall_grid.configure(Vector2.ZERO, Vector2(-10,-10), Vector2(10,10))
	wall_grid.point_clear = func(p: Vector2) -> bool: return not (p.x > 1.0 and p.x < 2.0 and p.y < 2.0)
	region.world.set_grid(wall_grid)
	region.world.terrain_collision_handler = func(_a: Vector2, _b: Vector2) -> Dictionary: return {"blocked":true}
	player.x = 0.5
	player.y = 0.5
	region.add_player("parity", player)
	check(region.submit("parity", {"type":"walk","x":2.5,"y":0.5}).ok, "server accepts path around obstacle despite blocked direct ray")
	for step in range(30):
		region.advance(0.1)
	check(player.get_position().is_equal_approx(Vector2(2.5,0.5)), "server click walk arrives around wall")
	region.world.move_grid_direction("parity", Vector2.RIGHT, 0.05, 4.0)
	region._add_drop("Bronze Ore", 1, player.get_position())
	check(not region.submit("parity", {"type":"pickup", "drop_id":region.drops.keys()[0]}).ok, "server rejects direct pickup during an unfinished step")
	var monster = load("res://scripts/monster_state.gd").new({}, 0.5, 0.5)
	monster.entity_id = "roamer"
	var roaming_world = load("res://scripts/world_state.gd").new()
	roaming_world.set_movement_bounds(Vector2(-10,-10), Vector2(10,10))
	roaming_world.set_grid(grid)
	roaming_world.register_monster_actor(monster, CombatActor.new().configure({"entity_id":"roamer","x":0.5,"y":0.5,"hp":10,"max_hp":10,"is_monster":true}))
	var roaming = load("res://scripts/monster_ai.gd").new({"monster":monster,"roam_radius":3,"spawn_x":0.5,"spawn_y":0.5}, roaming_world)
	roaming.random.seed = 17
	for step in range(10):
		roaming.tick(100 + step * 3)
		for frame in range(60):
			roaming.advance(1.0 / 60.0)
		if monster.get_position().distance_to(Vector2(0.5,0.5)) > 0.1:
			break
	check(monster.get_position().distance_to(Vector2(0.5,0.5)) > 0.1 and grid.is_center(monster.get_position()), "roaming uses shared smooth steps and finishes at center")
	check(monster.get_position().distance_to(Vector2(0.5,0.5)) <= 3.0, "roaming respects authored radius")
	roaming_world.move_grid_direction("roamer", Vector2.RIGHT, 0.1, 2.5)
	var epoch: int = roaming_world.grid_traveller("roamer").epoch
	var displaced := Vector2(monster.x, monster.y) + Vector2(0.2, 0.1)
	roaming_world.displace_actor("roamer", Vector2(0.2, 0.1))
	check(monster.get_position().is_equal_approx(displaced) and roaming_world.grid_traveller("roamer").epoch > epoch, "knockback preserves exact distance and invalidates stale step")
	check(not roaming_world.grid_traveller("roamer").active, "knockback cancels pending ordinary segment")
	grid.configure(Vector2.ZERO, Vector2(-40,-40), Vector2(40,40))
	roaming_world.set_movement_bounds(Vector2(-40,-40), Vector2(40,40))
	var enemy: CombatActor = roaming_world.combat.actors.roamer
	enemy.x = 25.5
	enemy.y = 0.5
	monster.move_to(25.5, 0.5)
	var attacker := CombatActor.new().configure({"entity_id":"hero","x":10.5,"y":0.5,"hp":10,"max_hp":10})
	attacker.current_target_id = "roamer"
	enemy.aggro_attacker_ids.append("hero")
	roaming_world.combat.add_actor(attacker)
	roaming_world.combat._process_monster_movement(roaming_world, 0.1)
	check(enemy.x < 25.5 and Vector2(enemy.x, enemy.y).distance_to(Vector2(25.5,0.5)) <= 0.25001, "monster forced outside leash returns home without teleporting or chasing farther")
	print("[Grid parity] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
