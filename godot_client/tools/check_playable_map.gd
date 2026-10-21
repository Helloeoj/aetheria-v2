extends SceneTree
## Runtime physics and editable-map integration check; no editor window needed.
## godot --headless --path . --script res://tools/check_playable_map.gd

const MAP_PATH := "res://scenes/EastOutskirtsLayered.tscn"
const MANIFEST_PATH := "res://Assets/MapTiles/map_manifest.json"
const BLOCKOUT_PATH := "res://scenes/EastOutskirtsBlockout.tscn"
const REPORT_PATH := "res://../../exports/PlayableMapUpgrade/verification.json"
const ORIGINAL_HEIGHT := 1024.0

var _checks := 0
var _failures: Array[String] = []
var _map: Node2D
var _space: PhysicsDirectSpaceState2D
var _counts := {"scene_tiles": 0, "object_polygons": 0, "object_circles": 0, "water_polygons": 0}
var _object_kinds: Dictionary = {}
var _clear_ground := {"original": 0, "harbor": 0}


func _initialize() -> void:
	_run.call_deferred()


func _verify(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		printerr("[PlayableMap check] " + message)


func _run() -> void:
	if not FileAccess.file_exists(MANIFEST_PATH):
		_verify(false, "Missing map manifest; run the content builder first.")
		_finish()
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not parsed is Dictionary:
		_verify(false, "Cannot parse map manifest.")
		_finish()
		return
	var manifest: Dictionary = parsed
	var expected_blockout_hash := String(manifest.get("verification", {}).get("blockout_sha256", ""))
	_verify(not expected_blockout_hash.is_empty() and FileAccess.get_sha256(BLOCKOUT_PATH).to_lower() == expected_blockout_hash, "Authored collision reference changed after map generation.")
	var packed := load(MAP_PATH) as PackedScene
	if packed == null:
		_verify(false, "Main map scene did not load.")
		_finish()
		return
	_map = packed.instantiate() as Node2D
	root.add_child(_map)
	# Scene tiles and physics bodies register at the end of the frame.
	for frame in 4:
		await process_frame
		await physics_frame
	_space = _map.get_world_2d().direct_space_state
	var combat := _map.get_node_or_null("Combat") as Node2D
	_verify(combat != null, "Main map has no combat controller.")
	_verify(_map.y_sort_enabled, "Map root does not sort objects by their feet.")
	if combat != null:
		_verify(combat.y_sort_enabled and combat.z_index == 0, "Actors do not share the map's Y-sort plane.")
		_verify(is_equal_approx(combat.map_width, 1536.0) and is_equal_approx(combat.map_height, 2656.0), "Controller bounds do not match the extended map.")
		combat.set_physics_process(false)
		combat.set_process(false)
		var player_actor := combat.actor_sprites.get(combat.player.entity_id) as ActorSprite
		_verify(player_actor != null, "Player actor did not initialize.")
		if player_actor != null:
			_verify_canvas_depth(player_actor)
			_verify(not player_actor.y_sort_enabled, "Actor parts may interleave with map objects.")
			_verify(player_actor.collision_mask == 1, "Actor movement does not collide with world geometry.")
			_verify(player_actor.position.is_equal_approx(Vector2(320, 704)), "Extended map moved the original player spawn.")
	var original := _map.get_node_or_null("CollisionGeometry") as Node2D
	_verify(original != null, "Original authored collision scene is not instanced.")
	if original != null:
		_verify(original.transform.is_equal_approx(Transform2D.IDENTITY), "Original collisions were translated or scaled.")
		_verify(original.process_mode == Node.PROCESS_MODE_DISABLED, "Collision reference is still active alongside migrated scene-tile shapes.")
	_verify(int(manifest.get("verification", {}).get("original_reference_different_pixels", -1)) == 0, "Original map artwork changed during conversion.")
	_verify(int(manifest.get("verification", {}).get("authored_shapes_migrated", -1)) == 25, "The authored collision shapes were not all transferred.")
	var content := _map.get_node_or_null("PlayableMapContent") as Node2D
	if content == null:
		_verify(false, "Editable content scene is missing.")
		_finish()
		return
	_verify(content.y_sort_enabled and content.z_index == 0, "Editable content breaks the common Y-sort plane.")
	_check_scene_tiles(content, manifest.get("objects", []))
	_check_terrain(content, manifest.get("terrain", []))
	_verify(_clear_ground["original"] >= 3 and _clear_ground["harbor"] >= 3, "Open ground was not confirmed in both map sections.")
	_verify(_counts["object_polygons"] + _counts["object_circles"] > 0, "No generated object collision was exercised.")
	_verify(_counts["water_polygons"] > 0, "No harbor water collision was exercised.")
	_finish()


func _verify_canvas_depth(node: Node) -> void:
	if node is CanvasItem:
		_verify(node.z_index == 0, "Actor child escapes world depth sorting: " + str(node.get_path()))
	for child in node.get_children():
		_verify_canvas_depth(child)


func _check_scene_tiles(content: Node2D, objects: Array) -> void:
	var found: Dictionary = {}
	for candidate_layer: Node in content.get_children():
		var layer := candidate_layer as TileMapLayer
		if layer == null or layer.tile_set == null or layer.tile_set.get_source_count() == 0:
			continue
		var source: TileSetSource = layer.tile_set.get_source(layer.tile_set.get_source_id(0))
		if not source is TileSetScenesCollectionSource:
			continue
		_verify(layer.y_sort_enabled and layer.z_index == 0, "Object tiles do not sort on the actor plane: " + layer.name)
		for cell: Vector2i in layer.get_used_cells():
			var identifier := layer.get_cell_alternative_tile(cell)
			_verify(identifier >= 0 and identifier < objects.size(), "Object cell references a missing scene tile.")
			if identifier < 0 or identifier >= objects.size():
				continue
			_verify(not found.has(identifier), "Scene tile appears more than once: %d" % identifier)
			found[identifier] = true
			var entry: Dictionary = objects[identifier]
			var expected_position: Vector2 = layer.to_global(layer.map_to_local(cell) + _point(entry.get("offset", [0, 0])))
			var body: StaticBody2D = null
			for instance: Node in layer.get_children():
				var candidate := instance.get_node_or_null("Footprint") as StaticBody2D
				if candidate != null and candidate.global_position.distance_to(expected_position) < 0.01:
					body = candidate
					break
			_verify(body != null, "Painted scene tile failed to instantiate at its footprint: " + String(entry.get("name", identifier)))
			if body == null:
				continue
			_counts["scene_tiles"] += 1
			_verify(body.z_index == 0 and not body.y_sort_enabled and body.get_parent().y_sort_enabled, "Object does not sort as one unit at its footprint.")
			_check_object_collision(body, entry)
	_verify(found.size() == objects.size(), "Not every manifest object is painted in the map.")
	_verify(_counts["scene_tiles"] == objects.size(), "Painted object count differs from live scene instance count.")


func _check_object_collision(body: StaticBody2D, entry: Dictionary) -> void:
	var exercised := 0
	for polygon_value: Array in entry.get("collision_polygons", []):
		var point := body.to_global(_inside_polygon(polygon_value))
		_verify(_point_hits_body(point, body), "Object polygon did not block: " + String(entry.get("name", "unnamed")))
		_counts["object_polygons"] += 1
		exercised += 1
	var circles: Array = entry.get("collision_circles", []).duplicate()
	if entry.has("collision_circle"):
		circles.append(entry["collision_circle"])
	for circle: Dictionary in circles:
		var point := body.to_global(_point(circle.get("position", [0, 0])))
		_verify(_point_hits_body(point, body), "Object circle did not block: " + String(entry.get("name", "unnamed")))
		_counts["object_circles"] += 1
		exercised += 1
	for authored: Dictionary in entry.get("authored_collision", []):
		var center := _point(authored["position"])
		_verify(_point_hits_body(center, body), "Migrated authored collider is misplaced: " + String(authored["name"]))
		var matched := false
		for shape_node: Node in body.get_children():
			if shape_node is CollisionShape2D and shape_node.shape is CircleShape2D and authored.has("radius"):
				if shape_node.global_position.is_equal_approx(center) and is_equal_approx(shape_node.shape.radius, float(authored["radius"])):
					matched = true
			elif shape_node is CollisionPolygon2D and authored.has("size"):
				var rect := Rect2()
				for i in shape_node.polygon.size():
					var p: Vector2 = shape_node.to_global(shape_node.polygon[i])
					rect = Rect2(p, Vector2.ZERO) if i == 0 else rect.expand(p)
				if rect.get_center().is_equal_approx(center) and rect.size.is_equal_approx(_point(authored["size"])):
					matched = true
		_verify(matched, "Authored collider dimensions changed: " + String(authored["name"]))
	if exercised > 0:
		var kind := String(entry.get("kind", "prop"))
		_object_kinds[kind] = int(_object_kinds.get(kind, 0)) + 1


func _check_terrain(content: Node2D, terrain: Array) -> void:
	for entry: Dictionary in terrain:
		var layer := content.get_node_or_null(_safe_name(String(entry.get("name", "")))) as TileMapLayer
		_verify(layer != null, "Missing editable terrain layer: " + String(entry.get("name", "")))
		if layer == null:
			continue
		_verify(layer.tile_set != null and layer.tile_set.get_source(0) is TileSetAtlasSource, "Terrain is not an editable tile atlas.")
		_verify(layer.get_used_cells().size() == entry.get("cells", []).size(), "Terrain cell count differs from manifest: " + layer.name)
		var physics: Dictionary = {}
		for tile: Dictionary in entry.get("physics_cells", []):
			physics[Vector2i(_point(tile["atlas"]))] = tile.get("polygons", [])
		var is_walkable_kind := layer.name.to_lower().contains("ground") or layer.name.to_lower().contains("path")
		for cell_value: Array in entry.get("cells", []):
			var cell := Vector2i(int(cell_value[0]), int(cell_value[1]))
			var atlas := Vector2i(int(cell_value[2]), int(cell_value[3]))
			var center := layer.map_to_local(cell)
			if physics.has(atlas):
				for polygon_value: Array in physics[atlas]:
					var point := layer.to_global(center + _inside_polygon(polygon_value))
					_verify(_point_hits_body(point, layer), "Water tile polygon did not block at " + str(point))
					_counts["water_polygons"] += 1
			if is_walkable_kind:
				var world_point := layer.to_global(center)
				var section := "original" if world_point.y < ORIGINAL_HEIGHT else "harbor"
				if int(_clear_ground[section]) < 3 and _point_hits(world_point).is_empty():
					_clear_ground[section] += 1


func _point_hits(point: Vector2) -> Array[Dictionary]:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return _space.intersect_point(query, 64)


func _point_hits_body(point: Vector2, expected: Object) -> bool:
	for hit: Dictionary in _point_hits(point):
		if hit.get("collider") == expected:
			return true
	return false


func _inside_polygon(value: Array) -> Vector2:
	# A concave polygon's arithmetic center may lie outside it. The largest
	# triangulated face gives an unambiguous interior physics query point.
	var polygon := PackedVector2Array()
	for vertex: Array in value:
		polygon.append(_point(vertex))
	var indices := Geometry2D.triangulate_polygon(polygon)
	var largest_area := -1.0
	var center := Vector2.ZERO
	for index in range(0, indices.size(), 3):
		var a := polygon[indices[index]]
		var b := polygon[indices[index + 1]]
		var c := polygon[indices[index + 2]]
		var area := absf((b - a).cross(c - a))
		if area > largest_area:
			largest_area = area
			center = (a + b + c) / 3.0
	return center


func _point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))


