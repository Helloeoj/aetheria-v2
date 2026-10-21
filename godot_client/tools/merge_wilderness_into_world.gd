extends SceneTree
## Merge approved wilderness cells into one editable world without changing the source maps.
## Run after build_wilderness_map.gd:
## godot --headless --path . --script res://tools/merge_wilderness_into_world.gd

const EXISTING_SCENE := "res://scenes/PlayableMapContent.tscn"
const WILDERNESS_SCENE := "res://scenes/WildernessMapContent.tscn"
const OUTPUT_SCENE := "res://scenes/ValtheirisWorldContent.tscn"
const TILESET_DIRECTORY := "res://Assets/Tilesets"
const WORLD_ORIGIN := Vector2(-1536, -3072)
const WORLD_SIZE := Vector2(3072, 5728)
const TERRAIN_ALIASES := {"Paths": "PathsAndQuays", "Roads": "PathsAndQuays"}
const ReviewInstaller := preload("res://tools/apply_review_sections.gd")

var _world: Node2D
var _wilderness: Node2D
var _old_set_clones: Dictionary = {}
var _imported_source_maps: Dictionary = {}
var _world_sets: Array[Dictionary] = []
var _object_set: TileSet
var _existing_cells := 0
var _appended_cells := 0
var _new_layers := 0
var _last_error := ""
var _border_overrides: Dictionary = {}
var _polished_scenes: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var succeeded := _merge()
	if _wilderness != null:
		_wilderness.free()
	if _world != null:
		_world.free()
	quit(0 if succeeded else 1)


