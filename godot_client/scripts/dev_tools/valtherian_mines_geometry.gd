extends SceneTree
## Actual passive content physics, all floor centers and shared-grid edges.
## Ore-occupied centers are classified, not falsely called traversable floor.
const CONTENT := "res://scenes/ValtherianMinesContent.tscn"
const LAYOUT := "res://Assets/Maps/ValtherianMines/layout.json"
const CONTRACT := "res://Assets/Maps/ValtherianMines/worldbuilding.json"
const SIZE := Vector2(6144, 3328)
const BODY := Vector2(24, 24)
const EXPECTED := {"blackstone":12, "coal":7, "mithril":4, "adamantite":2, "iron":4}
var checks := 0
var failures: Array[String] = []
var content: Node2D
var grid := HiddenGrid.new()
var body := RectangleShape2D.new()
var clear_cache := {}
var layout: Dictionary
var contract: Dictionary
var floor_cells := {}
var clear_cells := {}
var reached := {}
var output_dir := ""
var metrics := {}
var loaded_scene_sha := ""
var loaded_layout_sha := ""

func _initialize() -> void:
	output_dir = OS.get_user_data_dir().path_join("valtherian-map-audit")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_dir = argument.trim_prefix("--output=")
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		if failures.size() <= 30:
			printerr("[Valtherian geometry FAIL] ", label)

func vector(pair: Array) -> Vector2:
	return Vector2(pair[0], pair[1])

func sim(world: Vector2) -> Vector2:
	return Vector2(world.x / 32.0, (SIZE.y - world.y) / 32.0)

func pixel(point: Vector2) -> Vector2:
	return Vector2(point.x * 32.0, SIZE.y - point.y * 32.0)

func grid_cell(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x, -cell.y - 1)

func world_cell(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x, -cell.y - 1)

func body_query(world: Vector2, shape: Shape2D = null) -> PhysicsShapeQueryParameters2D:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = body if shape == null else shape
	query.transform = Transform2D(0, content.to_global(world))
	query.collision_mask = 1
	query.collide_with_areas = false
	query.margin = 0.08
	return query

func point_clear(point: Vector2) -> bool:
	var world := pixel(point)
	if not clear_cache.has(world):
		clear_cache[world] = content.get_world_2d().direct_space_state.intersect_shape(body_query(world), 1).is_empty()
	return bool(clear_cache[world])

func sweep_clear(start: Vector2, finish: Vector2) -> bool:
	var query := body_query(pixel(start))
	query.motion = content.to_global(pixel(finish)) - query.transform.origin
	var fractions := content.get_world_2d().direct_space_state.cast_motion(query)
	return fractions.size() == 2 and fractions[0] >= 0.99999

func flood(start: Vector2i, removed := {}) -> Dictionary:
	var found := {}
	var pending: Array[Vector2i] = [start]
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_back()
		if found.has(cell) or removed.has(cell) or not clear_cells.has(cell):
			continue
		found[cell] = true
		for direction: Vector2i in HiddenGrid.DIRECTIONS:
			var neighbor := cell + direction
			if not found.has(neighbor) and not removed.has(neighbor) and clear_cells.has(neighbor) and grid.connected(cell, neighbor):
				pending.append(neighbor)
	return found

