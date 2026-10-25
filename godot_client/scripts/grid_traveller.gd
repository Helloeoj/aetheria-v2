class_name GridTraveller
extends RefCounted
## Shared real-time step state. Input changes never redirect a committed edge.
var position := Vector2.ZERO
var cell := Vector2i.ZERO
var target := Vector2.ZERO
var active := false
var route := PackedVector2Array()
var goal := Vector2(INF, INF)
var retry_delay := 0.0

func reset(point: Vector2, grid: HiddenGrid) -> void:
	position = point
	cell = grid.cell_at(point)
	target = point
	active = false
	route.clear()
	goal = Vector2(INF, INF)
	retry_delay = 0.0

func cancel_route() -> void:
	route.clear()
	goal = Vector2(INF, INF)

func set_route(points: PackedVector2Array, destination: Vector2) -> void:
	route = points.duplicate()
	goal = destination
	retry_delay = 0.25

func advance(delta: float, speed: float, direction: Vector2, grid: HiddenGrid, move: Callable = Callable()) -> void:
	if not is_finite(delta) or delta <= 0.0 or speed <= 0.0 or not direction.is_finite():
		return
	var budget := delta * speed
	var steps := 0
	while budget > 0.000001 and steps < 256:
		steps += 1
		if not active:
			while not route.is_empty() and position.distance_to(route[0]) < 0.00001:
				route.remove_at(0)
			if route.is_empty() and direction.is_zero_approx():
				break
			var recovery: Variant = grid.recovery_cell(position)
			if recovery == null:
				cancel_route()
				break
			var center := grid.center(recovery)
			if not position.is_equal_approx(center):
				target = center
			elif not route.is_empty():
				target = route[0]
				var next := grid.cell_at(target)
				if not grid.connected(grid.cell_at(position), next):
					cancel_route()
					break
			else:
				var step := Vector2i(roundi(direction.normalized().x), roundi(direction.normalized().y))
				var next := grid.cell_at(position) + step
				if not grid.connected(grid.cell_at(position), next):
					break
				target = grid.center(next)
			active = true
		if not grid.clear_segment(position, target):
			active = false
			cancel_route()
			grid.clear_cache()
			break
		var distance := position.distance_to(target)
		var travel := minf(budget, distance)
		var wanted := position.move_toward(target, travel)
		if move.is_valid():
			var actual: Vector2 = move.call(wanted - position)
			if not actual.is_equal_approx(wanted):
				reset(actual, grid)
				grid.clear_cache()
				break
		position = wanted
		budget -= travel
		if travel >= distance - 0.000001:
			position = target
			cell = grid.cell_at(target)
			active = false

func snapshot() -> Dictionary:
	return {"cell": [cell.x, cell.y], "target": [target.x, target.y], "active": active}