func _merge() -> bool:
	var manifest_text := FileAccess.get_file_as_string("res://Assets/MapTiles/Wilderness/wilderness_manifest.json")
	var manifest: Variant = JSON.parse_string(manifest_text)
	if manifest is Dictionary:
		for override: Dictionary in manifest.get("border_visual_overrides", []):
			_border_overrides[String(override["name"])] = override
	var existing := load(EXISTING_SCENE) as PackedScene
	var incoming := load(WILDERNESS_SCENE) as PackedScene
	if existing == null or incoming == null:
		return _error("Both source map scenes must exist before merging.")
	# Keep these off the SceneTree: scene-tile runtime children are never packed.
	_world = existing.instantiate() as Node2D
	_wilderness = incoming.instantiate() as Node2D
	if _world == null or _wilderness == null:
		return _error("Both source map roots must be Node2D.")
	_world.name = "ValtheirisWorldContent"
	_world.y_sort_enabled = true
	_world.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_world.set_meta("map_origin", WORLD_ORIGIN)
	_world.set_meta("map_size", WORLD_SIZE)
	_world.set_meta("section_size", 1536)
	_world.set_meta("source_scenes", PackedStringArray([EXISTING_SCENE, WILDERNESS_SCENE]))
	_world.set_meta("wilderness_manifest", "res://Assets/MapTiles/Wilderness/wilderness_manifest.json")
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TILESET_DIRECTORY))
	if directory_error != OK:
		return _error("Cannot create world TileSet directory: " + error_string(directory_error))

	for child in _world.get_children():
		if not child is TileMapLayer:
			continue
		var layer := child as TileMapLayer
		if layer.tile_set == null:
			return _error("Existing layer %s has no TileSet." % layer.name)
		_existing_cells += layer.get_used_cells().size()
		var original := layer.tile_set
		var key := original.get_instance_id()
		if not _old_set_clones.has(key):
			var cloned := _clone_tileset(original)
			if cloned == null:
				return false
			var file_name := original.resource_path.get_file().replace("Playable", "World")
			if file_name.is_empty() or not file_name.begins_with("World"):
				file_name = "World_%s.tres" % _safe_name(String(layer.name))
			cloned.resource_name = original.resource_name.replace("Playable", "Valtheiris World")
			_old_set_clones[key] = cloned
			_world_sets.append({"tileset": cloned, "path": TILESET_DIRECTORY.path_join(file_name)})
		layer.tile_set = _old_set_clones[key]
		layer.owner = _world
		if _contains_scene_source(original):
			_object_set = layer.tile_set

	for child in _wilderness.get_children():
		if not child is TileMapLayer:
			continue
		var incoming_layer := child as TileMapLayer
		if incoming_layer.tile_set == null:
			return _error("Wilderness layer %s has no TileSet." % incoming_layer.name)
		var target_name := String(TERRAIN_ALIASES.get(String(incoming_layer.name), String(incoming_layer.name)))
		var destination := _world.get_node_or_null(NodePath(target_name)) as TileMapLayer
		var target_set: TileSet
		if _contains_scene_source(incoming_layer.tile_set) and _object_set != null:
			target_set = _object_set
		elif destination != null:
			target_set = destination.tile_set
		else:
			target_set = _clone_tileset(incoming_layer.tile_set)
			if target_set == null:
				return false
			target_set.resource_name = "Valtheiris World " + target_name
			_world_sets.append({"tileset": target_set, "path": TILESET_DIRECTORY.path_join("World_%s.tres" % _safe_name(target_name))})
			if _contains_scene_source(target_set):
				_object_set = target_set
			# This new category already owns an exact clone of its source IDs.
			var direct_map: Dictionary = {}
			for index in incoming_layer.tile_set.get_source_count():
				var source_id := incoming_layer.tile_set.get_source_id(index)
				direct_map[source_id] = source_id
			_imported_source_maps[_source_map_key(target_set, incoming_layer.tile_set)] = direct_map
		if destination != null and destination.tile_set != target_set:
			return _error("Layer %s would mix incompatible world TileSets." % target_name)
		var source_map := _append_sources(target_set, incoming_layer.tile_set)
		if source_map.is_empty() and incoming_layer.tile_set.get_source_count() > 0:
			return false
		for cell in incoming_layer.get_used_cells():
			var destination_layer := _layer_with_free_cell(target_name, incoming_layer, target_set, cell)
			if destination_layer == null:
				return false
			var source_id := incoming_layer.get_cell_source_id(cell)
			if not source_map.has(source_id):
				return _error("Layer %s references an unavailable incoming source %d." % [target_name, source_id])
			destination_layer.set_cell(cell, int(source_map[source_id]), incoming_layer.get_cell_atlas_coords(cell), incoming_layer.get_cell_alternative_tile(cell))
			_appended_cells += 1

	# Local review art remains in the shared layer stack after a deliberate rebuild.
	var review_result: Dictionary = ReviewInstaller.apply(_world)
	if not bool(review_result.get("ok", false)):
		return _error("Cannot retain reviewed terrain: " + str(review_result.get("errors", [])))
	# Save and reload once so the packed world references external TileSet files.
	for record in _world_sets:
		var tileset := record["tileset"] as TileSet
		var path := String(record["path"])
		var save_error := ResourceSaver.save(tileset, path)
		if save_error != OK:
			return _error("Cannot save %s: %s" % [path, error_string(save_error)])
		var saved := ResourceLoader.load(path, "TileSet", ResourceLoader.CACHE_MODE_REPLACE) as TileSet
		if saved == null:
			return _error("Cannot reload " + path)
		for child in _world.get_children():
			if child is TileMapLayer and child.tile_set == tileset:
				child.tile_set = saved
	var packed := PackedScene.new()
	var pack_error := packed.pack(_world)
	if pack_error != OK:
		return _error("Cannot pack the unified world: " + error_string(pack_error))
	var save_error := ResourceSaver.save(packed, OUTPUT_SCENE)
	if save_error != OK:
		return _error("Cannot save the unified world: " + error_string(save_error))
	print("[ValtheirisWorld] Saved %s. Preserved %d existing cells; appended %d wilderness cells across %d total layers, %d new layers, %d external world TileSets." % [OUTPUT_SCENE, _existing_cells, _appended_cells, _world.get_child_count(), _new_layers, _world_sets.size()])
	return true


func _append_sources(destination: TileSet, incoming: TileSet) -> Dictionary:
	var key := _source_map_key(destination, incoming)
	if _imported_source_maps.has(key):
		return _imported_source_maps[key]
	if destination.tile_size != incoming.tile_size:
		_error("Cannot merge TileSets with different tile sizes.")
		return {}
	while destination.get_physics_layers_count() < incoming.get_physics_layers_count():
		var layer := destination.get_physics_layers_count()
		destination.add_physics_layer()
		destination.set_physics_layer_collision_layer(layer, incoming.get_physics_layer_collision_layer(layer))
		destination.set_physics_layer_collision_mask(layer, incoming.get_physics_layer_collision_mask(layer))
	var source_map: Dictionary = {}
	for index in incoming.get_source_count():
		var original_id := incoming.get_source_id(index)
		var cloned := _clone_source(incoming.get_source(original_id))
		if cloned == null:
			return {}
		var new_id := destination.get_next_source_id()
		destination.add_source(cloned, new_id)
		source_map[original_id] = new_id
	_imported_source_maps[key] = source_map
	return source_map


