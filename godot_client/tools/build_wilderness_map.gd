extends SceneTree
## Builds editable wilderness terrain and whole-object scene tiles from the approved sections.
## Import changed images first, then run with:
## godot --headless --path . --script res://tools/build_wilderness_map.gd

const MANIFEST_PATH := "res://Assets/MapTiles/Wilderness/wilderness_manifest.json"
const CONTENT_PATH := "res://scenes/WildernessMapContent.tscn"
const OBJECT_DIRECTORY := "res://scenes/WildernessObjectsGenerated"
const TILESET_DIRECTORY := "res://Assets/Tilesets"
const OBJECT_TILESET_PATH := TILESET_DIRECTORY + "/WildernessMapObjects.tres"
const WORLD_COLLISION_LAYER := 1
const OBJECT_GRID := Vector2i(32, 32)

var _scene_root: Node2D
var _terrain_cell_count := 0
var _object_count := 0
var _collision_polygon_count := 0
var _collision_circle_count := 0
var _object_layers: Array[TileMapLayer] = []
var _occupied_object_cells: Array[Dictionary] = []
var _object_layer_kinds: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var succeeded := _build()
	if _scene_root != null:
		_scene_root.free()
	quit(0 if succeeded else 1)


func _build() -> bool:
	var manifest_file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if manifest_file == null:
		return _error("Cannot open %s: %s" % [MANIFEST_PATH, error_string(FileAccess.get_open_error())])
	var parser := JSON.new()
	var parse_error := parser.parse(manifest_file.get_as_text())
	manifest_file.close()
	if parse_error != OK:
		return _error("Manifest JSON line %d: %s" % [parser.get_error_line(), parser.get_error_message()])
	if not parser.data is Dictionary:
		return _error("Manifest root must be an object.")
	var manifest: Dictionary = parser.data
	if not _is_pair(manifest.get("map_size")):
		return _error("Manifest map_size must be [width, height].")
	if manifest.has("map_origin") and not _is_pair(manifest["map_origin"]):
		return _error("Manifest map_origin must be [x, y].")
	if not manifest.get("terrain", []) is Array or not manifest.get("objects", []) is Array:
		return _error("Manifest terrain and objects must be arrays.")
	for directory: String in [OBJECT_DIRECTORY, TILESET_DIRECTORY]:
		var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		if directory_error != OK:
			return _error("Cannot create %s: %s" % [directory, error_string(directory_error)])

	_scene_root = Node2D.new()
	_scene_root.name = "WildernessMapContent"
	_scene_root.y_sort_enabled = true
	_scene_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_scene_root.set_meta("map_size", _vector_pair(manifest["map_size"]))
	_scene_root.set_meta("map_origin", _vector_pair(manifest.get("map_origin", [0, 0])))
	_scene_root.set_meta("section_size", int(manifest.get("section_size", 1536)))
	_scene_root.set_meta("manifest", MANIFEST_PATH)

	var terrain_entries: Array = manifest.get("terrain", [])
	for index in range(terrain_entries.size()):
		if not terrain_entries[index] is Dictionary:
			return _error("Terrain entry %d must be an object." % index)
		if not _build_terrain(terrain_entries[index], index):
			return false

	var object_entries: Array = manifest.get("objects", [])
	if not _build_objects(object_entries):
		return false
	if not _save_scene(_scene_root, CONTENT_PATH):
		return false
	print("[WildernessMap] Saved %s: %d terrain cells, %d object scenes in %d object layers, %d collision polygons, %d collision circles." % [
		CONTENT_PATH, _terrain_cell_count, _object_count, _object_layers.size(), _collision_polygon_count, _collision_circle_count
	])
	return true


