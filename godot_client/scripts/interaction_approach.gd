extends RefCounted
## Shared authored positions/ranges. A walk intent never supplies its own reach.
static func describe(game: Node2D, node: Node2D, kind: String) -> Dictionary:
	if not is_instance_valid(node) or not node.is_inside_tree() or not node.is_visible_in_tree() or not game.get_parent().is_ancestor_of(node):
		return {}
	var point: Vector2
	var reach := 0.0
	var sight := false
	match kind:
		"fish":
			if not node is FishingSpot:
				return {}
			point = node.shore_position()
			reach = node.interact_radius
		"cook":
			if not node is CookingStation or not node.enabled:
				return {}
			point = node.approach_position()
			reach = node.interaction_radius
		"craft":
			if not node is CraftingStation:
				return {}
			return {"point": node.simulation_position, "reach": 2.5, "sight": false}
		"mine":
			if not node is MiningDeposit or not node.enabled:
				return {}
			point = node.approach_position()
			reach = node.interaction_radius
			sight = true
		"portal":
			if not node is CavePortal or not node.enabled:
				return {}
			point = node.approach_position()
			reach = node.interaction_radius
		"pickup":
			if not node is GroundItemDrop or node.collected:
				return {}
			point = node.global_position
			reach = 64.0
		_:
			return {}
	if not point.is_finite() or not is_finite(reach) or reach <= 0.0:
		return {}
	var local := game.to_local(point)
	var simulation := local / 32.0
	if game.get("map_scene_mode") != false:
		var origin: Vector2 = game.get("map_origin")
		simulation = Vector2((local.x - origin.x) / 32.0, (origin.y + float(game.get("map_height")) - local.y) / 32.0)
	return {"point": simulation, "reach": reach / 32.0, "sight": sight}

static func in_range(world: Variant, actor: Variant, approach: Dictionary) -> bool:
	if actor == null or approach.is_empty():
		return false
	var point := Vector2(actor.x, actor.y)
	return point.distance_to(approach.point) <= float(approach.reach) + 0.00001 \
		and (not bool(approach.sight) or world.has_line_of_sight(point, approach.point))

static func identifier(game: Node, node: Node2D, kind: String) -> String:
	if kind == "mine":
		return node.deposit_id
	if kind == "pickup":
		return str(node.get_meta("online_drop_id", ""))
	return str(game.get_parent().get_path_to(node))