func _clone_tileset(original: TileSet) -> TileSet:
	var cloned := original.duplicate(true) as TileSet
	if cloned == null:
		_error("Cannot duplicate a source TileSet.")
		return null
	# Keep exact tile data while retaining the existing external textures/scenes.
	for index in original.get_source_count():
		var source_id := original.get_source_id(index)
		var source := _clone_source(original.get_source(source_id))
		if source == null:
			return null
		cloned.remove_source(source_id)
		cloned.add_source(source, source_id)
	return cloned


func _clone_source(original: TileSetSource) -> TileSetSource:
	var cloned := original.duplicate(true) as TileSetSource
	if cloned == null:
		_error("Cannot duplicate a TileSet source.")
		return null
	if original is TileSetAtlasSource:
		(cloned as TileSetAtlasSource).texture = (original as TileSetAtlasSource).texture
	elif original is TileSetScenesCollectionSource:
		var incoming_scenes := original as TileSetScenesCollectionSource
		var cloned_scenes := cloned as TileSetScenesCollectionSource
		for index in incoming_scenes.get_scene_tiles_count():
			var tile_id := incoming_scenes.get_scene_tile_id(index)
			var scene := incoming_scenes.get_scene_tile_scene(tile_id)
			var scene_name := String(scene.get_state().get_node_name(0))
			if _border_overrides.has(scene_name):
				scene = _polish_border_scene(scene, _border_overrides[scene_name])
				if scene == null:
					return null
			cloned_scenes.set_scene_tile_scene(tile_id, scene)
	return cloned


func _polish_border_scene(original: PackedScene, override: Dictionary) -> PackedScene:
	var object_name := String(override["name"])
	if _polished_scenes.has(object_name):
		return _polished_scenes[object_name]
	var node := original.instantiate()
	var visual := node.get_node_or_null("Footprint/Visual") as Sprite2D
	if visual == null:
		node.free()
		_error("Border tree has no visual: " + object_name)
		return null
	visual.texture = load(String(override["texture"])) as Texture2D
	var offset: Array = override["sprite_offset"]
	visual.position = Vector2(float(offset[0]), float(offset[1]))
	# Keep every Footprint transform, shape resource and authored circle intact.
	var packed := PackedScene.new()
	var pack_error := packed.pack(node)
	node.free()
	if pack_error != OK:
		_error("Cannot pack completed border tree: " + object_name)
		return null
	var directory := "res://scenes/MapObjectsPolished"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory.path_join(object_name + ".tscn")
	if ResourceSaver.save(packed, path) != OK:
		_error("Cannot save completed border tree: " + object_name)
		return null
	var saved := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	_polished_scenes[object_name] = saved
	return saved


func _layer_with_free_cell(stem: String, template: TileMapLayer, tileset: TileSet, cell: Vector2i) -> TileMapLayer:
	var overlap := 1
	while true:
		var layer_name := stem if overlap == 1 else "%sOverlap%d" % [stem, overlap]
		var candidate := _world.get_node_or_null(NodePath(layer_name)) as TileMapLayer
		if candidate == null:
			candidate = template.duplicate(0) as TileMapLayer
			if candidate == null:
				_error("Cannot create editable layer " + layer_name)
				return null
			candidate.name = layer_name
			candidate.clear()
			candidate.tile_set = tileset
			_world.add_child(candidate)
			candidate.owner = _world
			_new_layers += 1
		if candidate.tile_set != tileset:
			_error("Existing layer %s has an incompatible TileSet." % layer_name)
			return null
		if candidate.get_cell_source_id(cell) == -1:
			return candidate
		overlap += 1
	return null


func _contains_scene_source(tileset: TileSet) -> bool:
	for index in tileset.get_source_count():
		if tileset.get_source(tileset.get_source_id(index)) is TileSetScenesCollectionSource:
			return true
	return false


func _source_map_key(destination: TileSet, incoming: TileSet) -> String:
	return "%d:%d" % [destination.get_instance_id(), incoming.get_instance_id()]


func _safe_name(value: String) -> String:
	var output := ""
	for character in value:
		if character >= "a" and character <= "z" or character >= "A" and character <= "Z" or character >= "0" and character <= "9" or character == "_":
			output += character
		else:
			output += "_"
	return output if not output.is_empty() else "Layer"


func _error(message: String) -> bool:
	_last_error = message
	push_error("[ValtheirisWorld] " + message)
	return false
