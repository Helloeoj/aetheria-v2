class_name ReviewSectionInstaller
extends RefCounted
## Apply approved, local terrain revisions to the existing editable map layers.
## This utility changes in-memory resources only. The caller owns all saving.

const DEFAULT_REGISTRY := "res://Assets/MapTiles/ReviewSections/sections.json"
const TILE_SIZE := Vector2i(32, 32)
const ALLOWED_LAYERS := ["Grass", "PathsAndQuays", "GroundDetails"]


static func apply(world: Node2D, registry_path: String = DEFAULT_REGISTRY) -> Dictionary:
	var result := {
		"ok": false,
		"errors": [],
		"registry": registry_path,
		"sections": [],
		"cells_changed": 0,
		"modified_tilesets": [],
	}
	if world == null:
		return _fail(result, "A world root is required.")
	if world.is_inside_tree():
		return _fail(result, "Apply review sections before adding the world to the SceneTree.")
	if not FileAccess.file_exists(registry_path):
		result["ok"] = true
		result["registry_missing"] = true
		return result
	var parser := JSON.new()
	var parse_error := parser.parse(FileAccess.get_file_as_string(registry_path))
	if parse_error != OK:
		return _fail(result, "Review registry line %d: %s" % [parser.get_error_line(), parser.get_error_message()])
	if not parser.data is Dictionary or not parser.data.get("sections") is Array:
		return _fail(result, "Review registry must contain a sections array.")

	# Validate the complete request before changing any source or TileMap cell.
	var plans: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	for entry: Variant in parser.data["sections"]:
		if not entry is Dictionary:
			return _fail(result, "Every review section must be an object.")
		var section: Dictionary = entry
		var section_id := String(section.get("id", ""))
		if section_id.is_empty() or seen_ids.has(section_id):
			return _fail(result, "Review section IDs must be nonempty and unique: " + section_id)
		seen_ids[section_id] = true
		if not _integer_pair(section.get("origin")) or not _integer_pair(section.get("size")):
			return _fail(result, "%s origin and size must be integer pairs." % section_id)
		var origin_values: Array = section["origin"]
		var size_values: Array = section["size"]
		var origin := Vector2i(int(origin_values[0]), int(origin_values[1]))
		var size := Vector2i(int(size_values[0]), int(size_values[1]))
		if size.x <= 0 or size.y <= 0 or origin.x % 32 != 0 or origin.y % 32 != 0 or size.x % 32 != 0 or size.y % 32 != 0:
			return _fail(result, "%s origin and positive size must align to the 32 pixel grid." % section_id)
		if not section.get("layers") is Array:
			return _fail(result, "%s must contain a layers array." % section_id)
		var section_layers: Dictionary = {}
		for layer_entry: Variant in section["layers"]:
			if not layer_entry is Dictionary:
				return _fail(result, "%s layer entries must be objects." % section_id)
			var layer_name := String(layer_entry.get("name", ""))
			if not ALLOWED_LAYERS.has(layer_name) or section_layers.has(layer_name):
				return _fail(result, "%s has an unsupported or duplicate layer: %s" % [section_id, layer_name])
			section_layers[layer_name] = true
			var layer := world.get_node_or_null(NodePath(layer_name)) as TileMapLayer
			if layer == null or layer.tile_set == null or layer.tile_set.tile_size != TILE_SIZE:
				return _fail(result, "%s requires an existing %s TileMapLayer with 32 pixel tiles." % [section_id, layer_name])
			var texture_path := String(layer_entry.get("texture", ""))
			if not texture_path.begins_with("res://Assets/MapTiles/ReviewSections/") or not texture_path.ends_with(".png"):
				return _fail(result, "%s %s must reference a PNG inside Assets/MapTiles/ReviewSections." % [section_id, layer_name])
			var texture := ResourceLoader.load(texture_path, "Texture2D", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D
			if texture == null or texture.get_width() != size.x or texture.get_height() != size.y:
				return _fail(result, "%s %s texture must be imported and match section size %s." % [section_id, layer_name, size])
			var image := texture.get_image()
			if image == null or image.is_empty():
				return _fail(result, "%s %s texture pixels are unavailable." % [section_id, layer_name])
			if image.is_compressed() and image.decompress() != OK:
				return _fail(result, "%s %s texture cannot be decompressed." % [section_id, layer_name])
			image.convert(Image.FORMAT_RGBA8)
			var source_name := "Review %s %s" % [section_id, layer_name]
			var source_id := _find_source(layer.tile_set, section_id, layer_name, source_name)
			if source_id >= 0:
				var existing := layer.tile_set.get_source(source_id) as TileSetAtlasSource
				if existing == null or existing.texture_region_size != TILE_SIZE:
					return _fail(result, "Existing %s source is incompatible." % source_name)
				if existing.texture == null or existing.texture.get_width() != size.x or existing.texture.get_height() != size.y:
					return _fail(result, "Existing %s source size differs from its registry." % source_name)
			var region := Rect2i(origin / TILE_SIZE, size / TILE_SIZE)
			for previous in plans:
				if previous["layer"] == layer and region.intersects(previous["region"]):
					return _fail(result, "Review sections overlap on layer %s: %s and %s." % [layer_name, previous["section_id"], section_id])
			plans.append({
				"section_id": section_id, "layer_name": layer_name, "layer": layer,
				"origin": origin, "size": size, "region": region,
				"texture": texture, "texture_path": texture_path, "pixels": image.get_data(),
				"source_name": source_name, "source_id": source_id,
			})

	var modified: Dictionary = {}
	for plan in plans:
		var layer: TileMapLayer = plan["layer"]
		var tileset := layer.tile_set
		var source_id: int = plan["source_id"]
		var source: TileSetAtlasSource
		var source_created := source_id < 0
		if source_created:
			source = TileSetAtlasSource.new()
			source.texture_region_size = TILE_SIZE
			source.texture = plan["texture"]
			source_id = tileset.get_next_source_id()
			tileset.add_source(source, source_id)
		else:
			source = tileset.get_source(source_id) as TileSetAtlasSource
			source.texture = plan["texture"]
		source.resource_name = plan["source_name"]
		source.set_meta("review_section", plan["section_id"])
		source.set_meta("review_layer", plan["layer_name"])
		source.set_meta("review_origin", plan["origin"])
		source.set_meta("review_size", plan["size"])
		var region: Rect2i = plan["region"]
		var width: int = plan["size"].x
		var pixels: PackedByteArray = plan["pixels"]
		var cells_painted := 0
		var cells_erased := 0
		var cells_changed := 0
		for tile_y in range(region.size.y):
			for tile_x in range(region.size.x):
				var atlas := Vector2i(tile_x, tile_y)
				var cell := region.position + atlas
				var old_source := layer.get_cell_source_id(cell)
				if _has_alpha(pixels, width, atlas):
					if not source.has_tile(atlas):
						source.create_tile(atlas)
					# Review grass, paths and details deliberately have no physics polygons.
					if old_source != source_id or layer.get_cell_atlas_coords(cell) != atlas or layer.get_cell_alternative_tile(cell) != 0:
						cells_changed += 1
					layer.set_cell(cell, source_id, atlas, 0)
					cells_painted += 1
				else:
					if old_source >= 0:
						cells_erased += 1
						cells_changed += 1
					layer.erase_cell(cell)
		var layer_report := {
			"id": plan["section_id"], "layer": plan["layer_name"],
			"source_id": source_id, "source_created": source_created,
			"origin": [plan["origin"].x, plan["origin"].y],
			"size": [plan["size"].x, plan["size"].y],
			"cells_in_region": region.size.x * region.size.y,
			"cells_painted": cells_painted, "cells_erased": cells_erased,
			"cells_changed": cells_changed,
		}
		result["sections"].append(layer_report)
		result["cells_changed"] += cells_changed
		var key := tileset.get_instance_id()
		if not modified.has(key):
			modified[key] = {"tileset": tileset, "path": tileset.resource_path, "layers": []}
		modified[key]["layers"].append(plan["layer_name"])
	result["modified_tilesets"] = modified.values()
	result["ok"] = true
	return result


static func _find_source(tileset: TileSet, section_id: String, layer_name: String, source_name: String) -> int:
	for index in range(tileset.get_source_count()):
		var source_id := tileset.get_source_id(index)
		var source := tileset.get_source(source_id)
		if source.resource_name == source_name:
			return source_id
		if String(source.get_meta("review_section", "")) == section_id and String(source.get_meta("review_layer", "")) == layer_name:
			return source_id
	return -1


static func _has_alpha(pixels: PackedByteArray, width: int, atlas: Vector2i) -> bool:
	for y in range(atlas.y * 32, (atlas.y + 1) * 32):
		for x in range(atlas.x * 32, (atlas.x + 1) * 32):
			if pixels[(y * width + x) * 4 + 3] > 0:
				return true
	return false


static func _integer_pair(value: Variant) -> bool:
	if not value is Array or value.size() != 2:
		return false
	for component: Variant in value:
		if not (component is int or component is float) or not is_finite(float(component)) or float(component) != floor(float(component)):
			return false
	return true


static func _fail(result: Dictionary, message: String) -> Dictionary:
	result["errors"].append(message)
	return result
