extends SceneTree
## Installed mine physics and shared HiddenGrid regression. No pixel-color inference.
const SIZE := Vector2(1536, 1024)
const BODY := Vector2(24, 24)
var checks := 0
var failures := 0
var content: Node2D
var grid := HiddenGrid.new()
var shape := RectangleShape2D.new()
var layout: Dictionary

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Bracken geometry FAIL] ", label)

func sim(pixel: Vector2) -> Vector2:
	return Vector2(pixel.x / 32.0, (SIZE.y - pixel.y) / 32.0)

func pixel(point: Vector2) -> Vector2:
	return Vector2(point.x * 32.0, SIZE.y - point.y * 32.0)

func vector(pair: Array) -> Vector2:
	return Vector2(pair[0], pair[1])

func query_at(point: Vector2) -> PhysicsShapeQueryParameters2D:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, content.to_global(pixel(point)))
	query.collision_mask = 1
	query.collide_with_areas = false
	query.margin = 0.08
	return query

func point_clear(point: Vector2) -> bool:
	return content.get_world_2d().direct_space_state.intersect_shape(query_at(point), 1).is_empty()

func sweep_clear(start: Vector2, finish: Vector2) -> bool:
	var query := query_at(start)
	query.motion = content.to_global(pixel(finish)) - query.transform.origin
	var fractions := content.get_world_2d().direct_space_state.cast_motion(query)
	return fractions.size() == 2 and fractions[0] >= 0.99999

