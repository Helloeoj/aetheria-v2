extends SceneTree
## Real imported ore silhouettes, not their much smaller physical bases.
## Run: Godot --headless --path godot_client --script res://scripts/dev_tools/bracken_mine_visuals.gd
const CONTENT := "res://scenes/BrackenMineContent.tscn"
const LAYOUT := "res://Assets/Maps/BrackenMine/layout.json"
const MARKERS := "res://Assets/Maps/BrackenMine/ore-markers.json"
const EXPECTED_ROSTER := {"copper": 3, "tin": 3, "iron": 4, "coal": 5}
## Independently transcribed user dots: changing the placement manifest must not
## quietly approve a different color, a moved reference dot, or an extra rock.
const USER_DOTS := {
	"IronNWNorth": ["iron", Vector2(322, 140)],
	"CoalNWWest": ["coal", Vector2(258, 181)],
	"CoalNWEast": ["coal", Vector2(399, 164)],
	"IronNWSouth": ["iron", Vector2(293, 217)],
	"CopperWestNorth": ["copper", Vector2(195, 444)],
	"CopperWestEast": ["copper", Vector2(284, 480)],
	"TinWestWest": ["tin", Vector2(141, 519)],
	"TinWestSouth": ["tin", Vector2(280, 571)],
	"TinNorthEast": ["tin", Vector2(1223, 225)],
	"CopperNorthEast": ["copper", Vector2(1293, 231)],
	"CoalSETop": ["coal", Vector2(1355, 582)],
	"CoalSEEast": ["coal", Vector2(1402, 638)],
	"CoalSEBottom": ["coal", Vector2(1310, 703)],
	"IronSEWest": ["iron", Vector2(1196, 634)],
	"IronSEBottom": ["iron", Vector2(1375, 687)],
}
const SCENES := {
	"copper": "res://scenes/MapProps/OreNodes/CopperOreFull.tscn",
	"tin": "res://scenes/MapProps/OreNodes/TinOreFull.tscn",
	"iron": "res://scenes/MapProps/OreNodes/IronOreFull.tscn",
	"coal": "res://scenes/MapProps/OreNodes/CoalFull.tscn",
}
const TEXTURES := {
	"copper": "res://Assets/MapTiles/OreNodes/copper-ore-full-south.png",
	"tin": "res://Assets/MapTiles/OreNodes/tin-ore-full-south.png",
	"iron": "res://Assets/MapTiles/OreNodes/iron-ore-full-south.png",
	"coal": "res://Assets/MapTiles/OreNodes/coal-full-south.png",
}
const WALL_CLEARANCE := 2.0
const ORE_CLEARANCE := 4.0
var checks := 0
var failures := 0
var content: Node2D
var floor_boundary := PackedVector2Array()
var exclusions: Array[PackedVector2Array] = []
var ore_nodes: Array[Node2D] = []
var prop_nodes: Array[Node2D] = []
var sprite_count := 0
var ore_clearance_offsets: Array[Vector2i] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Bracken visuals FAIL] ", label)

func vector(pair: Array) -> Vector2:
	return Vector2(pair[0], pair[1])

