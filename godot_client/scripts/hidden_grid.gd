class_name HiddenGrid
extends RefCounted
## One cell is one existing simulation unit (32 world pixels).
## Origin is explicit, independent of camera, map extents and artwork cells.
const DIRECTIONS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(1, -1)]
const SEARCH_LIMIT := 8192
var origin := Vector2.ZERO
var minimum := Vector2.ZERO
var maximum := Vector2(299, 299)
var point_clear: Callable
var sweep_clear: Callable
var _cells := {}
var _edges := {}

func configure(anchor: Vector2, low: Vector2, high: Vector2) -> void:
	origin = anchor
	minimum = low
	maximum = high
	clear_cache()

func clear_cache() -> void:
	_cells.clear()
	_edges.clear()

func cell_at(point: Vector2) -> Vector2i:
	return Vector2i((point - origin).floor())

func center(cell: Vector2i) -> Vector2:
	return origin + Vector2(cell) + Vector2.ONE * 0.5

func is_center(point: Vector2) -> bool:
	return point.is_equal_approx(center(cell_at(point)))

func contains(point: Vector2) -> bool:
	return point.is_finite() and point.x >= minimum.x and point.y >= minimum.y \
		and point.x <= maximum.x and point.y <= maximum.y

func clear_point(point: Vector2) -> bool:
	return contains(point) and (not point_clear.is_valid() or bool(point_clear.call(point)))

func clear_segment(start: Vector2, finish: Vector2) -> bool:
	return clear_point(start) and clear_point(finish) \
		and (not sweep_clear.is_valid() or bool(sweep_clear.call(start, finish)))

func walkable(cell: Vector2i) -> bool:
	if not _cells.has(cell):
		_cells[cell] = clear_point(center(cell))
	return _cells[cell]

func connected(start: Vector2i, finish: Vector2i) -> bool:
	var offset := finish - start
	if offset == Vector2i.ZERO or absi(offset.x) > 1 or absi(offset.y) > 1:
		return false
	var key := Vector4i(start.x, start.y, finish.x, finish.y)
	if _edges.has(key):
		return _edges[key]
	var valid := walkable(start) and walkable(finish)
	if valid and offset.x != 0 and offset.y != 0:
		valid = connected(start, start + Vector2i(offset.x, 0)) \
			and connected(start, start + Vector2i(0, offset.y)) \
			and connected(start + Vector2i(offset.x, 0), finish) \
			and connected(start + Vector2i(0, offset.y), finish)
	valid = valid and clear_segment(center(start), center(finish))
	_edges[key] = valid
	return valid

## A legacy/off-grid point only joins a center through a real body sweep.
func recovery_cell(point: Vector2) -> Variant:
	if not clear_point(point):
		return null
	var base := cell_at(point)
	var best: Variant = null
	var distance := INF
	for y in range(-2, 3):
		for x in range(-2, 3):
			var cell := base + Vector2i(x, y)
			var candidate := center(cell)
			var next_distance := candidate.distance_squared_to(point)
			if next_distance < distance and walkable(cell) and clear_segment(point, candidate):
				best = cell
				distance = next_distance
	return best

## Goal radius allows authored off-grid interaction approach points to stay put.
func path(start: Vector2, goal: Vector2, goal_radius: float = 0.0, allowed: Callable = Callable(), goal_valid: Callable = Callable()) -> PackedVector2Array:
	if not start.is_finite() or not goal.is_finite() or not contains(goal):
		return PackedVector2Array()
	var recovered: Variant = recovery_cell(start)
	if recovered == null:
		return PackedVector2Array()
	var first: Vector2i = recovered
	var goals := {}
	var radius := goal_radius if goal_radius > 0.0 else 0.72
	var extent := mini(int(ceil(radius)), 32)
	var base := cell_at(goal)
	for y in range(-extent, extent + 1):
		for x in range(-extent, extent + 1):
			var cell := base + Vector2i(x, y)
			if goal_radius <= 0.0 and walkable(base) and cell != base:
				continue
			if goal_valid.is_valid() and not bool(goal_valid.call(center(cell))):
				continue
			if center(cell).distance_to(goal) <= radius and walkable(cell):
				goals[cell] = true
	if goals.is_empty():
		return PackedVector2Array()
	var frontier: Array = []
	_push(frontier, [0.0, first])
	var costs := {first: 0.0}
	var previous := {}
	var visited := {}
	while not frontier.is_empty() and visited.size() < SEARCH_LIMIT:
		var cell: Vector2i = _pop(frontier)[1]
		if visited.has(cell):
			continue
		if goals.has(cell):
			var result := PackedVector2Array([center(cell)])
			while previous.has(cell):
				cell = previous[cell]
				result.insert(0, center(cell))
			return result
		visited[cell] = true
		for direction: Vector2i in DIRECTIONS:
			var next := cell + direction
			if allowed.is_valid() and not bool(allowed.call(center(next))):
				continue
			if visited.has(next) or not connected(cell, next):
				continue
			var cost: float = costs[cell] + Vector2(direction).length()
			if cost >= float(costs.get(next, INF)):
				continue
			costs[next] = cost
			previous[next] = cell
			var estimate := maxf(0.0, center(next).distance_to(goal) - radius)
			_push(frontier, [cost + estimate, next])
	return PackedVector2Array()

static func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) / 2
		if float(heap[parent][0]) <= float(item[0]):
			break
		heap[index] = heap[parent]
		index = parent
	heap[index] = item

static func _pop(heap: Array) -> Array:
	var result: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return result
	var index := 0
	while index * 2 + 1 < heap.size():
		var child := index * 2 + 1
		if child + 1 < heap.size() and float(heap[child + 1][0]) < float(heap[child][0]):
			child += 1
		if float(last[0]) <= float(heap[child][0]):
			break
		heap[index] = heap[child]
		index = child
	heap[index] = last
	return result