func _safe_name(value: String) -> String:
	var output := ""
	for character in value:
		if character >= "a" and character <= "z" or character >= "A" and character <= "Z" or character >= "0" and character <= "9" or character == "_":
			output += character
		else:
			output += "_"
	return output if not output.is_empty() else "Generated"


func _finish() -> void:
	var report := {
		"passed": _failures.is_empty(), "checks": _checks, "failures": _failures,
		"counts": _counts, "collision_objects_by_kind": _object_kinds,
		"clear_ground_samples": _clear_ground,
		"original_blockout_sha256": FileAccess.get_sha256(BLOCKOUT_PATH).to_lower(),
		"rendering_verified": false,
		"note": "Headless verification checks live physics and sort structure; it does not produce a rendered screenshot."
	}
	var report_absolute := ProjectSettings.globalize_path(REPORT_PATH)
	DirAccess.make_dir_recursive_absolute(report_absolute.get_base_dir())
	var output := FileAccess.open(report_absolute, FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report, "\t") + "\n")
		output.close()
	if _failures.is_empty():
		print("[PlayableMap check] PASS: %d checks, %s; clear ground %s. Report: %s" % [_checks, JSON.stringify(_counts), JSON.stringify(_clear_ground), report_absolute])
	else:
		printerr("[PlayableMap check] FAIL: %d failures in %d checks. Report: %s" % [_failures.size(), _checks, report_absolute])
	if _map != null:
		_map.free()
	quit(0 if _failures.is_empty() else 1)