func _build_terrain(entry: Dictionary, index: int) -> bool:
	var layer_name := _safe_name(String(entry.get("name", "Terrain%d" % index)))
	var texture_path := String(entry.get("texture", ""))
	var texture := _load_texture(texture_path)
	if texture == null:
		return false
	var tile_size := int(entry.get("tile_size", 32))
	if tile_size <= 0:
		return _error("%s tile_size must be positive." % layer_name)
	if texture.get_width() % tile_size != 0 or texture.get_height() % tile_size != 0:
		return _error("%s texture size must be divisible by tile_size %d." % [layer_name, tile_size])
	if not entry.get("cells", []) is Array or not entry.get("physics_cells", []) is Array:
		return _error("%s cells and physics_cells must be arrays." % layer_name)

	var tileset := TileSet.new()
	tileset.resource_name = "Wilderness " + layer_name
	tileset.tile_size = Vector2i(tile_size, tile_size)
	var physics_entries: Array = entry.get("physics_cells", [])
	if not physics_entries.is_empty() or bool(entry.get("brush_collidable", false)):
		tileset.add_physics_layer()
		tileset.set_physics_layer_collision_layer(0, WORLD_COLLISION_LAYER)
		tileset.set_physics_layer_collision_mask(0, 0)
	var atlas := TileSetAtlasSource.new()
	atlas.resource_name = layer_name
	atlas.texture = texture
	atlas.texture_region_size = Vector2i(tile_size, tile_size)
	tileset.add_source(atlas, 0)
	var atlas_bounds := Vector2i(texture.get_width() / tile_size, texture.get_height() / tile_size)
	var cells: Array = entry.get("cells", [])
	var occupied_cells: Dictionary = {}
	for cell_value: Variant in cells:
		if not cell_value is Array or cell_value.size() != 4:
			return _error("%s cells must contain [cell_x, cell_y, atlas_x, atlas_y]." % layer_name)
		var atlas_cell := Vector2i(int(cell_value[2]), int(cell_value[3]))
		if not _ensure_atlas_tile(atlas, atlas_cell, atlas_bounds, layer_name):
			return false
		var map_cell := Vector2i(int(cell_value[0]), int(cell_value[1]))
		if occupied_cells.has(map_cell):
			return _error("%s has more than one terrain tile in cell %s." % [layer_name, map_cell])
		occupied_cells[map_cell] = true
	for physics_value: Variant in physics_entries:
		if not physics_value is Dictionary or not _is_pair(physics_value.get("atlas")) or not physics_value.get("polygons", []) is Array:
			return _error("%s physics_cells entries require atlas:[x,y] and polygons:[...]." % layer_name)
		var atlas_cell := Vector2i(_vector_pair(physics_value["atlas"]))
		if not _ensure_atlas_tile(atlas, atlas_cell, atlas_bounds, layer_name):
			return false
		var tile_data := atlas.get_tile_data(atlas_cell, 0)
		var polygons: Array = physics_value.get("polygons", [])
		tile_data.set_collision_polygons_count(0, polygons.size())
		for polygon_index in range(polygons.size()):
			var polygon := _polygon_points(polygons[polygon_index], "%s atlas %s" % [layer_name, atlas_cell])
			if polygon.is_empty():
				return false
			tile_data.set_collision_polygon_points(0, polygon_index, polygon)
			_collision_polygon_count += 1

	var tileset_path := "%s/Wilderness%02d_%s.tres" % [TILESET_DIRECTORY, index, layer_name]
	if entry.has("brush_texture"):
		var brush_texture := _load_texture(String(entry["brush_texture"]))
		if brush_texture == null:
			return false
		var brushes := TileSetAtlasSource.new()
		brushes.resource_name = "Reusable " + layer_name + " brushes"
		brushes.texture = brush_texture
		brushes.texture_region_size = Vector2i(tile_size, tile_size)
		tileset.add_source(brushes, 1)
		var brush_columns := int(brush_texture.get_width() / tile_size)
		var brush_rows := int(brush_texture.get_height() / tile_size)
		var brush_count := int(entry.get("brush_count", 0))
		if brush_columns < 1 or brush_rows < 1 or brush_count > brush_columns * brush_rows:
			return _error("%s reusable brushes do not fit their texture." % layer_name)
		for brush_id in brush_count:
			var brush_cell := Vector2i(brush_id % brush_columns, brush_id / brush_columns)
			brushes.create_tile(brush_cell)
			if bool(entry.get("brush_collidable", false)):
				var data := brushes.get_tile_data(brush_cell, 0)
				data.set_collision_polygons_count(0, 1)
				var half_tile := float(tile_size) * 0.5
				data.set_collision_polygon_points(0, 0, PackedVector2Array([Vector2(-half_tile, -half_tile), Vector2(half_tile, -half_tile), Vector2(half_tile, half_tile), Vector2(-half_tile, half_tile)]))
	if not _save_resource(tileset, tileset_path):
		return false
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = load(tileset_path) as TileSet
	layer.z_index = int(entry.get("z_index", -10))
	layer.y_sort_enabled = false
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.navigation_enabled = false
	_scene_root.add_child(layer)
	layer.owner = _scene_root
	for cell_value: Array in cells:
		layer.set_cell(Vector2i(int(cell_value[0]), int(cell_value[1])), 0, Vector2i(int(cell_value[2]), int(cell_value[3])), 0)
	_terrain_cell_count += cells.size()
	return true


