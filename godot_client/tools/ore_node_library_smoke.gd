extends SceneTree
## Non-destructive palette/placement check. Does not save or modify any world.

const MANIFEST := "res://Assets/MapTiles/OreNodes/manifest.json"
const WORLD_PALETTE := "res://Assets/Tilesets/WorldMapObjects.tres"
const LOCAL_PALETTE := "res://Assets/Tilesets/OreNodes.tres"
const COLLECTION := "res://Assets/Tilesets/OreNodeSceneTiles.tres"
const ORDER := ["copper", "tin", "iron", "coal", "silver", "gold", "mithril", "adamantite", "runite", "blackstone"]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("[OreNodeLibrary] FAIL: ", label)

func _run() -> void:
	if not FileAccess.file_exists(MANIFEST):
		check(false, "The installed ore prop manifest exists")
		_finish()
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not data is Dictionary:
		check(false, "The ore prop manifest is a dictionary")
		_finish()
		return
	var entries: Array = data.get("entries", [])
	check(entries.size() == 10, "Ten ore/catalyst designs are available")
	var world := load(WORLD_PALETTE) as TileSet
	var local := load(LOCAL_PALETTE) as TileSet
	var source := load(COLLECTION) as TileSetScenesCollectionSource
	if world == null or local == null or source == null:
		check(false, "All editor palettes load as native Godot resources")
		_finish()
		return
	check(world.has_source(0) and world.has_source(1), "Original and wilderness palette sources remain available")
	check(world.has_source(2) and world.get_source(2) == source, "World palette exposes the reusable ore collection at source2")
	check(local.get_source_count() == 1 and local.get_source(0) != source, "Standalone palette owns a separate collection without detaching the world palette")
	for tile_id in 20:
		var local_source := local.get_source(0) as TileSetScenesCollectionSource
		check(local_source.get_scene_tile_scene(tile_id) == source.get_scene_tile_scene(tile_id), "Both palettes expose the same stable named prop mappings")
	check(world.tile_size == Vector2i(32, 32) and local.tile_size == Vector2i(32, 32), "Placement retains the existing32px grid")
	check(source.get_scene_tiles_count() == 20, "Twenty named full/depleted scene stamps are available")
	var repository := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
	for index in entries.size():
		var entry: Dictionary = entries[index]
		check(entry.get("id") == ORDER[index], "Material order remains discoverable and stable")
		var expected_anchor: Array = entry.get("anchor", [])
		var pair: Array[Node2D] = []
		for state: String in ["full", "depleted"]:
			var variant: Dictionary = entry.get(state, {})
			var tile_id := int(variant.get("tile_id", -1))
			check(tile_id == index * 2 + (1 if state == "depleted" else 0), "State pair has stable adjacent scene IDs")
			var packed := source.get_scene_tile_scene(tile_id)
			check(packed != null and packed.resource_path == variant.get("scene"), "Palette stamp references its named whole-object scene")
			if packed == null:
				continue
			var node := packed.instantiate() as Node2D
			if node == null:
				check(false, "The prop can be instantiated")
				continue
			pair.append(node)
			var foot := node.get_node_or_null("Footprint") as StaticBody2D
			var visual := node.get_node_or_null("Footprint/Visual") as Sprite2D
			check(node.get_script() == null and node.y_sort_enabled and node.z_index == 0 and node.scale == Vector2.ONE, "Prop has native-scale feet sorting without gameplay behavior")
			check(node.get_meta("ore_id", "") == entry.id and node.get_meta("ore_state", "") == state, "Material and visual state are identifiable")
			check(foot != null and visual != null, "The whole prop includes artwork and a physical base")
			if foot == null or visual == null:
				continue
			check(foot.position == Vector2.ZERO and foot.collision_layer == 1 and foot.collision_mask == 0 and foot.is_in_group("world_solid"), "Base follows existing static-world collision conventions")
			check(visual.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and node.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Both prop and imported visual explicitly keep nearest filtering")
			check(not visual.centered and visual.position == -Vector2(float(expected_anchor[0]), float(expected_anchor[1])), "Authored foot anchor is retained")
			check(visual.texture != null and visual.texture.get_size() == Vector2(96, 96) and visual.texture.resource_path == variant.get("texture"), "The imported native96px texture is used without resizing")
			var texture_path: String = variant.get("texture", "")
			var original := repository.path_join("art_sources/ore-nodes").path_join(texture_path.get_file())
			check(FileAccess.get_sha256(texture_path) == FileAccess.get_sha256(original), "Installed texture is byte-identical to the approved source PNG")
			check(variant.get("source_sha256", "") == FileAccess.get_sha256(texture_path), "Manifest checksum matches the current source artwork")
			var settings := ConfigFile.new()
			check(settings.load(texture_path + ".import") == OK and settings.get_value("params", "compress/mode", -1) == 0 and not settings.get_value("params", "mipmaps/generate", true), "Texture import is lossless without mipmaps")
			var polygons := foot.find_children("*", "CollisionPolygon2D", true, false)
			check(polygons.size() == 2, "Main rock and companion rock each have a base collider")
			for polygon: CollisionPolygon2D in polygons:
				check(not polygon.disabled and polygon.polygon.size() >= 3, "Physical bases have valid authored polygons")
				for point: Vector2 in polygon.polygon:
					check(absf(point.x) < 48 and absf(point.y) < 40, "Collision covers only the base, not the transparent96px canvas")
		if pair.size() == 2:
			check(pair[0].get_node("Footprint/Visual").position == pair[1].get_node("Footprint/Visual").position, "Changing visual state does not shift the node")
			var first := pair[0].get_node("Footprint").find_children("*", "CollisionPolygon2D", true, false)
			var second := pair[1].get_node("Footprint").find_children("*", "CollisionPolygon2D", true, false)
			for i in mini(first.size(), second.size()):
				check(first[i].polygon == second[i].polygon, "Full/depleted state swaps retain physical footprint")
		for node: Node2D in pair:
			node.free()
	_check_rebuild_retention(source)
	await _check_native_placement(world)
	_finish()

func _check_rebuild_retention(source: TileSetScenesCollectionSource) -> void:
	var builder: Script = load("res://tools/merge_wilderness_into_world.gd")
	var probe := TileSet.new()
	probe.tile_size = Vector2i(32, 32)
	var original := TileSetScenesCollectionSource.new()
	var wilderness := TileSetScenesCollectionSource.new()
	probe.add_source(original, 0)
	probe.add_source(wilderness, 1)
	check(builder.ensure_ore_source(probe), "A future deliberate rebuild retains the ore collection")
	check(probe.get_source(0) == original and probe.get_source(1) == wilderness and probe.get_source(2) != source, "Registration preserves existing sources and never takes ownership of a loaded world's collection")
	var live_world := load(WORLD_PALETTE) as TileSet
	check(live_world.has_source(2) and live_world.get_source(2) == source, "Registering another palette does not detach ore stamps from a loaded world")
	for tile_id in 20:
		var registered := probe.get_source(2) as TileSetScenesCollectionSource
		check(registered.get_scene_tile_scene(tile_id) == source.get_scene_tile_scene(tile_id), "Rebuilt palette retains each canonical PackedScene mapping")
	check(builder.ensure_ore_source(probe) and probe.get_source_count() == 3, "Repeated palette registration is idempotent")
	var occupied := TileSet.new()
	occupied.add_source(original, 0)
	var conflicting := TileSetScenesCollectionSource.new()
	occupied.add_source(conflicting, 2)
	check(not builder.ensure_ore_source(occupied) and occupied.get_source(2) == conflicting, "An occupied source ID is rejected without overwriting user resources")
	check(not builder.ensure_ore_source(probe, "res://missing-ore-source.tres"), "A missing library fails quietly before any save")
	check(not builder.ensure_ore_source(null), "A missing object palette is handled safely")

func _check_native_placement(palette: TileSet) -> void:
	var container := Node2D.new()
	container.y_sort_enabled = true
	var layer := TileMapLayer.new()
	layer.name = "OrePlacement"
	layer.tile_set = palette
	layer.y_sort_enabled = true
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.add_child(layer)
	layer.owner = container
	root.add_child(container)
	for i in 10:
		layer.set_cell(Vector2i(i * 3, 0), 2, Vector2i.ZERO, i * 2)
		layer.set_cell(Vector2i(i * 3, 4), 2, Vector2i.ZERO, i * 2 + 1)
	await _settle()
	check(layer.get_child_count() == 20, "Native TileMap painting instantiates every complete prop")
	for child: Node2D in layer.get_children():
		var cell := layer.local_to_map(child.position)
		check(child.position == layer.map_to_local(cell), "Stamped foot anchor snaps to the existing placement grid")
		check(not _actor_blocked(layer, child.global_position + Vector2(0, 32)), "A24px actor has a clear south approach at compact96px spacing")
	layer.erase_cell(Vector2i.ZERO)
	await _settle()
	check(layer.get_child_count() == 19 and not _actor_blocked(layer, Vector2(6, 1)), "Erasing a stamp removes its artwork and base collision")
	layer.set_cell(Vector2i.ZERO, 2, Vector2i.ZERO, 0)
	await _settle()
	var packed := PackedScene.new()
	check(packed.pack(container) == OK, "A map containing ore stamps can be packed normally")
	container.free()
	var restored := packed.instantiate() as Node2D
	root.add_child(restored)
	await _settle()
	var restored_layer := restored.get_node("OrePlacement") as TileMapLayer
	check(restored_layer.get_used_cells().size() == 20 and restored_layer.get_child_count() == 20, "Saved/copied map instances recreate all20 whole-object stamps")
	# Four-cell spacing reserves a full actor-width route between bases.
	restored_layer.clear()
	restored_layer.set_cell(Vector2i(0, 0), 2, Vector2i.ZERO, 2)
	restored_layer.set_cell(Vector2i(4, 0), 2, Vector2i.ZERO, 0)
	await _settle()
	for y in range(-64, 81, 8):
		check(not _actor_blocked(restored_layer, Vector2(80, y)), "A24px actor can pass between nodes along a128px-spaced route")
	restored.free()

func _actor_blocked(layer: TileMapLayer, position: Vector2) -> bool:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(24, 24)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0, position)
	query.collision_mask = 1
	return not layer.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()

func _settle() -> void:
	for frame in 3:
		await process_frame
	await physics_frame
	await process_frame

func _finish() -> void:
	print("[OreNodeLibrary] ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
