extends SceneTree
## Regress stationary thumbs and elastic closed fists without changing the art.
const RIG := preload("res://scripts/dev_tools/golem_titan_skeleton_rig.gd")
const HAND_POINTS := {
	"fist_right": [Vector2(64, 176), Vector2(64, 184), Vector2(36, 184), Vector2(44, 192), Vector2(40, 200)],
	"fist_left": [Vector2(192, 176), Vector2(192, 184), Vector2(220, 184), Vector2(212, 192), Vector2(216, 200), Vector2(182, 180), Vector2(184, 188), Vector2(186, 184)],
}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var rig := RIG.new()
	root.add_child(rig)
	await process_frame
	var failures: Array[String] = []
	# The rest UV surface must cover the source exactly. Hand/restraint seams
	# intentionally duplicate vertex indexes at the same source position.
	var edge_counts: Dictionary = {}
	var mesh_area := 0.0
	var mesh_vertices: PackedVector2Array = rig.skin.polygon
	var position_indexes: Dictionary = {}
	var canonical := PackedInt32Array()
	for index in mesh_vertices.size():
		var point: Vector2 = mesh_vertices[index]
		if not position_indexes.has(point):
			position_indexes[point] = index
		canonical.append(int(position_indexes[point]))
	for triangle: PackedInt32Array in rig.skin.polygons:
		var a: Vector2 = mesh_vertices[triangle[0]]
		var b: Vector2 = mesh_vertices[triangle[1]]
		var c: Vector2 = mesh_vertices[triangle[2]]
		var area := (b - a).cross(c - a) * 0.5
		if area <= 0.0:
			failures.append("Degenerate or reversed rest triangle.")
		mesh_area += area
		for edge in 3:
			var first := canonical[triangle[edge]]
			var second := canonical[triangle[(edge + 1) % 3]]
			var key := Vector2i(mini(first, second), maxi(first, second))
			edge_counts[key] = int(edge_counts.get(key, 0)) + 1
	for edge: Vector2i in edge_counts:
		if edge_counts[edge] == 2:
			continue
		var a: Vector2 = mesh_vertices[edge.x]
		var b: Vector2 = mesh_vertices[edge.y]
		var outer_edge := (a.x == b.x and a.x in [0.0, 256.0]) or (a.y == b.y and a.y in [0.0, 256.0])
		if edge_counts[edge] != 1 or not outer_edge:
			failures.append("Nonconforming or nonmanifold mesh edge.")
	if not is_equal_approx(mesh_area, 256.0 * 256.0):
		failures.append("Rest mesh does not cover the complete unchanged texture.")
	for name: String in HAND_POINTS:
		for point: Vector2 in HAND_POINTS[name]:
			var weights: Dictionary = rig.call("_weights_at", point)
			if weights.size() != 1 or not is_equal_approx(float(weights.get(name, 0.0)), 1.0):
				failures.append("%s at %s is not wholly owned by its hand: %s" % [name, point, weights])
	var maximum_shape_error := 0.0
	for index in 48:
		rig.sample_at_seconds(2.4 * float(index) / 48.0)
		var deformed: PackedVector2Array = rig.get_deformed_vertices()
		for name: String in HAND_POINTS:
			var reference: Vector2 = HAND_POINTS[name][2]
			var reference_index: int = rig.get_hand_vertex_index(reference, name)
			if reference_index < 0:
				failures.append("Missing regression reference vertex: " + str(reference))
				continue
			for point: Vector2 in HAND_POINTS[name]:
				var point_index: int = rig.get_hand_vertex_index(point, name)
				if point_index < 0:
					failures.append("Missing hand vertex: " + str(point))
					continue
				var error := absf(deformed[point_index].distance_to(deformed[reference_index]) - point.distance_to(reference))
				maximum_shape_error = maxf(maximum_shape_error, error)
	if maximum_shape_error > 0.0001:
		failures.append("Thumb/finger distances stretch by %.6f native pixels." % maximum_shape_error)
	for failure: String in failures:
		printerr("[Titan hand test] ", failure)
	print("[Titan hand test] %d failures; maximum thumb/finger distance error %.8f px." % [failures.size(), maximum_shape_error])
	rig.queue_free()
	quit(0 if failures.is_empty() else 1)
