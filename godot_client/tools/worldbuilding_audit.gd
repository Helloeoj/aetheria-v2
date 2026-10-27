extends RefCounted
## Development-only, read-only audit of registered Godot physics geometry.
## Contract coordinates are world pixels; image colors never define collision.
const Grid = preload("res://scripts/hidden_grid.gd")
const CELL := 32.0
const ACTOR := 24.0
var _result: Dictionary
var _map: Node2D
var _bounds: Rect2
var _floor := PackedVector2Array()
var _grid: HiddenGrid

func audit(map: Node2D, spec: Dictionary) -> Dictionary:
	_result = {"passed":false, "checks":0, "issues":[], "prop_textures":[], "conservative_footprints":[], "rendering_verified":false}
	_map = map
	_floor = PackedVector2Array()
	if not _check(_valid_contract(spec), "invalid_contract", "", "Contract v1 requires a real res:// .tscn, finite positive bounds/grid origin, at least one prop, two distinct anchors and one protected route (width >= 24); nonblocking props require reason."):
		return _result
	if not _check(map != null and map.is_inside_tree(), "invalid_scene", "", "Audit requires a registered Node2D scene after physics frames."):
		return _result
	_bounds = Rect2(_v(spec.bounds), Vector2(float(spec.bounds[2]), float(spec.bounds[3])))
	if spec.has("floor_polygon"):
		for pair: Array in spec.floor_polygon:
			_floor.append(_v(pair))
	_grid = Grid.new()
	_grid.configure(_v(spec.grid_origin) / CELL, _bounds.position / CELL, _bounds.end / CELL)
	_grid.point_clear = func(p: Vector2) -> bool: return _actor_clear(p * CELL, ACTOR)
	_grid.sweep_clear = func(a: Vector2, b: Vector2) -> bool: return _actor_sweep(a * CELL, b * CELL, ACTOR)
	# A fresh grid is created on every audit; placement edits cannot reuse caches.
	var roots: Array[Node] = []
	for entry: Dictionary in spec.props:
		var prop := map.get_node_or_null(NodePath(entry.node))
		if not _check(prop is Node2D, "prop_missing", str(entry.node), "Installed prop node is absent or not Node2D."):
			continue
		if not _check(prop != map, "invalid_prop_scope", str(entry.node), "A prop cannot be the whole audited scene; use its individual child root so walls and peers remain collision candidates."):
			continue
		if not _check(not prop.scene_file_path.is_empty(), "invalid_prop_scope", str(entry.node), "Declare the root of an actual reusable PackedScene instance, not a folder combining props or walls."):
			continue
		var nested := false
		for other: Node in roots:
			nested = nested or other == prop or other.is_ancestor_of(prop) or prop.is_ancestor_of(other)
		if not _check(not nested, "invalid_prop_scope", str(entry.node), "Audited prop roots must be disjoint; a parent scope would hide peer collisions."):
			continue
		roots.append(prop)
		_audit_visuals(prop, str(entry.node))
		if not entry.blocking:
			_check(not _has_world_shape(prop), "nonblocking_has_footprint", str(entry.node), "Nonblocking declaration conflicts with an enabled world-solid shape; audit it as blocking.")
			continue
		_audit_prop(prop, str(entry.node))
	var first: Vector2 = _v(spec.anchors[0].point)
	for anchor: Dictionary in spec.anchors:
		var point := _v(anchor.point)
		_check(_actor_clear(point, ACTOR), "anchor_blocked", str(anchor.id), "Exact world anchor does not fit the 24px actor: " + str(point))
		var recovered: Variant = _grid.recovery_cell(point / CELL)
		_check(recovered != null, "anchor_grid_join_blocked", str(anchor.id), "Exact anchor has no body-swept join to a shared 32px center.")
		if point != first:
			_check(_reachable(first, point), "route_unreachable", str(anchor.id), "Required anchor is disconnected or exceeds the bounded grid search; exact endpoints and joins are required.")
	for route: Dictionary in spec.routes:
		var width := float(route.width)
		for index in range(1, route.points.size()):
			var start := _v(route.points[index - 1])
			var finish := _v(route.points[index])
			_check(_actor_sweep(start, finish, width), "reserved_lane_blocked", str(route.id), "Reserved %spx lane segment %d overlaps a solid or leaves authored bounds/floor." % [width, index])
			_check(_reachable(start, finish), "route_unreachable", str(route.id), "Protected route segment %d cannot connect its exact endpoints with shared-grid actor sweeps." % index)
	_result.passed = _result.issues.is_empty()
	# The grid owns callbacks to this RefCounted audit object; release the
	# callbacks explicitly so repeated validations do not form a reference cycle.
	_grid.point_clear = Callable()
	_grid.sweep_clear = Callable()
	_grid = null
	return _result

