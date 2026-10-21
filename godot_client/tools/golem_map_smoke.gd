extends SceneTree
## Godot --headless --path godot_client --script res://tools/golem_map_smoke.gd

var _failures: Array[String] = []
const CRISP_MATERIAL := "res://Assets/Maps/GolemKingdom/Rendering/CrispEnvironment.tres"

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
		push_error(description)

func _blocked(space: PhysicsDirectSpaceState2D, point: Vector2) -> bool:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(24, 24)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, point)
	query.collision_mask = 1
	query.collide_with_areas = false
	return not space.intersect_shape(query, 1).is_empty()

func _nearest_filter(item: CanvasItem) -> bool:
	var ancestor: Node = item
	while ancestor != null:
		if ancestor is CanvasItem and ancestor.texture_filter != CanvasItem.TEXTURE_FILTER_PARENT_NODE:
			return ancestor.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
		ancestor = ancestor.get_parent()
	return false

func _material_scope(node: Node, allowed: Dictionary, material: ShaderMaterial) -> int:
	var count := 0
	if node is CanvasItem and node.material == material:
		count = 1
		_check(allowed.has(node.get_instance_id()), "Scenery shader is absent from actors, UI and non-art nodes: " + str(node.get_path()))
	for child: Node in node.get_children():
		count += _material_scope(child, allowed, material)
	return count