func _build_objects(entries: Array) -> bool:
	if entries.is_empty():
		return true
	var tileset := TileSet.new()
	tileset.resource_name = "Wilderness Map Objects"
	tileset.tile_size = OBJECT_GRID
	var scene_source := TileSetScenesCollectionSource.new()
	scene_source.resource_name = "Trees buildings rocks and wilderness props"
	tileset.add_source(scene_source, 0)
	for index in range(entries.size()):
		if not entries[index] is Dictionary:
			return _error("Object entry %d must be an object." % index)
		var entry: Dictionary = entries[index]
		if not _is_pair(entry.get("cell")) or not _is_pair(entry.get("offset", [0, 0])) or not _is_pair(entry.get("sprite_offset", [0, 0])):
			return _error("Object %d requires cell, offset, and sprite_offset coordinate pairs." % index)
		var scene := _build_object(entry, index)
		if scene == null:
			return false
		var scene_tile_id := scene_source.create_scene_tile(scene, index)
		if scene_tile_id != index:
			return _error("Cannot create scene tile %d." % index)
		scene_source.set_scene_tile_display_placeholder(scene_tile_id, false)
	if not _save_resource(tileset, OBJECT_TILESET_PATH):
		return false
	var saved_tileset := load(OBJECT_TILESET_PATH) as TileSet
	if saved_tileset == null:
		return _error("Cannot reload " + OBJECT_TILESET_PATH)

	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		var cell := Vector2i(_vector_pair(entry["cell"]))
		var kind := _safe_name(String(entry.get("kind", "Objects")))
		var layer_index := 0
		while layer_index < _object_layers.size() and (_object_layer_kinds[layer_index] != kind or _occupied_object_cells[layer_index].has(cell)):
			layer_index += 1
		if layer_index == _object_layers.size():
			var layer := TileMapLayer.new()
			var overlap_number := _object_layer_kinds.count(kind)
			layer.name = kind if overlap_number == 0 else "%sOverlap%d" % [kind, overlap_number + 1]
			layer.tile_set = saved_tileset
			layer.y_sort_enabled = true
			layer.z_index = 0
			layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			layer.navigation_enabled = false
			_scene_root.add_child(layer)
			layer.owner = _scene_root
			_object_layers.append(layer)
			_occupied_object_cells.append({})
			_object_layer_kinds.append(kind)
		_object_layers[layer_index].set_cell(cell, 0, Vector2i.ZERO, index)
		_occupied_object_cells[layer_index][cell] = true
		_object_count += 1
	return true


