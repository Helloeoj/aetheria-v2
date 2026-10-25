extends SceneTree
## These checks catch boundary rounding, early occupancy and mid-edge turning.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Hidden grid FAIL] ", label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var grid_script = load("res://scripts/hidden_grid.gd")
	var travel_script = load("res://scripts/grid_traveller.gd")
	if grid_script == null or travel_script == null:
		printerr("[Hidden grid FAIL] Shared grid and travel implementation missing")
		quit(1)
		return
	var grid = grid_script.new()
	grid.configure(Vector2.ZERO, Vector2(-10, -10), Vector2(10, 10))
	check(grid.cell_at(Vector2(-0.01, 1.0)) == Vector2i(-1, 1), "floor boundaries include negative cells")
	check(grid.center(Vector2i(-1, 1)) == Vector2(-0.5, 1.5), "cell centers preserve negative coordinates")
	var edge_click: PackedVector2Array = grid.path(Vector2(1.5, 0.5), Vector2(0.99, 0.5))
	check(not edge_click.is_empty() and edge_click[-1] == Vector2(0.5, 0.5), "click near boundary selects clicked cell rather than adjacent nearer actor")
	var visible_route: PackedVector2Array = grid.path(Vector2(0.5, 0.5), Vector2(2.5, 0.5), 3.0, Callable(),
		func(p: Vector2) -> bool: return p.x >= 2.0)
	check(not visible_route.is_empty() and visible_route[-1].x >= 2.0, "chase finds a valid attack position even when already inside nominal range")
	var traveller = travel_script.new()
	traveller.reset(Vector2(0.5, 0.5), grid)
	traveller.advance(0.1, 4.0, Vector2.RIGHT, grid)
	check(traveller.position.is_equal_approx(Vector2(0.9, 0.5)), "world-space speed preserved")
	check(traveller.cell == Vector2i(0, 0), "occupancy stays at departure before arrival")
	traveller.advance(0.15, 4.0, Vector2.UP, grid)
	check(traveller.position.is_equal_approx(Vector2(1.5, 0.5)), "turn waits for center")
	check(traveller.cell == Vector2i(1, 0), "occupancy changes on arrival")
	traveller.advance(0.05, 4.0, Vector2.ZERO, grid)
	check(traveller.position == Vector2(1.5, 0.5), "release at center stays stopped")
	traveller.reset(Vector2(0.5, 0.5), grid)
	traveller.advance(0.1, 4.0, Vector2.ONE, grid)
	traveller.advance(0.1, 4.0, Vector2.ZERO, grid)
	check(traveller.cell == Vector2i.ZERO, "diagonal not completed at cardinal duration")
	traveller.advance(0.2, 4.0, Vector2.ZERO, grid)
	check(traveller.position.is_equal_approx(Vector2(1.5, 1.5)), "release finishes only committed diagonal")
	grid.point_clear = func(p: Vector2) -> bool: return not (p.x > 0.99 and p.x < 2.0 and p.y < 2.0)
	grid.clear_cache()
	check(not grid.connected(Vector2i.ZERO, Vector2i.ONE), "diagonal cannot cut blocked cardinal neighbor")
	var path: PackedVector2Array = grid.path(Vector2(0.5, 0.5), Vector2(2.5, 0.5))
	check(path.size() > 3, "path routes around wall instead of rejecting obscured destination")
	grid.sweep_clear = func(_a: Vector2, _b: Vector2) -> bool: return false
	grid.clear_cache()
	check(grid.path(Vector2(0.5, 0.5), Vector2(2.5, 0.5)).is_empty(), "clear endpoints cannot bypass blocked sweep")
	grid.sweep_clear = Callable()
	grid.point_clear = Callable()
	grid.clear_cache()
	traveller.reset(Vector2(0.7, 0.6), grid)
	traveller.advance(0.01, 4.0, Vector2.RIGHT, grid)
	check(traveller.position.distance_to(Vector2(0.7, 0.6)) <= 0.04001, "off-grid legacy placement recovers without teleport")
	var player = load("res://scripts/player_state.gd").new("Grid unit")
	player.entity_id = "grid-unit"
	player.x = 0.5
	player.y = 0.5
	var world = load("res://scripts/world_state.gd").new(player)
	world.register_player_actor(CombatActor.new().configure({"entity_id": player.entity_id, "x": 0.5, "y": 0.5, "hp": 10, "max_hp": 10}))
	if not world.has_method("set_grid"):
		check(false, "WorldState owns shared step movement")
	else:
		world.call("set_grid", grid)
		world.call("move_grid_direction", player.entity_id, Vector2.RIGHT, 0.1, 4.0)
		check(player.get_position().is_equal_approx(Vector2(0.9, 0.5)), "shared movement synchronizes durable player coordinates")
		world.call("move_grid_direction", player.entity_id, Vector2.ZERO, 0.2, 4.0)
		check(player.get_position().is_equal_approx(Vector2(1.5, 0.5)), "WorldState finishes released step without starting another")
		world.move_actor_continuous(player.entity_id, Vector2(0.2, 0.1))
		world.call("move_grid_direction", player.entity_id, Vector2.UP, 0.01, 4.0)
		check(player.get_position().distance_to(Vector2(1.7, 0.6)) <= 0.04001, "forced displacement invalidates old travel state")
	var region = load("res://network/authoritative_region.gd").new()
	region.configure("grid-unit", null)
	region.world.set_movement_bounds(Vector2(-10, -10), Vector2(10, 10))
	region.world.call("set_grid", grid)
	player.x = 0.5
	player.y = 0.5
	region.add_player("grid-unit", player)
	region.submit("grid-unit", {"type": "move", "direction": [1.0, 0.0]})
	region.advance(0.1)
	region.submit("grid-unit", {"type": "move", "direction": [0.0, 0.0]})
	region.advance(0.3)
	check(player.get_position().is_equal_approx(Vector2(1.5, 0.5)), "server release finishes committed step")
	var snapshot: Dictionary = region.snapshot("grid-unit")
	check(snapshot.has("grid") and snapshot.actors[0].has("grid_travel"), "server publishes grid and travel state")
	var prediction = load("res://network/movement_prediction.gd").new()
	if not prediction.has_method("use_grid"):
		check(false, "prediction supports shared grid steps")
	else:
		prediction.call("use_grid", grid)
		prediction.reset(Vector2(0.5, 0.5))
		prediction.record_input(1, Vector2.RIGHT)
		prediction.advance(0.1, Vector2.RIGHT)
		prediction.record_input(2, Vector2.ZERO)
		prediction.advance(0.15, Vector2.ZERO)
		check(prediction.position.is_equal_approx(Vector2(1.5, 0.5)), "predicted release completes the same step as server")
	print("[Hidden grid] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
