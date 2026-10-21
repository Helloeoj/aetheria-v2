extends Node2D
## Routes use the same authored floor cells as the content collision.
const DATA_PATH := "res://Assets/Maps/GolemCatacombs/Floor01/layout.json"
const CELL_WORLD := 24.0
const CLEARANCE_CELLS := 1
var _grid: AStarGrid2D
var _floor_cells := {}

func _build_grid() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(0, 0, int(data.width_cells), int(data.height_cells))
	_grid.cell_size = Vector2.ONE * CELL_WORLD
	_grid.offset = Vector2.ONE * CELL_WORLD * 0.5
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.update()
	_grid.fill_solid_region(_grid.region)
	for values: Array in data.walkable_cells:
		_floor_cells[Vector2i(int(values[0]), int(values[1]))] = true
	for cell: Vector2i in _floor_cells:
		var clear := true
		# Keep a full world-cell margin, conservatively exceeding the actor's
		# 12-pixel half-width. Diagonals also require both adjacent cells clear.
		for y in range(-CLEARANCE_CELLS, CLEARANCE_CELLS + 1):
			for x in range(-CLEARANCE_CELLS, CLEARANCE_CELLS + 1):
				if not _floor_cells.has(cell + Vector2i(x, y)):
					clear = false
		if clear:
			_grid.set_point_solid(cell, false)

func interaction_path(from_global: Vector2, to_global_point: Vector2) -> PackedVector2Array:
	if _grid == null:
		_build_grid()
	var start := Vector2i((to_local(from_global) / CELL_WORLD).floor())
	var finish := Vector2i((to_local(to_global_point) / CELL_WORLD).floor())
	if not _grid.is_in_boundsv(start) or not _grid.is_in_boundsv(finish):
		return PackedVector2Array()
	if _grid.is_point_solid(finish):
		finish = _recover_margin_point(to_global_point, finish, true)
		if finish.x < 0:
			return PackedVector2Array()
	if _grid.is_point_solid(start):
		start = _recover_margin_point(from_global, start, false)
		if start.x < 0:
			return PackedVector2Array()
	var path := _grid.get_point_path(start, finish)
	if path.is_empty():
		return path
	for index in range(path.size()):
		path[index] = to_global(path[index])
	path.append(to_global_point)
	return path

func _recover_margin_point(global_point: Vector2, cell: Vector2i, is_finish: bool) -> Vector2i:
	# A physically clear endpoint may lie inside the extra route margin.
	# Connect its exact position and the grid only through a real body sweep.
	var unavailable := Vector2i(-1, -1)
	if not _floor_cells.has(cell):
		return unavailable
	var game := get_node_or_null("Combat")
	if game == null:
		return unavailable
	var player: Variant = game.get("player")
	var sprites: Dictionary = game.get("actor_sprites")
	var actor := sprites.get(player.entity_id) as CharacterBody2D
	if actor == null:
		return unavailable
	var body_collision := actor.get_node("BodyCollision") as CollisionShape2D
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = body_collision.shape
	query.transform = Transform2D(actor.global_rotation, global_point)
	query.collision_mask = actor.collision_mask
	query.exclude = [actor.get_rid()]
	if not get_world_2d().direct_space_state.intersect_shape(query).is_empty():
		return unavailable
	var nearest := unavailable
	var nearest_distance := INF
	for y in range(-3, 4):
		for x in range(-3, 4):
			var candidate := cell + Vector2i(x, y)
			if not _grid.is_in_boundsv(candidate) or _grid.is_point_solid(candidate):
				continue
			var grid_point := to_global(_grid.get_point_position(candidate))
			var distance := global_point.distance_squared_to(grid_point)
			if distance >= nearest_distance:
				continue
			var body_transform := actor.global_transform
			body_transform.origin = grid_point if is_finish else global_point
			var target := global_point if is_finish else grid_point
			if actor.test_move(body_transform, target - body_transform.origin):
				continue
			nearest = candidate
			nearest_distance = distance
	return nearest
