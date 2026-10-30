extends SceneTree
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Spawn selection FAIL] ", label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var path := "res://scripts/monster_spawn_placement.gd"
	check(FileAccess.file_exists(path), "Shared nearby spawn selector exists")
	if not FileAccess.file_exists(path):
		_finish()
		return
	var placement = load(path)
	var grid := HiddenGrid.new()
	grid.configure(Vector2.ZERO, Vector2(-10, -10), Vector2(10, 10))
	var player := Vector2(0.5, 0.5)
	var occupied: Array[Vector2] = [player]
	for index in range(8):
		var point: Vector2 = placement.nearby(grid, player, 3.0, Callable(), occupied)
		check(point.is_finite() and point.distance_to(player) <= 3.00001 and grid.is_center(point), "Available nearby tile selected %d" % index)
		for previous: Vector2 in occupied:
			check(absf(previous.x - point.x) >= 0.75 or absf(previous.y - point.y) >= 0.75, "Repeated selection avoids occupied body")
		occupied.append(point)
	# The only valid destination is near in space but separated by a wall.
	grid.point_clear = func(p: Vector2) -> bool: return not is_equal_approx(p.x, 1.5)
	var isolated: Vector2 = placement.nearby(grid, player, 3.0, Callable(), [player, Vector2(-0.5, 0.5), Vector2(0.5, -0.5), Vector2(0.5, 1.5), Vector2(-0.5, -0.5), Vector2(-0.5, 1.5), Vector2(0.5, -1.5), Vector2(0.5, 2.5), Vector2(-1.5, 0.5)])
	check(not isolated.is_finite() or isolated.x < 1.5, "Cannot spawn through nearby wall")
	grid.point_clear = Callable()
	var island_floor := func(p: Vector2) -> bool: return p == player or p == Vector2(1.5, 1.5)
	check(not placement.nearby(grid, player, 3.0, island_floor, [player]).is_finite(), "Diagonal cannot cross unsupported cardinal floor")
	var edge_floor := func(p: Vector2) -> bool: return is_equal_approx(p.y, 0.5) and p.x >= 0.5
	var edge: Vector2 = placement.nearby(grid, player, 3.0, edge_floor, [player, Vector2(1.5, 0.5), Vector2(2.5, 0.5)])
	check(edge == Vector2(3.5, 0.5), "Exact three-tile boundary is permitted")
	check(not placement.nearby(grid, player, 2.99, edge_floor, [player, Vector2(1.5, 0.5), Vector2(2.5, 0.5)]).is_finite(), "Radius is measured in actual distance, not rounded cell count")
	var negative: Vector2 = placement.nearby(grid, Vector2(-2.8, -3.6), 3.0, Callable(), [Vector2(-2.8, -3.6)])
	check(negative.is_finite() and negative.distance_to(Vector2(-2.8, -3.6)) <= 3.00001, "Signed off-center player position works")
	grid.point_clear = func(_p: Vector2) -> bool: return false
	check(not placement.nearby(grid, player, 3.0).is_finite(), "Fully blocked search returns no destination")
	check(not placement.nearby(null, player, 3.0).is_finite(), "Missing grid fails closed")
	check(not placement.nearby(grid, Vector2(INF, 0), 3.0).is_finite(), "Nonfinite player position fails closed")
	var world = load("res://scripts/world_state.gd").new()
	world.monster_spawn_validator = func(_point: Vector2) -> bool: return false
	var monster := MonsterState.new({}, 1.5, 1.5)
	var actor := CombatActor.new().configure({"entity_id": "bad-spawn", "x": 1.5, "y": 1.5, "hp": 10, "max_hp": 10, "is_monster": true})
	check(not world.register_monster_actor(monster, actor) and world.monsters.is_empty() and world.combat.actors.is_empty(), "World registration rejects invalid spawn before mutation")
	world.monster_spawn_validator = func(_point: Vector2) -> bool: return true
	check(world.register_monster_actor(monster, actor) and world.monsters.size() == 1, "World registration accepts validated spawn")
	_finish()

func _finish() -> void:
	print("[Spawn selection] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