func _audit_visuals(prop: Node, label: String) -> void:
	var sprites: Array[Sprite2D] = []
	_collect_sprites(prop, sprites)
	_check(not sprites.is_empty(), "missing_visual", label, "Audited props require a visible standalone Sprite2D PNG to bind source-art checks.")
	for sprite: Sprite2D in sprites:
		var path := str(_map.get_path_to(sprite))
		var texture: Texture2D = sprite.texture
		var standalone := texture != null and not texture is AtlasTexture and texture.resource_path.begins_with("res://") and texture.resource_path.ends_with(".png") and not sprite.region_enabled and sprite.hframes == 1 and sprite.vframes == 1
		if _check(standalone, "unsupported_visual_texture", path, "Use a standalone res:// PNG; atlases, regions, sprite sheets and generated textures need a deliberate source-contract extension."):
			var anchor: Vector2 = sprite.to_local((prop as Node2D).global_position) - sprite.get_rect().position
			if sprite.flip_h:
				anchor.x = texture.get_width() - anchor.x
			if sprite.flip_v:
				anchor.y = texture.get_height() - anchor.y
			_result.prop_textures.append({"node":path, "texture":texture.resource_path, "native_size":[texture.get_width(), texture.get_height()], "anchor":[anchor.x, anchor.y], "world_scale":[sprite.global_transform.x.length(), sprite.global_transform.y.length()]})
			var source: Image = Image.load_from_file(ProjectSettings.globalize_path(texture.resource_path)) if FileAccess.file_exists(texture.resource_path) else null
			_check(images_match(texture.get_image(), source), "imported_texture_mismatch", path, "Loaded/imported texture differs from current source PNG dimensions, alpha or visible RGB; reimport before accepting this prop.")
		_check(_nearest_filter(sprite), "visual_filter", path, "Effective inherited texture filter must be nearest without mipmaps.")
		_check(sprite.is_visible_in_tree(), "missing_visual", path, "Prop Sprite2D is hidden in the installed scene.")

static func images_match(imported: Image, source: Image) -> bool:
	if imported == null or source == null or imported.is_empty() or source.is_empty() or imported.get_size() != source.get_size():
		return false
	var actual := imported.duplicate() as Image
	var expected := source.duplicate() as Image
	if (actual.is_compressed() and actual.decompress() != OK) or (expected.is_compressed() and expected.decompress() != OK):
		return false
	actual.convert(Image.FORMAT_RGBA8)
	expected.convert(Image.FORMAT_RGBA8)
	var actual_bytes := actual.get_data()
	var expected_bytes := expected.get_data()
	if actual_bytes.size() != expected_bytes.size():
		return false
	for index in range(0, actual_bytes.size(), 4):
		if actual_bytes[index + 3] != expected_bytes[index + 3]:
			return false
		# Godot's fix_alpha_border legitimately fills hidden RGB around edges.
		if actual_bytes[index + 3] > 0 and (actual_bytes[index] != expected_bytes[index] or actual_bytes[index + 1] != expected_bytes[index + 1] or actual_bytes[index + 2] != expected_bytes[index + 2]):
			return false
	return true

func _collect_sprites(node: Node, sprites: Array[Sprite2D]) -> void:
	if node is Sprite2D:
		sprites.append(node)
	for child: Node in node.get_children():
		_collect_sprites(child, sprites)

func _nearest_filter(sprite: Sprite2D) -> bool:
	var item: CanvasItem = sprite
	while item != null:
		if item.texture_filter != CanvasItem.TEXTURE_FILTER_PARENT_NODE:
			return item.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
		item = item.get_parent() as CanvasItem
	return sprite.get_viewport().canvas_item_default_texture_filter == Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST

func _audit_prop(prop: Node, label: String) -> void:
	var bodies: Array[PhysicsBody2D] = []
	_collect_bodies(prop, bodies)
	var own_rids: Array[RID] = []
	for body: PhysicsBody2D in bodies:
		own_rids.append(body.get_rid())
	var shape_count := 0
	for body: PhysicsBody2D in bodies:
		if body.collision_layer & 1 == 0:
			continue
		for owner_id: int in body.get_shape_owners():
			if body.is_shape_owner_disabled(owner_id):
				continue
			var transform: Transform2D = body.global_transform * body.shape_owner_get_transform(owner_id)
			for index in range(body.shape_owner_get_shape_count(owner_id)):
				var shape: Shape2D = body.shape_owner_get_shape(owner_id, index)
				shape_count += 1
				if shape is CircleShape2D or shape is CapsuleShape2D:
					_result.conservative_footprints.append({"node":label, "shape":shape.get_class(), "detail":"Bounds/floor containment uses transformed enclosing rectangle; overlap query uses the actual native shape."})
				var polygon := _shape_polygon(shape, transform)
				if not _check(not polygon.is_empty(), "unsupported_footprint", label, "Physical base needs a solid rectangle, convex polygon, circle or capsule; unsupported shapes require a deliberate validator extension."):
					continue
				_check(_inside_bounds(polygon), "footprint_out_of_bounds", label, "Actual transformed physical base extends outside contract bounds.")
				_check(_inside_floor(polygon), "footprint_outside_floor", label, "Actual transformed physical base crosses the authored floor polygon, including concave cuts.")
				var query := PhysicsShapeQueryParameters2D.new()
				query.shape = shape
				query.transform = transform
				query.collision_mask = 1
				query.collide_with_areas = false
				query.exclude = own_rids
				query.margin = 0.0
				var hits := _map.get_world_2d().direct_space_state.intersect_shape(query, 16)
				var peers: Array[String] = []
				for hit: Dictionary in hits:
					var collider: Object = hit.collider
					peers.append(str(collider.get_path()) if collider is Node else str(hit.collider_id))
				_check(hits.is_empty(), "footprint_overlap", label, "Physical base overlaps world solids: " + ", ".join(peers))
	_check(shape_count > 0, "missing_footprint", label, "Blocking prop has no enabled body shape on world-solid layer 1.")

func _has_world_shape(prop: Node) -> bool:
	var bodies: Array[PhysicsBody2D] = []
	_collect_bodies(prop, bodies)
	for body: PhysicsBody2D in bodies:
		if body.collision_layer & 1 == 0:
			continue
		for owner_id: int in body.get_shape_owners():
			if not body.is_shape_owner_disabled(owner_id) and body.shape_owner_get_shape_count(owner_id) > 0:
				return true
	return false

func _collect_bodies(node: Node, bodies: Array[PhysicsBody2D]) -> void:
	if node is PhysicsBody2D:
		bodies.append(node)
	for child: Node in node.get_children():
		_collect_bodies(child, bodies)

func _shape_polygon(shape: Shape2D, transform: Transform2D) -> PackedVector2Array:
	var points := PackedVector2Array()
	if shape is ConvexPolygonShape2D:
		points = shape.points
	elif shape is RectangleShape2D:
		var half: Vector2 = shape.size * 0.5
		points = PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)])
	elif shape is CircleShape2D or shape is CapsuleShape2D:
		var rect := shape.get_rect()
		points = PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	for index in range(points.size()):
		points[index] = transform * points[index]
	return points

func _actor_polygon(start: Vector2, finish: Vector2, width: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var half := Vector2.ONE * width * 0.5
	for point: Vector2 in [start, finish]:
		points.append(point - half)
		points.append(point + Vector2(half.x, -half.y))
		points.append(point + half)
		points.append(point + Vector2(-half.x, half.y))
	var hull := Geometry2D.convex_hull(points)
	if hull.size() > 1 and hull[0] == hull[-1]:
		hull.remove_at(hull.size() - 1)
	return hull

func _inside_bounds(polygon: PackedVector2Array) -> bool:
	for point: Vector2 in polygon:
		if not point.is_finite() or point.x < _bounds.position.x or point.y < _bounds.position.y or point.x > _bounds.end.x or point.y > _bounds.end.y:
			return false
	return true

func _inside_floor(polygon: PackedVector2Array) -> bool:
	if _floor.is_empty():
		return true
	# Polygon difference detects edges crossing a concavity even when all base
	# vertices happen to be inside. Boundary contact without area overlap is OK.
	for outside: PackedVector2Array in Geometry2D.clip_polygons(polygon, _floor):
		if absf(_area(outside)) > 0.001:
			return false
	return true

func _actor_query(point: Vector2, width: float) -> PhysicsShapeQueryParameters2D:
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2.ONE * width
	query.shape = shape
	query.transform = Transform2D(0.0, point)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.margin = 0.08
	return query

func _actor_clear(point: Vector2, width: float) -> bool:
	var polygon := _actor_polygon(point, point, width)
	return _inside_bounds(polygon) and _inside_floor(polygon) and _map.get_world_2d().direct_space_state.intersect_shape(_actor_query(point, width), 1).is_empty()

func _actor_sweep(start: Vector2, finish: Vector2, width: float) -> bool:
	if not _actor_clear(start, width) or not _actor_clear(finish, width):
		return false
	var polygon := _actor_polygon(start, finish, width)
	if not _inside_bounds(polygon) or not _inside_floor(polygon):
		return false
	var query := _actor_query(start, width)
	query.motion = finish - start
	var fractions := _map.get_world_2d().direct_space_state.cast_motion(query)
	return fractions.size() == 2 and fractions[0] >= 0.99999

func _reachable(start: Vector2, finish: Vector2) -> bool:
	if not _actor_clear(start, ACTOR) or not _actor_clear(finish, ACTOR):
		return false
	var route: PackedVector2Array = _grid.path(start / CELL, finish / CELL, 0.0, Callable(),
		func(p: Vector2) -> bool: return _actor_sweep(p * CELL, finish, ACTOR))
	return not route.is_empty() and _actor_sweep(start, route[0] * CELL, ACTOR) and _actor_sweep(route[-1] * CELL, finish, ACTOR)

func _check(ok: bool, code: String, node: String, detail: String) -> bool:
	_result.checks += 1
	if not ok:
		_result.issues.append({"code":code, "node":node, "detail":detail})
	return ok

static func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value))