func _run() -> void:
	body.size = BODY
	check(ResourceLoader.exists(CONTENT), "actual content is generated")
	check(FileAccess.file_exists(LAYOUT), "actual layout exists")
	check(FileAccess.file_exists(CONTRACT), "actual placement contract exists")
	if not failures.is_empty():
		finish()
		return
	loaded_scene_sha = FileAccess.get_sha256(CONTENT)
	loaded_layout_sha = FileAccess.get_sha256(LAYOUT)
	layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	contract = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT))
	content = (load(CONTENT) as PackedScene).instantiate()
	root.add_child(content)
	await physics_frame
	await physics_frame
	check(content.transform == Transform2D.IDENTITY, "actual map root retains world scale")
	check(content.get_meta("gameplay_grid_origin", Vector2.INF) == Vector2.ZERO, "shared grid origin remains0,0")
	check(layout.gameplay_cell_pixels == 32 and vector(layout.world_size) == SIZE, "world and32px grid match approved plan")
	for pair: Array in layout.floor_cells:
		floor_cells[Vector2i(pair[0], pair[1])] = true
	check(floor_cells.size() == 5498, "all5498 approved floor cells retained")
	var floor_layer := content.get_node_or_null("NativeFloor") as TileMapLayer
	check(floor_layer != null, "actual native floor layer exists")
	if floor_layer != null:
		check(floor_layer.get_used_cells().size() == floor_cells.size(), "artwork contains every declared floor cell")
		check(floor_layer.tile_set.tile_size == Vector2i(128,128) and floor_layer.global_scale == Vector2(0.25,0.25), "native128px artwork gives32world pixels")
		check(floor_layer.to_global(floor_layer.map_to_local(Vector2i.ZERO)).is_equal_approx(Vector2(16,16)), "actual floor aligns to shared grid centers")
		for cell: Vector2i in floor_layer.get_used_cells():
			check(floor_cells.has(cell), "no floor artwork outside authored cell " + str(cell))
	var boundary := content.get_node("CaveBoundary") as StaticBody2D
	check(boundary.collision_layer == 1, "real cave boundary blocks world layer1")
	check(boundary.get_child_count() == layout.void_rects.size(), "all actual continuous void rectangles exist")
	for i in range(layout.void_rects.size()):
		var rect: Array = layout.void_rects[i]
		var actual := boundary.get_node("RockSolid%04d" % i) as CollisionShape2D
		check(actual.shape is RectangleShape2D and not actual.disabled and actual.shape.size == Vector2(rect[2],rect[3]) and actual.position == Vector2(rect[0]+rect[2]*0.5,rect[1]+rect[3]*0.5), "solid boundary rectangle " + str(i))
	grid.configure(Vector2(0,104), Vector2.ZERO, Vector2(192,104))
	grid.point_clear = point_clear
	grid.sweep_clear = sweep_clear
	var blocked_floor := 0
	var unexplained_blocked: Array = []
	var exterior_samples := 0
	var exterior_gaps: Array = []
	for y in range(104):
		for x in range(192):
			var cell := Vector2i(x,y)
			var physical := Vector2(cell) * 32 + Vector2(16,16)
			var clear := grid.walkable(grid_cell(cell))
			if floor_cells.has(cell):
				if clear:
					clear_cells[grid_cell(cell)] = true
				else:
					blocked_floor += 1
					for hit: Dictionary in content.get_world_2d().direct_space_state.intersect_shape(body_query(physical), 8):
						var collider := hit.collider as Node
						if collider == null or not str(content.get_path_to(collider)).begins_with("Ores/"):
							unexplained_blocked.append([x,y])
			else:
				exterior_samples += 1
				if clear:
					exterior_gaps.append([x,y])
	check(unexplained_blocked.is_empty(), "floor centers are obstructed only by declared canonical ores")
	check(exterior_gaps.is_empty(), "every exterior cell center is physically solid")
	var arrival := Vector2(6032,2064)
	for anchor: Dictionary in contract.anchors:
		if anchor.id == "arrival":
			arrival = vector(anchor.point)
	check(point_clear(sim(arrival)), "exact entrance arrival admits24px body")
	var start: Variant = grid.recovery_cell(sim(arrival))
	check(start != null, "arrival joins the actual shared grid")
	if start == null:
		finish()
		return
	reached = flood(start)
	check(reached.size() == clear_cells.size(), "all physically clear floor centers connect to arrival")
	var unsafe_edges := 0
	var safe_diagonals := 0
	var rejected_corners := 0
	for cell: Vector2i in clear_cells:
		for direction: Vector2i in HiddenGrid.DIRECTIONS:
			var next := cell + direction
			if not clear_cells.has(next):
				continue
			var connected := grid.connected(cell,next)
			if connected and not sweep_clear(grid.center(cell),grid.center(next)):
				unsafe_edges += 1
			if direction.x != 0 and direction.y != 0:
				var cardinal_clear := grid.connected(cell,cell+Vector2i(direction.x,0)) and grid.connected(cell,cell+Vector2i(0,direction.y)) and grid.connected(cell+Vector2i(direction.x,0),next) and grid.connected(cell+Vector2i(0,direction.y),next)
				if not cardinal_clear:
					rejected_corners += 1
					check(not connected, "shared grid prevents diagonal corner cutting")
				elif connected:
					safe_diagonals += 1
	check(unsafe_edges == 0 and safe_diagonals > 100 and rejected_corners > 0, "all actual edges preserve body sweeps and corner protection")
	var roster := {"blackstone":0,"coal":0,"mithril":0,"adamantite":0,"iron":0}
	check(content.get_node("Ores").get_child_count() == 29 and layout.ores.size() == 29, "exactly29 marked ore props installed")
	for ore: Dictionary in layout.ores:
		var node := content.get_node("Ores/" + str(ore.name)) as Node2D
		check(node != null and node.scene_file_path == ore.scene and node.scale == Vector2.ONE and node.position == vector(ore.position), str(ore.id) + " retains canonical scene, native scale and authored position")
		check(node.get_script() == null and not node.is_in_group("mining_deposit"), str(ore.id) + " adds no skill mechanics")
		roster[str(ore.ore)] += 1
		var approach := vector(ore.approach_world_xy)
		check(point_clear(sim(approach)), str(ore.id) + " exact approach admits actual body")
		check(reached.has(grid.cell_at(sim(approach))), str(ore.id) + " exact approach joins connected room")
		var path := grid.path(sim(arrival),sim(approach))
		check(not path.is_empty(), str(ore.id) + " shared-grid route is conclusive")
		if not path.is_empty():
			check(grid.clear_segment(path[-1],sim(approach)), str(ore.id) + " final body sweep reaches exact approach")
	check(roster == EXPECTED, "roster matches all five user colors")
	check(layout.decor_props.size() == 8 and content.get_node("Decor").get_child_count() == 8, "all8 warm supports are separate placed props")
	for decor: Dictionary in layout.decor_props:
		var support := content.get_node("Decor/"+str(decor.name)) as Node2D
		var visual := support.get_node("Visual") as Sprite2D
		check(support.scene_file_path == decor.scene and support.position == vector(decor.position), str(decor.name)+" matches authored whole prop")
		check(not support.y_sort_enabled and visual.scale == Vector2(0.0625,0.0625) and visual.texture.get_size() == Vector2(1254,1254), str(decor.name)+" retains native group, density and source")
	var lane_checks := audit_lanes()
	var gate_checks := audit_progression(start)
	metrics = {"authored_floor_cells":floor_cells.size(),"body_clear_floor_cells":clear_cells.size(),"ore_occupied_floor_centers":blocked_floor,
		"reachable_clear_centers":reached.size(),"unexplained_blocked_centers":unexplained_blocked,"outside_centers_tested":exterior_samples,
		"outside_escape_centers":exterior_gaps,"safe_diagonals":safe_diagonals,"rejected_diagonal_corners":rejected_corners,
		"unsafe_swept_edges":unsafe_edges,"ore_roster":roster,"exact_ore_approaches":layout.ores.size(),"reserved_lane_checks":lane_checks,"reserved_lane_numeric_inset_pixels":0.2,"progression_checks":gate_checks,"separate_warm_supports":layout.decor_props.size()}
	finish()