func polygon(points: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for pair: Array in points:
		result.append(vector(pair))
	return result

func checked_route(start: Vector2, goal: Vector2, label: String, allowed := Callable()) -> PackedVector2Array:
	var route := grid.path(sim(start), sim(goal), 0.0, allowed)
	check(not route.is_empty(), label + " has a 32px center route")
	if route.is_empty():
		return route
	check(grid.clear_segment(sim(start), route[0]), label + " joins first center through 24px sweep")
	check(grid.clear_segment(route[-1], sim(goal)), label + " final center safely joins exact authored approach")
	for i in range(route.size()):
		check(grid.is_center(route[i]) and point_clear(route[i]), label + " body clears center " + str(pixel(route[i])))
		if i > 0:
			check(grid.connected(grid.cell_at(route[i - 1]), grid.cell_at(route[i])) and sweep_clear(route[i - 1], route[i]), label + " swept edge is clear")
	return route

func _run() -> void:
	shape.size = BODY
	check(ResourceLoader.exists("res://scenes/BrackenMineContent.tscn"), "approved mine is installed as playable content")
	check(ResourceLoader.exists("res://scenes/BrackenMineArtwork.tscn"), "final separated artwork is included in geometry audit")
	if failures > 0:
		finish()
		return
	layout = JSON.parse_string(FileAccess.get_file_as_string("res://Assets/Maps/BrackenMine/layout.json"))
	content = load("res://scenes/BrackenMineContent.tscn").instantiate()
	root.add_child(content)
	await physics_frame
	await physics_frame
	check(content.transform == Transform2D.IDENTITY, "art, physics and canonical props retain native 1:1 transform")
	check(content.get_meta("gameplay_grid_origin") == Vector2.ZERO, "fixed pixel grid origin is (0,0)")
	check(vector(layout.world_size) == SIZE and vector(layout.actor_body_pixels) == BODY and layout.gameplay_cell_pixels == 32, "native dimensions, 24px body and 32px shared cells agree")
	grid.configure(Vector2(0, 32), Vector2.ZERO, Vector2(48, 32))
	grid.point_clear = point_clear
	grid.sweep_clear = sweep_clear
	var arrival := vector(layout.arrival)
	check(arrival == Vector2(768, 928), "authored two-way arrival is preserved")
	check(grid.recovery_cell(sim(arrival)) != null and point_clear(sim(arrival)), "arrival admits full body and swept safe-center recovery")
	checked_route(arrival, vector(layout.exit_approach), "Entrance exit approach")
	var probes := content.get_node("GridProbes")
	check(probes.get_child_count() >= 10, "all four alcoves and both island sides have authored probes")
	for marker: Node2D in probes.get_children():
		check(point_clear(sim(marker.position)), "full body fits exact authored probe " + str(marker.name))
		checked_route(arrival, marker.position, str(marker.name))
	# Constrain identical endpoints to opposite sides of the central island.
	# A single A* route to every room would not prove the loop remains complete.
	var west: Vector2 = probes.get_node("WestLoop").position
	var east: Vector2 = probes.get_node("EastLoop").position
	var north_route := checked_route(west, east, "North island loop", func(p: Vector2) -> bool: return pixel(p).y <= 560.0)
	var south_route := checked_route(west, east, "South island loop", func(p: Vector2) -> bool: return pixel(p).y >= 320.0)
	var passed_north := false
	var passed_south := false
	for point: Vector2 in north_route:
		passed_north = passed_north or pixel(point).y < 285.0
	for point: Vector2 in south_route:
		passed_south = passed_south or pixel(point).y > 592.0
	check(passed_north and passed_south, "independent full-body routes pass north and south of island")
	check(not sweep_clear(sim(west), sim(east)), "direct sweep cannot cross central rock island")
	var floor_polygon := polygon(layout.floor_boundary)
	var blocked_exterior := 0
	var exterior_gaps := 0
	# Sample authored meaning, never artwork RGB, at quarter-cell intervals.
	for y in range(0, 1025, 8):
		for x in range(0, 1537, 8):
			var point := Vector2(x, y)
			if not Geometry2D.is_point_in_polygon(point, floor_polygon):
				blocked_exterior += 1
				if point_clear(sim(point)):
					exterior_gaps += 1
	check(blocked_exterior > 10000 and exterior_gaps == 0, "solid exterior has no body-sized escape in %d quarter-cell samples (%d gaps)" % [blocked_exterior, exterior_gaps])
	for exclusion: Dictionary in layout.exclusions:
		var boundary := polygon(exclusion.polygon)
		check(content.get_node_or_null("Collision/" + str(exclusion.name)) != null, "explicit collider exists for " + str(exclusion.name))
		var samples := 0
		var gaps := 0
		for y in range(0, 1024, 8):
			for x in range(0, 1536, 8):
				var point := Vector2(x, y)
				if Geometry2D.is_point_in_polygon(point, boundary):
					samples += 1
					if point_clear(sim(point)):
						gaps += 1
		check(samples > 0 and gaps == 0, "%s is solid at all %d interior samples" % [exclusion.name, samples])
	check(not sweep_clear(sim(Vector2(768, 1008)), sim(Vector2(768, 1064))), "south entrance world bounds prevent exterior escape")
	var roster := {"copper":0, "tin":0, "iron":0, "coal":0}
	var ore_positions: Array[Vector2] = []
	for ore: Dictionary in layout.ores:
		var node: Node2D = content.get_node(str(ore.name))
		var ore_id := str(node.get_meta("ore_id", ""))
		check(roster.has(ore_id), "only requested ore types are installed")
		if roster.has(ore_id):
			roster[ore_id] += 1
		check(node.scene_file_path.begins_with("res://scenes/MapProps/OreNodes/") and node.scale == Vector2.ONE, str(node.name) + " reuses native canonical scene")
		check(node.get_script() == null and not node.is_in_group("mining_deposit"), str(node.name) + " remains prop without new mining rules")
		check(fmod(node.position.x, 32.0) == 0 and fmod(node.position.y, 32.0) == 0, str(node.name) + " respects 32px placement snapping")
		check(node.get_node_or_null("Footprint/MainBase") != null and node.get_node_or_null("Footprint/CompanionBase") != null, str(node.name) + " retains paired colliders")
		for base_name: String in ["MainBase", "CompanionBase"]:
			var base: CollisionPolygon2D = node.get_node("Footprint/" + base_name)
			for local_point: Vector2 in base.polygon:
				check(Geometry2D.is_point_in_polygon(content.to_local(base.to_global(local_point)), floor_polygon), str(node.name) + " physical base stays on approved floor")
		var front := vector(ore.front_approach)
		check(front.y >= node.position.y + 16.0 and front.distance_to(node.position) <= 48.0, str(node.name) + " approach remains immediately south/front of base")
		check(point_clear(sim(front)), str(node.name) + " exact front fits 24px body at " + str(front))
		checked_route(arrival, front, str(node.name) + " front approach")
		ore_positions.append(node.position)
	for ore_id: String in roster:
		check(roster[ore_id] == 3, "balanced roster contains three " + ore_id + " props")
	for i in range(ore_positions.size()):
		for j in range(i + 1, ore_positions.size()):
			check(ore_positions[i].distance_to(ore_positions[j]) >= 96.0, "canonical centers retain 96px compact-cluster spacing")
	var clear_cells := 0
	var safe_diagonals := 0
	var rejected_corners := 0
	var unsafe_connections := 0
	for y in range(-32, 0):
		for x in range(0, 48):
			var cell := Vector2i(x, y)
			if not grid.walkable(cell):
				continue
			clear_cells += 1
			for direction: Vector2i in HiddenGrid.DIRECTIONS:
				var next := cell + direction
				if not grid.walkable(next):
					continue
				var connected := grid.connected(cell, next)
				if connected and not sweep_clear(grid.center(cell), grid.center(next)):
					unsafe_connections += 1
				if direction.x != 0 and direction.y != 0:
					var cardinal_clear := grid.connected(cell, cell + Vector2i(direction.x, 0)) and grid.connected(cell, cell + Vector2i(0, direction.y)) and grid.connected(cell + Vector2i(direction.x, 0), next) and grid.connected(cell + Vector2i(0, direction.y), next)
					if not cardinal_clear:
						rejected_corners += 1
						check(not connected, "shared grid rejects obstructed diagonal corner")
					elif connected:
						safe_diagonals += 1
	check(clear_cells > 200 and safe_diagonals > 100 and rejected_corners > 0 and unsafe_connections == 0, "all edges use body sweeps and corner clearance (%d cells, %d diagonals, %d rejected corners, %d unsafe edges)" % [clear_cells, safe_diagonals, rejected_corners, unsafe_connections])
	# Every physically clear center must join the same traversable floor. This
	# catches an ore that seals a tiny room pocket beyond the named room probes.
	var reached := {}
	var frontier: Array[Vector2i] = []
	var first: Variant = grid.recovery_cell(sim(arrival))
	if first != null:
		frontier.append(first)
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		if reached.has(cell):
			continue
		reached[cell] = true
		for direction: Vector2i in HiddenGrid.DIRECTIONS:
			if not reached.has(cell + direction) and grid.connected(cell, cell + direction):
				frontier.append(cell + direction)
	check(reached.size() == clear_cells, "all %d physically clear grid centers connect to arrival (%d reached)" % [clear_cells, reached.size()])
	print("[Bracken geometry metrics] ", JSON.stringify({"clear_cells":clear_cells,"reachable_cells":reached.size(),"safe_diagonals":safe_diagonals,"rejected_corners":rejected_corners,"exterior_samples":blocked_exterior,"roster":roster}))
	content.queue_free()
	await process_frame
	await _audit_installed_wrapper()
	finish()

func _audit_installed_wrapper() -> void:
	check(ResourceLoader.exists("res://scenes/BrackenMine.tscn"), "playable wrapper is installed")
	if not ResourceLoader.exists("res://scenes/BrackenMine.tscn"):
		return
	root.get_node("SceneTravel").set("_player", null)
	var map: Node2D = load("res://scenes/BrackenMine.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	var game: Node = map.get_node("Combat")
	game.set_physics_process(false)
	for frame in range(90):
		await physics_frame
		if game.grid_adapter != null and game.grid_adapter.completed:
			break
	var report: Dictionary = game.grid_adoption_report()
	print("[Bracken installed adapter] ", JSON.stringify(report))
	check(report.get("enabled", false), "real main adapter adopts installed mine against physical geometry")
	var root_probes := map.get_node("GridProbes")
	check(root_probes.get_child_count() == layout.probes.size(), "runtime adoption sees every room and ore-front probe")
	for probe: Dictionary in layout.probes:
		var marker: Node2D = root_probes.get_node_or_null(str(probe.name))
		check(marker != null and marker.position == vector(probe.position), "wrapper preserves authored probe " + str(probe.name))
	if report.get("enabled", false):
		check(game.world.grid.origin == grid.origin and game.world.grid == game.world.cell_grid, "real movement and AoE retain same immutable 32px lattice")
		var runtime_grid: HiddenGrid = game.world.grid
		for probe: Dictionary in layout.probes:
			check(not runtime_grid.path(game.player.get_position(), game.grid_adapter.simulation_point(map.to_global(vector(probe.position)))).is_empty(), "real adopted movement reaches " + str(probe.name))
	map.queue_free()
	current_scene = null
	await process_frame

func finish() -> void:
	print("[Bracken geometry] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
