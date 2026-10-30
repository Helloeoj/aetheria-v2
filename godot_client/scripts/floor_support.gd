extends RefCounted
## Read authored ground topology, not artwork colors or path connectivity.
const FLOOR_LAYERS := ["Ground", "Grass", "Paths", "PathsAndQuays", "NativeFloor"]
var layers: Array[TileMapLayer] = []
var room_artwork: Sprite2D
var authored_cells: Dictionary = {}
var authored_cell_size := 32.0
var authored_origin := Vector2.ZERO
var authored_area: Node2D

func configure(area: Node) -> void:
	layers.clear()
	authored_cells.clear()
	authored_area = area as Node2D
	room_artwork = area.get_node_or_null("TavernContent/ApprovedArtwork") as Sprite2D
	for node: Node in area.find_children("*", "TileMapLayer", true, false):
		if str(node.name) in FLOOR_LAYERS:
			layers.append(node as TileMapLayer)
	if layers.is_empty() and room_artwork == null and authored_area != null:
		var layout_path := "res://Assets/Maps/%s/layout.json" % area.scene_file_path.get_file().get_basename()
		if FileAccess.file_exists(layout_path):
			var layout: Variant = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
			if layout is Dictionary and layout.get("floor_cells") is Array:
				authored_cell_size = float(layout.get("gameplay_cell_pixels", 32.0))
				var anchor: Array = layout.get("grid_origin", [0, 0])
				if authored_cell_size <= 0.0 or anchor.size() != 2:
					return
				authored_origin = Vector2(float(anchor[0]), float(anchor[1]))
				for pair: Array in layout.floor_cells:
					if pair.size() == 2:
						authored_cells[Vector2i(int(pair[0]), int(pair[1]))] = true

func supports_body(global_point: Vector2, half_width: float = 12.0) -> bool:
	if not global_point.is_finite() or half_width <= 0.0:
		return false
	var body := Rect2(global_point - Vector2.ONE * half_width, Vector2.ONE * half_width * 2.0)
	if layers.is_empty():
		if not authored_cells.is_empty():
			return _authored_support(body)
		# This existing room uses one complete floor image and authored collision.
		# Other unrecognized areas fail closed until they declare a floor source.
		if not is_instance_valid(room_artwork) or not room_artwork.is_visible_in_tree():
			return false
		for corner: Vector2 in [body.position, Vector2(body.end.x, body.position.y), body.end, Vector2(body.position.x, body.end.y)]:
			if not room_artwork.get_rect().has_point(room_artwork.to_local(corner)):
				return false
		return true
	var floor_rects: Array[Rect2] = []
	var xs: Array[float] = [body.position.x, body.end.x]
	var ys: Array[float] = [body.position.y, body.end.y]
	for layer: TileMapLayer in layers:
		for rectangle: Rect2 in _rectangles(layer, body):
			floor_rects.append(rectangle)
			xs.append(rectangle.position.x)
			xs.append(rectangle.end.x)
			ys.append(rectangle.position.y)
			ys.append(rectangle.end.y)
	if floor_rects.is_empty():
		return false
	# Partition on every transformed cell boundary. Each resulting open region
	# has constant coverage: its midpoint proves the WHOLE region, including
	# interior holes that checking only the body's center/corners would miss.
	xs.sort()
	ys.sort()
	for x in range(1, xs.size()):
		if xs[x] - xs[x - 1] < 0.00001:
			continue
		for y in range(1, ys.size()):
			if ys[y] - ys[y - 1] < 0.00001:
				continue
			var probe := Vector2((xs[x] + xs[x - 1]) * 0.5, (ys[y] + ys[y - 1]) * 0.5)
			var supported := false
			for rectangle: Rect2 in floor_rects:
				if rectangle.has_point(probe):
					supported = true
					break
			if not supported:
				return false
	return true

func _authored_support(body: Rect2) -> bool:
	# The contract's floor cells are area-local world pixels, not source art.
	var first := (authored_area.to_local(body.position) - authored_origin) / authored_cell_size
	var last := (authored_area.to_local(body.end) - authored_origin) / authored_cell_size
	var low := Vector2i(first.min(last).floor())
	var high := Vector2i((first.max(last) - Vector2.ONE * 0.00001).floor())
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			if not authored_cells.has(Vector2i(x, y)):
				return false
	return true

func _rectangles(layer: TileMapLayer, body: Rect2) -> Array[Rect2]:
	var result: Array[Rect2] = []
	if not is_instance_valid(layer) or not layer.is_visible_in_tree() or layer.tile_set == null:
		return result
	# All current floor layers use axis-aligned square cells at authored scale.
	# Do not silently approximate a new rotated/skewed/isometric floor.
	if layer.tile_set.tile_shape != TileSet.TILE_SHAPE_SQUARE or not is_zero_approx(layer.global_transform.x.y) or not is_zero_approx(layer.global_transform.y.x):
		return result
	var first := layer.local_to_map(layer.to_local(body.position))
	var last := layer.local_to_map(layer.to_local(body.end))
	var low := Vector2i(mini(first.x, last.x), mini(first.y, last.y))
	var high := Vector2i(maxi(first.x, last.x), maxi(first.y, last.y))
	if (high.x - low.x + 1) * (high.y - low.y + 1) > 4096:
		return result
	var half_tile := Vector2(layer.tile_set.tile_size) * 0.5
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var cell := Vector2i(x, y)
			if layer.get_cell_source_id(cell) < 0:
				continue
			var local_center := layer.map_to_local(cell)
			var start := layer.to_global(local_center - half_tile)
			var finish := layer.to_global(local_center + half_tile)
			var clipped := Rect2(start, finish - start).abs().intersection(body)
			if clipped.has_area():
				result.append(clipped)
	return result
