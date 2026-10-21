extends Node2D
## Small room-specific grid routes interactions around the hearth and furniture.
const DATA_PATH := "res://Assets/Maps/Tavern/layout.json"
const SOURCE_SCALE := 0.75
const CELL := 16.0
var _grid: AStarGrid2D

func _build_grid() -> void:
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(0, 0, 79, 79)
	_grid.cell_size = Vector2.ONE * CELL * SOURCE_SCALE
	_grid.offset = Vector2.ONE * CELL * SOURCE_SCALE * 0.5
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	for y in range(79):
		for x in range(79):
			var point := (Vector2(x,y) + Vector2.ONE * 0.5) * CELL
			for values: Array in data.obstacles:
				# The player's collision is 24 world pixels = 32 source pixels wide.
				var rect := Rect2(float(values[0]),float(values[1]),float(values[2]),float(values[3])).grow(18)
				if rect.has_point(point):
					_grid.set_point_solid(Vector2i(x,y))
					break

func interaction_path(from_global: Vector2, to_global_point: Vector2) -> PackedVector2Array:
	if _grid == null:
		_build_grid()
	var start := Vector2i((to_local(from_global) / (CELL * SOURCE_SCALE)).floor())
	var finish := Vector2i((to_local(to_global_point) / (CELL * SOURCE_SCALE)).floor())
	if not _grid.is_in_boundsv(start) or not _grid.is_in_boundsv(finish) or _grid.is_point_solid(start) or _grid.is_point_solid(finish):
		return PackedVector2Array()
	var path := _grid.get_point_path(start,finish)
	if path.is_empty():
		return path
	for index in range(path.size()):
		path[index] = to_global(path[index])
	path.append(to_global_point)
	return path