func audit_lanes() -> int:
	var count := 0
	for route: Dictionary in contract.routes:
		var lane := RectangleShape2D.new()
		# Exactly192/128px touches the adjacent solid boundary. Inset only the
		# query by0.2px to offset the physics engine's contact tolerance; the
		# actual floor rectangles and declared reserved widths stay unchanged.
		lane.size = Vector2.ONE * (float(route.width) - 0.2)
		var points: Array = route.points
		for i in range(points.size()):
			var point := vector(points[i])
			check(content.get_world_2d().direct_space_state.intersect_shape(body_query(point,lane),1).is_empty(), str(route.id) + " retains declared width at " + str(point))
			count += 1
			if i > 0:
				var query := body_query(vector(points[i-1]),lane)
				query.motion = point-vector(points[i-1])
				var fractions := content.get_world_2d().direct_space_state.cast_motion(query)
				check(fractions.size() == 2 and fractions[0] >= 0.99999, str(route.id) + " retains declared width along segment " + str(i))
				count += 1
	return count

func audit_progression(start: Vector2i) -> int:
	var terminal := grid_cell(Vector2i(16,24))
	var gates := [{"id":"early","x":162,"y0":60,"y1":68},{"id":"middle","x":110,"y0":44,"y1":52},{"id":"late","x":58,"y0":36,"y1":44}]
	for gate: Dictionary in gates:
		var removed := {}
		for y in range(gate.y0,gate.y1):
			removed[grid_cell(Vector2i(gate.x,y))] = true
		check(not flood(start,removed).has(terminal), str(gate.id) + " cut has no progression bypass")
	var necks := [{"id":"east_upper_branch","row":56,"left":169,"right":176,"terminal":Vector2i(178,16)},
		{"id":"upper_east_branch","row":37,"left":137,"right":144,"terminal":Vector2i(124,14)},
		{"id":"lower_east_branch","row":61,"left":113,"right":120,"terminal":Vector2i(132,90)},
		{"id":"upper_west_branch","row":56,"left":81,"right":88,"terminal":Vector2i(98,12)},
		{"id":"lower_west_branch","row":50,"left":45,"right":52,"terminal":Vector2i(32,90)}]
	for branch: Dictionary in necks:
		var removed := {}
		for x in range(branch.left,branch.right):
			removed[grid_cell(Vector2i(x,branch.row))] = true
		var found := flood(start,removed)
		check(not found.has(grid_cell(branch.terminal)) and found.has(terminal), str(branch.id) + " remains a separate side branch")
		for other: Dictionary in necks:
			if other.id != branch.id:
				check(found.has(grid_cell(other.terminal)), str(branch.id) + " cut preserves " + str(other.id))
	return gates.size() + necks.size()

func finish() -> void:
	DirAccess.make_dir_recursive_absolute(output_dir)
	if not loaded_scene_sha.is_empty():
		check(loaded_scene_sha == FileAccess.get_sha256(CONTENT) and loaded_layout_sha == FileAccess.get_sha256(LAYOUT), "source scene/layout stayed unchanged during audit")
	var report := {"checks":checks,"failure_count":failures.size(),"failures":failures,"metrics":metrics,
		"scene_sha256":loaded_scene_sha,"layout_sha256":loaded_layout_sha,
		"scope":"Actual Valtherian passive content physics/shared grid only; visual and travel approval remain separate"}
	var file := FileAccess.open(output_dir.path_join("valtherian-mine-geometry-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	print("[Valtherian geometry] ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