static func _pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1])

static func _v(pair: Array) -> Vector2:
	return Vector2(float(pair[0]), float(pair[1]))

static func _area(points: PackedVector2Array) -> float:
	var area := 0.0
	for index in range(points.size()):
		area += points[index].cross(points[(index + 1) % points.size()])
	return area * 0.5

static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

static func _valid_contract(spec: Dictionary) -> bool:
	# Godot's JSON parser decodes JSON numbers as floats, including schema 1.
	if not _number(spec.get("schema_version")) or float(spec.schema_version) != 1.0:
		return false
	var scene: Variant = spec.get("scene")
	if not _text(scene) or not scene.begins_with("res://") or not scene.ends_with(".tscn") or ".." in scene or not ResourceLoader.exists(scene):
		return false
	var bounds: Variant = spec.get("bounds")
	if not bounds is Array or bounds.size() != 4:
		return false
	for value: Variant in bounds:
		if not _number(value):
			return false
	if float(bounds[2]) <= 0.0 or float(bounds[3]) <= 0.0 or not is_finite(float(bounds[0]) + float(bounds[2])) or not is_finite(float(bounds[1]) + float(bounds[3])) or not _pair(spec.get("grid_origin")):
		return false
	if not spec.get("props") is Array or spec.props.is_empty() or not spec.get("anchors") is Array or spec.anchors.size() < 2 or not spec.get("routes") is Array or spec.routes.is_empty():
		return false
	var names := {}
	for prop: Variant in spec.props:
		if not prop is Dictionary or not _text(prop.get("node")) or prop.node == "." or prop.node.begins_with("/") or ":" in prop.node or ".." in prop.node or typeof(prop.get("blocking")) != TYPE_BOOL or names.has(prop.node):
			return false
		if not prop.blocking and not _text(prop.get("reason")):
			return false
		names[prop.node] = true
	names.clear()
	var points := {}
	for anchor: Variant in spec.anchors:
		if not anchor is Dictionary or not _text(anchor.get("id")) or names.has(anchor.id) or not _pair(anchor.get("point")):
			return false
		names[anchor.id] = true
		points[_v(anchor.point)] = true
	if points.size() < 2:
		return false
	names.clear()
	for route: Variant in spec.routes:
		if not route is Dictionary or not _text(route.get("id")) or names.has(route.id) or not route.get("points") is Array or route.points.size() < 2 or not _number(route.get("width")) or float(route.width) < ACTOR:
			return false
		names[route.id] = true
		var distinct := {}
		for point: Variant in route.points:
			if not _pair(point):
				return false
			distinct[_v(point)] = true
		if distinct.size() < 2:
			return false
	if spec.has("floor_polygon"):
		if not spec.floor_polygon is Array or spec.floor_polygon.size() < 3:
			return false
		var polygon := PackedVector2Array()
		for pair: Variant in spec.floor_polygon:
			if not _pair(pair) or polygon.has(_v(pair)):
				return false
			polygon.append(_v(pair))
		if absf(_area(polygon)) < 0.001:
			return false
		for i in range(polygon.size()):
			for j in range(i + 1, polygon.size()):
				if j == i + 1 or (i == 0 and j == polygon.size() - 1):
					continue
				if Geometry2D.segment_intersects_segment(polygon[i], polygon[(i + 1) % polygon.size()], polygon[j], polygon[(j + 1) % polygon.size()]) != null:
					return false
	return true