func polygon(points: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for pair: Array in points:
		result.append(vector(pair))
	return result

func read_json(path: String) -> Dictionary:
	check(FileAccess.file_exists(path), path + " exists")
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(parsed is Dictionary, path + " contains a JSON object")
	return parsed if parsed is Dictionary else {}

func collect_nodes(node: Node) -> void:
	if node is Sprite2D:
		sprite_count += 1
	if node is Node2D and node.has_meta("ore_id"):
		ore_nodes.append(node)
	elif node is Node2D and node.scene_file_path.begins_with("res://scenes/MapProps/BrackenMine/"):
		prop_nodes.append(node)
	for child: Node in node.get_children():
		collect_nodes(child)

func native_basis(node: Node2D) -> bool:
	return node.global_transform.x.is_equal_approx(Vector2.RIGHT) and node.global_transform.y.is_equal_approx(Vector2.DOWN)

func boundary_distance(point: Vector2, boundary: PackedVector2Array) -> float:
	var result := INF
	for index in range(boundary.size()):
		var closest := Geometry2D.get_closest_point_to_segment(point, boundary[index], boundary[(index + 1) % boundary.size()])
		result = minf(result, point.distance_squared_to(closest))
	return sqrt(result)

func silhouette(node: Node2D, ore_id := "") -> Dictionary:
	var sprite := node.get_node_or_null("Footprint/Visual") as Sprite2D
	check(sprite != null and sprite.texture != null, str(node.name) + " has its imported Sprite2D texture")
	if sprite == null or sprite.texture == null:
		return {}
	check(sprite.is_visible_in_tree() and sprite.modulate.a == 1.0 and sprite.self_modulate.a == 1.0, str(node.name) + " displays its visible source alpha")
	check(native_basis(node) and native_basis(sprite), str(node.name) + " retains native 1:1 unrotated pixels")
	check(node.global_position.is_equal_approx(node.global_position.round()) and sprite.global_position.is_equal_approx(sprite.global_position.round()), str(node.name) + " uses integer native coordinates")
	check(sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, str(node.name) + " uses nearest filtering")
	check(not sprite.region_enabled and sprite.hframes == 1 and sprite.vframes == 1 and not sprite.flip_h and not sprite.flip_v, str(node.name) + " displays the complete unflipped source")
	if not ore_id.is_empty():
		check(sprite.texture.resource_path == TEXTURES.get(ore_id, ""), str(node.name) + " reuses its canonical approved texture")
	var image := sprite.texture.get_image()
	check(image != null and not image.is_empty(), str(node.name) + " imported alpha is readable")
	if image == null or image.is_empty():
		return {}
	if image.is_compressed():
		check(image.decompress() == OK, str(node.name) + " imported texture decompresses for alpha inspection")
	check(not image.has_mipmaps(), str(node.name) + " has no mipmaps")
	var used := image.get_used_rect()
	check(used.has_area(), str(node.name) + " has visible alpha")
	var pixels := PackedVector2Array()
	var cells := {}
	var origin := sprite.get_rect().position
	for y in range(used.position.y, used.end.y):
		for x in range(used.position.x, used.end.x):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			var point := content.to_local(sprite.to_global(origin + Vector2(x + 0.5, y + 0.5)))
			pixels.append(point)
			cells[Vector2i(point.floor())] = true
	var center := content.to_local(sprite.to_global(origin + Vector2(used.position) + Vector2(used.size) / 2.0))
	return {"pixels": pixels, "cells": cells, "center": center}

func audit_pixels(node: Node2D, mask: Dictionary, all_ores: Dictionary, props: Dictionary) -> void:
	var outside := 0
	var excluded := 0
	var too_close := 0
	var ore_overlap := 0
	var ore_too_close := 0
	var prop_overlap := 0
	var minimum := INF
	for point: Vector2 in mask.pixels:
		if not Geometry2D.is_point_in_polygon(point, floor_boundary):
			outside += 1
		var distance := boundary_distance(point, floor_boundary)
		for exclusion: PackedVector2Array in exclusions:
			if Geometry2D.is_point_in_polygon(point, exclusion):
				excluded += 1
			distance = minf(distance, boundary_distance(point, exclusion))
		minimum = minf(minimum, distance)
		if distance < WALL_CLEARANCE:
			too_close += 1
		var cell := Vector2i(point.floor())
		if all_ores.get(cell, []).size() > 1:
			ore_overlap += 1
		for offset: Vector2i in ore_clearance_offsets:
			var occupants: Array = all_ores.get(cell + offset, [])
			if occupants.size() > 1 or (occupants.size() == 1 and occupants[0] != str(node.name)):
				ore_too_close += 1
				break
		if props.has(cell):
			prop_overlap += 1
	print("[Bracken silhouette] %s alpha=%d outside_floor=%d exclusions=%d wall_under_2px=%d minimum_clearance=%.3f ore_overlap=%d ore_under_4px=%d prop_overlap=%d" % [node.name, mask.pixels.size(), outside, excluded, too_close, minimum, ore_overlap, ore_too_close, prop_overlap])
	check(outside == 0 and excluded == 0, "%s entire visible alpha lies on authored floor (%d exterior, %d exclusion pixels)" % [node.name, outside, excluded])
	check(too_close == 0, "%s visible alpha keeps >=2px wall clearance (%d close pixels, minimum %.3f)" % [node.name, too_close, minimum])
	check(ore_overlap == 0, "%s visible alpha does not overlap another ore (%d pixels)" % [node.name, ore_overlap])
	check(ore_too_close == 0, "%s visible alpha keeps >=4px clearance from other ore (%d close pixels)" % [node.name, ore_too_close])
	check(prop_overlap == 0, "%s visible alpha does not overlap extracted artwork props (%d pixels)" % [node.name, prop_overlap])

func audit_markers(layout: Dictionary, config: Dictionary, masks: Dictionary) -> void:
	if config.is_empty():
		return
	check(str(config.get("marker_interpretation", "")).to_lower().begins_with("visible alpha rectangle center"), "colored dots specify the visible alpha rectangle center")
	var markers: Dictionary = {}
	var marker_roster := {}
	for marker: Dictionary in config.get("markers", []):
		var id := str(marker.get("id", ""))
		check(not id.is_empty() and not markers.has(id), "marker IDs are nonempty and unique: " + id)
		markers[id] = marker
		var ore_id := str(marker.get("ore_id", ""))
		marker_roster[ore_id] = int(marker_roster.get(ore_id, 0)) + 1
		check(USER_DOTS.has(id), "marker matches a user-provided dot: " + id)
		if USER_DOTS.has(id):
			check(ore_id == USER_DOTS[id][0] and vector(marker.get("dot_center", [0, 0])) == USER_DOTS[id][1], id + " retains the user's literal dot center and ore color")
	check(markers.size() == 15 and marker_roster == EXPECTED_ROSTER, "15 colored markers retain their requested 3 copper / 3 tin / 4 iron / 5 coal roster")
	var assigned := {}
	var actual := {}
	for node: Node2D in ore_nodes:
		actual[str(node.name)] = node
	for entry: Dictionary in layout.get("ores", []):
		var name := str(entry.get("name", ""))
		var id := str(entry.get("user_marker_id", ""))
		check(markers.has(id) and not assigned.has(id), name + " maps to exactly one requested colored dot: " + id)
		assigned[id] = true
		check(actual.has(name), "layout ore is installed: " + name)
		if not markers.has(id) or not actual.has(name) or not masks.has(name):
			continue
		var marker: Dictionary = markers[id]
		var node: Node2D = actual[name]
		var dot := vector(marker.get("dot_center", [0, 0]))
		var adjustment := vector(marker.get("adjustment", [0, 0]))
		var target := dot + adjustment
		check(dot == dot.round() and adjustment == adjustment.round(), id + " retains integer dot coordinates and adjustment")
		check(adjustment == Vector2.ZERO or not str(marker.get("reason", "")).strip_edges().is_empty(), id + " records the wall/prop conflict behind any slight nudge")
		check(str(entry.get("ore_id", "")) == str(marker.get("ore_id", "")) and str(node.get_meta("ore_id", "")) == str(marker.get("ore_id", "")), id + " preserves requested ore color")
		check(masks[name].center.is_equal_approx(target), "%s visible alpha rectangle center matches dot + adjustment (%s, wanted %s)" % [id, masks[name].center, target])
		check(node.position == vector(entry.position) and node.position == target + Vector2(0, 24), id + " installed foot anchor matches layout and visible-center + (0,24)")
	check(layout.get("ores", []).size() == 15 and assigned.size() == 15 and actual.size() == 15, "layout, requested markers and installed ore are one-to-one with no extras")
	for id: String in markers:
		check(assigned.has(id), "requested dot is installed: " + id)

func _run() -> void:
	var layout := read_json(LAYOUT)
	var config := read_json(MARKERS)
	check(ResourceLoader.exists(CONTENT), "installed BrackenMineContent exists")
	if layout.is_empty() or not ResourceLoader.exists(CONTENT):
		finish()
		return
	floor_boundary = polygon(layout.floor_boundary)
	for exclusion: Dictionary in layout.get("exclusions", []):
		exclusions.append(polygon(exclusion.polygon))
	content = load(CONTENT).instantiate()
	root.add_child(content)
	await process_frame
	check(content.transform == Transform2D.IDENTITY, "installed content keeps native 1:1 world coordinates")
	check(vector(layout.get("world_size", [0, 0])) == Vector2(1536, 1024) and layout.get("gameplay_cell_pixels", 0) == 32 and vector(layout.get("gameplay_grid_origin", [-1, -1])) == Vector2.ZERO, "native map size and unchanged 32px movement lattice are preserved")
	collect_nodes(content)
	check(sprite_count == ore_nodes.size() + prop_nodes.size(), "every installed sprite belongs to one approved ore or extracted artwork prop")
	for y in range(-3, 4):
		for x in range(-3, 4):
			var offset := Vector2i(x, y)
			if Vector2(offset).length() < ORE_CLEARANCE:
				ore_clearance_offsets.append(offset)
	check(prop_nodes.size() == 2, "both extracted MineCart and SupplyStack props participate in alpha overlap checks")
	var prop_scenes := {}
	var props := {}
	for prop: Node2D in prop_nodes:
		prop_scenes[prop.scene_file_path] = true
		var mask := silhouette(prop)
		for cell: Vector2i in mask.get("cells", {}):
			props[cell] = true
	check(prop_scenes.size() == 2 and prop_scenes.has("res://scenes/MapProps/BrackenMine/MineCart.tscn") and prop_scenes.has("res://scenes/MapProps/BrackenMine/SupplyStack.tscn"), "alpha overlap checks use both original extracted prop scenes")
	var roster := {}
	var masks := {}
	var all_ores := {}
	for node: Node2D in ore_nodes:
		var ore_id := str(node.get_meta("ore_id", ""))
		roster[ore_id] = int(roster.get(ore_id, 0)) + 1
		check(node.scene_file_path == SCENES.get(ore_id, "") and node.get_meta("ore_state", "") == "full", str(node.name) + " instances its canonical approved full ore scene")
		var mask := silhouette(node, ore_id)
		if mask.is_empty():
			continue
		masks[str(node.name)] = mask
		for cell: Vector2i in mask.cells:
			if not all_ores.has(cell):
				all_ores[cell] = []
			all_ores[cell].append(str(node.name))
	check(ore_nodes.size() == 15 and roster == EXPECTED_ROSTER, "installed ore roster is exactly 15 requested nodes: " + JSON.stringify(roster))
	for node: Node2D in ore_nodes:
		if masks.has(str(node.name)):
			audit_pixels(node, masks[str(node.name)], all_ores, props)
	audit_markers(layout, config, masks)
	print("[Bracken visuals roster] ", JSON.stringify(roster))
	content.queue_free()
	await process_frame
	finish()

func finish() -> void:
	print("[Bracken visuals] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