func _run() -> void:
	var packed := load("res://scenes/GolemKingdom.tscn") as PackedScene
	_check(packed != null, "Dungeon runtime scene loads")
	if packed == null:
		quit(1)
		return
	var map := packed.instantiate() as Node2D
	root.add_child(map)
	await physics_frame
	await physics_frame
	var content := map.get_node("GolemKingdomContent") as Node2D
	var crisp := load(CRISP_MATERIAL) as ShaderMaterial
	_check(crisp != null and crisp.shader != null, "Reviewed scenery material and shader load")
	if crisp == null or crisp.shader == null:
		map.queue_free()
		quit(1)
		return
	_check(crisp.shader.resource_path == "res://Assets/Maps/GolemKingdom/Rendering/CrispEnvironment.gdshader", "Shared material uses the installed reviewed scenery shader")
	var expected_parameters := {
		"edge_strength": 0.65, "ink_strength": 1.0, "ink_threshold": 0.4,
		"palette_strength": 1.0, "denoise_strength": 1.0, "ink_hardness": 1.0
	}
	for parameter: String in expected_parameters:
		_check(is_equal_approx(float(crisp.get_shader_parameter(parameter)), float(expected_parameters[parameter])), "Reviewed scenery shader setting: " + parameter)
	var lookup := crisp.get_shader_parameter("color_lookup") as Texture2D
	_check(lookup != null and lookup.get_size() == Vector2(1024, 32), "Balanced palette lookup retains its 32-cube atlas dimensions")
	_check(lookup != null and lookup.resource_path == "res://Assets/Maps/GolemKingdom/Rendering/ColorLookup512.png", "Shared material uses the reviewed balanced 512-color lookup")
	_check(crisp.shader.code.contains("color_lookup : filter_nearest, repeat_disable"), "Palette lookup uses nearest sampling without repeating")
	var material_targets: Dictionary = {}
	_check(content.scale == Vector2(3, 3), "Logical scene coordinates retain the original integer 3x scale")
	_check(int(content.get_meta("art_detail_scale", 0)) == 4, "Scene selects the restored 4x art detail")
	_check(content.get_meta("source_size") == Vector2i(1254, 1254), "Logical source coordinates remain 1254 square")
	_check(content.get_meta("art_detail_size") == Vector2i(5016, 5016), "Restored source detail is 5016 square")
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Assets/Maps/GolemKingdom/source-layer-manifest.json"))
	var source_objects: Dictionary = {}
	for definition: Dictionary in source.objects:
		source_objects[String(definition.id).replace("-", "_")] = definition
	var terrain_layers := 0
	var cutout_count := 0
	var base_collisions := 0
	for child: Node in content.get_children():
		if child is TileMapLayer:
			terrain_layers += 1
			material_targets[child.get_instance_id()] = true
			_check(child.material == crisp, "Terrain uses the same reviewed shared scenery material")
			_check(_nearest_filter(child), "Terrain source textures retain nearest sampling")
			_check(child.scale == Vector2(0.25, 0.25), "Terrain resolves 4x detail within its original footprint")
			_check(child.tile_set.tile_size == Vector2i(128, 128), "Terrain art patches have 128 source pixels")
			var atlas := child.tile_set.get_source(0) as TileSetAtlasSource
			_check(atlas != null and atlas.texture_region_size == Vector2i(128, 128), "Terrain atlas regions have 128 source pixels")
			_check(atlas.texture.get_size() == Vector2(5120, 5120), "Restored terrain uses the padded 5120px atlas")
			var first_cell: Vector2 = child.to_global(child.map_to_local(Vector2i.ZERO))
			var next_cell: Vector2 = child.to_global(child.map_to_local(Vector2i.RIGHT))
			_check(first_cell.is_equal_approx(Vector2(48, 48)), "Terrain first-cell world center remains unchanged")
			_check((next_cell - first_cell).is_equal_approx(Vector2(96, 0)), "Terrain world cell step remains 96px")
			_check(child.get_used_cells().size() > 0, "Terrain layer has paintable cells")
			_check(child.get_used_rect().end.x <= 40 and child.get_used_rect().end.y <= 40, "Terrain atlas coordinates remain source aligned")
		elif child.get_node_or_null("Artwork") != null:
			cutout_count += 1
			var definition: Dictionary = source_objects.get(String(child.name), {})
			_check(not definition.is_empty(), "Object retains its original source identity")
			if definition.is_empty():
				continue
			var artwork := child.get_node("Artwork") as Sprite2D
			material_targets[artwork.get_instance_id()] = true
			_check(artwork.material == crisp, "Object uses the same reviewed shared scenery material")
			_check(_nearest_filter(artwork), "Object source textures retain nearest sampling")
			var bounds: Array = definition.bounds
			var foot: Array = definition.foot
			var foot_local: Array = definition.foot_local
			_check(child.position == Vector2(float(foot[0]), float(foot[1])), "Object root stays at its original sorting feet")
			_check(artwork.position == -Vector2(float(foot_local[0]), float(foot_local[1])), "Object artwork keeps its original feet offset")
			_check(artwork.scale == Vector2(0.25, 0.25), "Object resolves 4x detail within its original footprint")
			_check(artwork.global_scale.is_equal_approx(Vector2(0.75, 0.75)), "Scenery texel density matches the 0.75-world-pixel character texel")
			_check(artwork.texture.get_size() == Vector2(float(bounds[2]), float(bounds[3])) * 4.0, "Object texture dimensions are exactly four times the original crop")
			_check(artwork.global_position == Vector2(float(bounds[0]), float(bounds[1])) * 3.0, "Object artwork world origin remains unchanged")
			_check(artwork.texture.resource_path.begins_with("res://Assets/Maps/GolemKingdom/Detail4x/Objects/"), "Object uses the restored detail sibling")
			var footprint := child.get_node_or_null("Footprint")
			if footprint != null:
				base_collisions += footprint.get_child_count()
			var expected_z := -12 if child.get_meta("source_layer") in ["Bridges", "Stairs"] else 0
			# Additional doorway steps intentionally share the walkable ground plane.
			_check(child.z_index == expected_z or child.z_index == -12, "Whole objects sort at their feet")
	_check(terrain_layers == 5, "Five independent terrain TileMapLayers")
	_check(cutout_count == 249, "All 249 approved foreground objects remain independent")
	_check(material_targets.size() == 254, "Only five terrain layers and 249 artwork sprites are shader targets")
	_check(_material_scope(map, material_targets, crisp) == 254, "Exactly 254 scenery nodes share the shader")
	_check(base_collisions == 203, "All 203 original object base collision shapes remain")
	_check(content.get_node("TerrainCollision").get_child_count() == 1479, "All 1479 original terrain collision rectangles remain")
	var game: Node = map.get_node("Combat")
	var player_visual: ActorSprite = game.actor_sprites.get(game.player.entity_id)
	_check(player_visual != null and player_visual.material != crisp and player_visual.animated_sprite.material != crisp, "Character root and animated sprite are outside the scenery shader")
	_check(_nearest_filter(player_visual.animated_sprite), "Character texture sampling remains nearest")
	_check(player_visual.animated_sprite.scale == Vector2(0.75, 0.75), "Character display size remains unchanged")
	_check(game.map_width == 3762.0 and game.map_height == 3762.0, "Dungeon has independent movement bounds")
	_check(game.initial_spawn_id == "EastCave", "Direct scene play uses safe eastern spawn")
	var spawn := map.get_node("SpawnPoints/EastCave") as Marker2D
	var exit := map.get_node("Combat/EastCaveExit")
	_check(spawn.global_position == Vector2(3531, 1617), "Eastern arrival marker stays in its original world coordinates")
	_check(exit.global_position == Vector2(3678, 1422), "Eastern exit marker stays in its original world coordinates")
	_check(exit.approach_position() == Vector2(3606, 1518), "Exit approach remains unchanged")
	_check(exit.destination_spawn_id == "GolemCaveReturn", "Exit returns to the matching overworld marker")
	var camera := map.get_node("MapCamera") as Camera2D
	_check(camera.limit_left == 0 and camera.limit_top == 0 and camera.limit_right == 3762 and camera.limit_bottom == 3762, "Camera retains the original world bounds")
	var space := map.get_world_2d().direct_space_state
	_check(not _blocked(space, spawn.global_position), "Eastern arrival fits the actual 24px player body")
	_check(not _blocked(space, exit.approach_position()), "Eastern exit approach fits the player body")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Assets/Maps/GolemKingdom/manifest.json"))
	var landmarks: Dictionary = manifest.landmarks_source
	for label: String in landmarks:
		var point: Array = landmarks[label]
		_check(not _blocked(space, Vector2(float(point[0]), float(point[1])) * 3.0), "Walkable gameplay landmark: " + label)
	for source_point: Vector2 in [Vector2(1048, 654), Vector2(555, 80), Vector2(340, 620), Vector2(18, 20)]:
		_check(_blocked(space, source_point * 3.0), "Lava or cavern wall blocks movement at " + str(source_point))
	if _failures.is_empty():
		print("GOLEM MAP PASS: crisp material on exactly 254 scenery nodes, actors/UI excluded, restored 4x detail, unchanged footprints/markers/bounds, player-size landmark clearance and lava collisions.")
	else:
		print("GOLEM MAP FAIL: ", _failures)
	map.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)
