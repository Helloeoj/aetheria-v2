class_name SpatialRelevance
extends RefCounted
## One index per region snapshot, reused by every recipient in that region.
const CELL := 16.0
var cells: Dictionary = {}

func update(actors: Array) -> void:
	cells.clear()
	for actor: Dictionary in actors:
		var cell := Vector2i(floori(float(actor.x) / CELL), floori(float(actor.y) / CELL))
		if not cells.has(cell):
			cells[cell] = []
		cells[cell].append(actor)

func nearby(position: Vector2, radius: float) -> Array:
	var result: Array = []
	var start := Vector2i(floori((position.x - radius) / CELL), floori((position.y - radius) / CELL))
	var finish := Vector2i(floori((position.x + radius) / CELL), floori((position.y + radius) / CELL))
	for x in range(start.x, finish.x + 1):
		for y in range(start.y, finish.y + 1):
			for actor: Dictionary in cells.get(Vector2i(x, y), []):
				if position.distance_squared_to(Vector2(float(actor.x), float(actor.y))) <= radius * radius:
					result.append(actor)
	return result
