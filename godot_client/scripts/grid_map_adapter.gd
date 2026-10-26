class_name GridMapAdapter
extends Node
## Physics-backed adoption gate. Never edits or substitutes map geometry.
var game: Node2D
var grid := HiddenGrid.new()
var report := {"enabled": false, "reason": "awaiting physics geometry", "checks": 0}
var completed := false
var _shape := RectangleShape2D.new()

func configure(owner_game: Node2D) -> void:
	game = owner_game
	_shape.size = Vector2(24, 24)
	# Authored once per map, never camera/player-derived. Most areas use (0,0).
	var pixel_origin: Vector2 = game.get_parent().get_meta("gameplay_grid_origin", Vector2.ZERO)
	grid.configure(Vector2((pixel_origin.x - game.map_origin.x) / 32.0, (game.map_origin.y + game.map_height - pixel_origin.y) / 32.0),
		game.world.movement_min, game.world.movement_max)
	grid.point_clear = _point_clear
	grid.sweep_clear = _sweep_clear

func _query(point: Vector2) -> PhysicsShapeQueryParameters2D:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _shape
	query.transform = Transform2D(0, game.to_global(game._screen_position(point.x, point.y)))
	query.collision_mask = 1
	query.collide_with_areas = false
	query.margin = 0.08
	return query

func _point_clear(point: Vector2) -> bool:
	return game.get_world_2d().direct_space_state.intersect_shape(_query(point), 1).is_empty()

func _sweep_clear(start: Vector2, finish: Vector2) -> bool:
	var query := _query(start)
	query.motion = game.to_global(game._screen_position(finish.x, finish.y)) - query.transform.origin
	var fractions := game.get_world_2d().direct_space_state.cast_motion(query)
	return fractions.size() == 2 and fractions[0] >= 0.99999

func simulation_point(global_point: Vector2) -> Vector2:
	var local := game.to_local(global_point)
	return Vector2((local.x - game.map_origin.x) / 32.0, (game.map_origin.y + game.map_height - local.y) / 32.0)

func audit() -> Dictionary:
	completed = true
	var root := game.get_parent()
	var probes: Array[Vector2] = []
	var spawns := root.get_node_or_null("SpawnPoints")
	if spawns != null:
		var entry: Node2D = spawns.get_node_or_null(str(game.initial_spawn_id)) if not str(game.initial_spawn_id).is_empty() else null
		if entry != null:
			probes.append(simulation_point(entry.global_position))
		for marker: Node2D in spawns.get_children():
			probes.append(simulation_point(marker.global_position))
	if probes.is_empty():
		probes.append(game.player.get_position())
	var authored_probes := root.get_node_or_null("GridProbes")
	if authored_probes != null:
		for marker: Node2D in authored_probes.get_children():
			probes.append(simulation_point(marker.global_position))
	# Existing Catacombs data supplies topology probes, not gameplay cell size.
	if root.scene_file_path.ends_with("CatacombsFloor01.tscn"):
		var path := "res://Assets/Maps/GolemCatacombs/Floor01/layout.json"
		var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		for room: Dictionary in layout.get("rooms", []):
			var point: Array = room.probe
			probes.append(simulation_point(root.to_global(Vector2(point[0], point[1]))))
	var count := 0
	for point: Vector2 in probes:
		count += 1
		if grid.recovery_cell(point) == null or grid.path(probes[0], point).is_empty():
			report = {"enabled": false, "reason": "spawn/room route incompatible or exceeds bounded search", "point": [point.x, point.y], "checks": count}
			return report
	for group: String in ["cave_portal", "cooking_station", "mining_deposit"]:
		for node: Node in game.get_tree().get_nodes_in_group(group):
			if not root.is_ancestor_of(node) or not node.has_method("approach_position"):
				continue
			var reach: Variant = node.get("interaction_radius")
			if reach == null:
				reach = node.get("interact_radius")
			var radius := float(reach) / 32.0 if reach != null else 0.0
			count += 1
			var target := simulation_point(node.approach_position())
			if grid.path(probes[0], target, radius, Callable(),
				func(p: Vector2) -> bool: return not node is MiningDeposit or game.world.has_line_of_sight(p, target)).is_empty():
				report = {"enabled": false, "reason": "unreachable authored interaction: " + str(node.name), "checks": count}
				return report
	for spot: FishingSpot in game.fishing_spots():
		count += 1
		if grid.path(probes[0], simulation_point(spot.shore_position()), spot.interact_radius / 32.0).is_empty():
			report = {"enabled": false, "reason": "unreachable fishing shore: " + str(spot.name), "checks": count}
			return report
	for station: Node in game.get_tree().get_nodes_in_group("crafting_station"):
		if root.is_ancestor_of(station):
			count += 1
			if grid.path(probes[0], station.simulation_position, 2.5).is_empty():
				report = {"enabled": false, "reason": "unreachable crafting approach: " + str(station.name), "checks": count}
				return report
	# Prove that the actual spawn has some usable neighboring connections.
	var start: Variant = grid.recovery_cell(probes[0])
	var neighbors := 0
	for direction: Vector2i in HiddenGrid.DIRECTIONS:
		if grid.connected(start, start + direction):
			neighbors += 1
	if neighbors == 0:
		report = {"enabled": false, "reason": "spawn center isolated", "checks": count}
	else:
		report = {"enabled": true, "reason": "spawn, room and authored approach routes validated against physics", "checks": count, "spawn_connections": neighbors}
	return report