func _build_object(entry: Dictionary, index: int) -> PackedScene:
	var object_name := _safe_name(String(entry.get("name", "Object%d" % index)))
	var kind := String(entry.get("kind", "prop"))
	var texture := _load_texture(String(entry.get("texture", "")))
	if texture == null:
		return null
	var object_root := Node2D.new()
	object_root.name = object_name
	object_root.y_sort_enabled = true
	object_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	object_root.set_meta("kind", kind)

	# Scene tiles start at the cell center. Offset the sort unit to its real feet.
	var body := StaticBody2D.new()
	body.name = "Footprint"
	body.position = _vector_pair(entry.get("offset", [0, 0]))
	body.y_sort_enabled = false
	body.collision_layer = WORLD_COLLISION_LAYER
	body.collision_mask = 0
	body.add_to_group("map_object", true)
	body.set_meta("kind", kind)
	object_root.add_child(body)
	body.owner = object_root
	var sprite := Sprite2D.new()
	sprite.name = "Visual"
	sprite.texture = texture
	sprite.centered = false
	sprite.position = _vector_pair(entry.get("sprite_offset", [0, 0]))
	sprite.z_index = 0
	body.add_child(sprite)
	sprite.owner = object_root
	var polygons_value: Variant = entry.get("collision_polygons", [])
	if not polygons_value is Array:
		_error("%s collision_polygons must be an array." % object_name)
		object_root.free()
		return null
	for polygon_index in range(polygons_value.size()):
		var polygon := _polygon_points(polygons_value[polygon_index], object_name)
		if polygon.is_empty():
			object_root.free()
			return null
		var shape := CollisionPolygon2D.new()
		shape.name = "SolidPolygon%d" % (polygon_index + 1)
		shape.polygon = polygon
		body.add_child(shape)
		shape.owner = object_root
		_collision_polygon_count += 1
	var circles: Array = entry.get("collision_circles", []).duplicate()
	if entry.has("collision_circle"):
		circles.append(entry["collision_circle"])
	for circle_index in circles.size():
		var circle_value: Variant = circles[circle_index]
		if not circle_value is Dictionary or float(circle_value.get("radius", 0)) <= 0 or not _is_pair(circle_value.get("position", [0, 0])):
			_error("%s collision_circle requires a positive radius and position:[x,y]." % object_name)
			object_root.free()
			return null
		var circle := CircleShape2D.new()
		circle.radius = float(circle_value["radius"])
		var shape := CollisionShape2D.new()
		shape.name = "SolidCircle%d" % circle_index
		shape.shape = circle
		shape.position = _vector_pair(circle_value.get("position", [0, 0]))
		body.add_child(shape)
		shape.owner = object_root
		_collision_circle_count += 1
	if not polygons_value.is_empty() or not circles.is_empty():
		body.add_to_group("world_solid", true)
	var object_path := "%s/%04d_%s.tscn" % [OBJECT_DIRECTORY, index, object_name]
	var packed := PackedScene.new()
	var pack_error := packed.pack(object_root)
	object_root.free()
	if pack_error != OK:
		_error("Cannot pack %s: %s" % [object_name, error_string(pack_error)])
		return null
	if not _save_resource(packed, object_path):
		return null
	return load(object_path) as PackedScene


func _ensure_atlas_tile(atlas: TileSetAtlasSource, coordinates: Vector2i, bounds: Vector2i, context: String) -> bool:
	if coordinates.x < 0 or coordinates.y < 0 or coordinates.x >= bounds.x or coordinates.y >= bounds.y:
		return _error("%s atlas coordinates %s fall outside %s." % [context, coordinates, bounds])
	if not atlas.has_tile(coordinates):
		atlas.create_tile(coordinates)
	return true


func _load_texture(resource_path: String) -> Texture2D:
	if not resource_path.begins_with("res://") or not ResourceLoader.exists(resource_path):
		_error("Missing imported texture: %s. Import the generated PNGs before building." % resource_path)
		return null
	var texture := load(resource_path) as Texture2D
	if texture == null:
		_error("Cannot load texture: " + resource_path)
	return texture


func _polygon_points(value: Variant, context: String) -> PackedVector2Array:
	var points := PackedVector2Array()
	if not value is Array or value.size() < 3:
		_error("%s collision polygon needs at least three points." % context)
		return points
	for point: Variant in value:
		if not _is_pair(point):
			_error("%s collision polygon point must be [x,y]." % context)
			return PackedVector2Array()
		points.append(_vector_pair(point))
	if Geometry2D.triangulate_polygon(points).is_empty():
		_error("%s collision polygon is degenerate or intersects itself." % context)
		return PackedVector2Array()
	return points


func _save_scene(node: Node, resource_path: String) -> bool:
	var packed := PackedScene.new()
	var pack_error := packed.pack(node)
	if pack_error != OK:
		return _error("Cannot pack %s: %s" % [resource_path, error_string(pack_error)])
	return _save_resource(packed, resource_path)


func _save_resource(resource: Resource, resource_path: String) -> bool:
	var save_error := ResourceSaver.save(resource, resource_path)
	if save_error != OK:
		return _error("Cannot save %s: %s" % [resource_path, error_string(save_error)])
	return true


func _is_pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float)


func _vector_pair(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))


func _safe_name(value: String) -> String:
	var output := ""
	for character in value:
		if character >= "a" and character <= "z" or character >= "A" and character <= "Z" or character >= "0" and character <= "9" or character == "_":
			output += character
		else:
			output += "_"
	return output if not output.is_empty() else "Generated"


func _error(message: String) -> bool:
	push_error("[WildernessMap] " + message)
	return false
