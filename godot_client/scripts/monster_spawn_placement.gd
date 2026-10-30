extends RefCounted
## Nearby means actual tile distance, connected by legal player-sized steps.
static func nearby(grid: HiddenGrid, player: Vector2, radius: float = 3.0, allowed: Callable = Callable(), occupied: Array = []) -> Vector2:
	var unavailable := Vector2(INF, INF)
	if grid == null or not player.is_finite() or not is_finite(radius) or radius <= 0.0 or radius > 3.0:
		return unavailable
	grid.clear_cache()
	var recovered: Variant = grid.recovery_cell(player)
	if recovered == null or not _allowed(grid, recovered, allowed):
		return unavailable
	var queue: Array[Vector2i] = [recovered]
	var visited := {recovered: true}
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		var point := grid.center(cell)
		if cell != recovered and point.distance_to(player) <= radius + 0.00001 and _unoccupied(point, player, occupied):
			return point
		for direction: Vector2i in HiddenGrid.DIRECTIONS:
			var next := cell + direction
			if visited.has(next) or grid.center(next).distance_to(player) > radius + 0.00001:
				continue
			if not _allowed(grid, next, allowed) or not grid.connected(cell, next):
				continue
			if direction.x != 0 and direction.y != 0 and (not _allowed(grid, cell + Vector2i(direction.x, 0), allowed) or not _allowed(grid, cell + Vector2i(0, direction.y), allowed)):
				continue
			visited[next] = true
			queue.append(next)
	return unavailable

static func _allowed(grid: HiddenGrid, cell: Vector2i, allowed: Callable) -> bool:
	var point := grid.center(cell)
	return grid.clear_point(point) and (not allowed.is_valid() or bool(allowed.call(point)))

static func _unoccupied(point: Vector2, player: Vector2, occupied: Array) -> bool:
	for other: Vector2 in occupied + [player]:
		if absf(point.x - other.x) < 0.75 and absf(point.y - other.y) < 0.75:
			return false
	return true
