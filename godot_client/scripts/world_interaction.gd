class_name WorldInteraction
extends Node
const Approach := preload("res://scripts/interaction_approach.gd")
## Converts pointer intent into selection, context actions and collision-aware walking.
var game: Node
var selected_drop: GroundItemDrop
var pending_pickup: GroundItemDrop
var pending_portal: CavePortal
var pending_cooking: Node2D
var pending_activity: Node2D
var pending_kind := ""
var walk_waypoints: Array[Vector2] = []
var walking := false
var destination := Vector2.ZERO
var blocked_seconds := 0.0

func configure(game_ref: Node) -> void:
	game = game_ref

func handle_click(event: InputEventMouseButton, global_point: Vector2) -> void:
	game.get_viewport().gui_release_focus()
	var monsters := monsters_at(global_point)
	var drops := drops_at(global_point)
	var portals := portals_at(global_point)
	var cooking_stations: Array[Node2D] = []
	for station: Node in get_tree().get_nodes_in_group("cooking_station"):
		if station.is_current(game) and station.contains_global_point(global_point):
			cooking_stations.append(station)
	var stations: Array[Node2D] = []
	for node: Node in get_tree().get_nodes_in_group("crafting_station"):
		if game.is_ancestor_of(node) and node.contains_global_point(global_point):
			stations.append(node)
	var fishing_hits: Array[FishingSpot] = []
	for spot: FishingSpot in game.fishing_spots():
		if spot.contains_global_point(global_point):
			fishing_hits.append(spot)
	var deposits: Array[Node2D] = []
	for node: Node in get_tree().get_nodes_in_group("mining_deposit"):
		if game.get_parent().is_ancestor_of(node) and node.contains_global_point(global_point):
			deposits.append(node)
	if event.button_index == MOUSE_BUTTON_LEFT:
		cancel_walk()
		if not portals.is_empty():
			request_portal(portals[0])
		elif not cooking_stations.is_empty():
			request_cooking(cooking_stations[0])
		elif not stations.is_empty():
			game.request_crafting(stations[0])
		elif not monsters.is_empty():
			select_monster(monsters[0])
		elif not drops.is_empty():
			select_drop(drops[0])
		elif not fishing_hits.is_empty():
			game.request_fishing(fishing_hits[0])
		elif not deposits.is_empty():
			game.request_mining(deposits[0])
		else:
			walk_here(global_point)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		cancel_walk()
		game._reset_held_movement()
		var entries: Array[Dictionary] = []
		for station: Node2D in cooking_stations:
			entries.append({"label": "Cook at stove", "action": _cooking_instance.bind(station.get_instance_id())})
		for station: Node2D in stations:
			entries.append({"label": "Use " + station.station_name, "action": game.request_crafting.bind(station)})
		for portal: CavePortal in portals:
			entries.append({"label": "Enter " + portal.portal_name, "action": _portal_instance.bind(portal.get_instance_id())})
		for spot: FishingSpot in fishing_hits:
			entries.append({"label": "Fish " + spot.spot_name, "action": game.request_fishing.bind(spot)})
		for deposit: Node2D in deposits:
			entries.append({"label": "Mine", "action": game.request_mining.bind(deposit)})
		for id: String in monsters:
			var actor: CombatActor = game.combat.actors.get(id)
			entries.append({"label": "Attack " + actor.name, "action": attack.bind(id)})
		for drop: GroundItemDrop in drops:
			entries.append({"label": "Pick up %s%s" % [drop.item_name, " ×%d" % drop.quantity if drop.quantity > 1 else ""], "action": _pickup_instance.bind(drop.get_instance_id())})
		# The doorway artwork can sit in a solid wall. Walk here ends on the
		# authored approach point and never acquires an Enter intent.
		var walk_point: Vector2 = portals[0].approach_position() if not portals.is_empty() else global_point
		if not cooking_stations.is_empty():
			walk_point = cooking_stations[0].approach_position()
		entries.append({"label": "Walk here", "action": walk_here.bind(walk_point)})
		game.context_menu.show_options("Choose option", entries, event.position)
	game.get_viewport().set_input_as_handled()

func monsters_at(global_point: Vector2) -> Array[String]:
	var hits: Array[String] = []
	for monster: MonsterState in game.world.monsters:
		var actor: CombatActor = game.combat.actors.get(monster.entity_id)
		var sprite: ActorSprite = game.actor_sprites.get(monster.entity_id)
		if actor == null or not actor.is_alive or sprite == null:
			continue
		var hit := Rect2(Vector2(-sprite.size.x * 0.5, -sprite.size.y), sprite.size).has_point(sprite.to_local(global_point))
		var visual := sprite.animated_sprite
		if visual != null and visual.visible and visual.sprite_frames != null:
			var texture := visual.sprite_frames.get_frame_texture(visual.animation, visual.frame)
			if texture != null:
				var used := texture.get_image().get_used_rect()
				var origin := visual.offset - texture.get_size() * 0.5
				hit = Rect2(origin + Vector2(used.position), Vector2(used.size)).grow(3).has_point(visual.to_local(global_point)) or hit
		if hit:
			hits.append(monster.entity_id)
	# The actor drawn last (lowest feet on screen) is selected first.
	hits.sort_custom(func(a: String, b: String) -> bool: return game.actor_sprites[a].global_position.y > game.actor_sprites[b].global_position.y)
	return hits

func drops_at(global_point: Vector2) -> Array[GroundItemDrop]:
	var hits: Array[GroundItemDrop] = []
	for drop: GroundItemDrop in game.ground_drops:
		if is_instance_valid(drop) and drop.contains_global_point(global_point):
			hits.push_front(drop)
	return hits

func portals_at(global_point: Vector2) -> Array[CavePortal]:
	var hits: Array[CavePortal] = []
	for node: Node in game.get_tree().get_nodes_in_group("cave_portal"):
		var portal := node as CavePortal
		if _portal_is_current(portal) and portal.contains_global_point(global_point):
			hits.append(portal)
	hits.sort_custom(func(a: CavePortal, b: CavePortal) -> bool: return a.global_position.y > b.global_position.y)
	return hits

func _portal_is_current(portal: CavePortal) -> bool:
	return is_instance_valid(portal) and portal.enabled and portal.is_visible_in_tree() and game.get_parent() != null and game.get_parent().is_ancestor_of(portal)

func select_monster(id: String) -> void:
	clear_drop_selection()
	cancel_walk()
	game._set_target(id)

func select_drop(drop: GroundItemDrop) -> void:
	cancel_walk()
	clear_drop_selection()
	game._clear_target()
	if not is_instance_valid(drop) or drop.collected:
		return
	selected_drop = drop
	drop.set_selected(true)

func clear_drop_selection() -> void:
	if is_instance_valid(selected_drop):
		selected_drop.set_selected(false)
	selected_drop = null

func attack(id: String) -> void:
	var actor: CombatActor = game.combat.actors.get(id)
	if actor == null or not actor.is_alive:
		return
	select_monster(id)
	game._start_auto_chase()

func walk_here(global_point: Vector2) -> void:
	cancel_walk()
	clear_drop_selection()
	game._reset_held_movement()
	if Network.online():
		var point := _simulation_position(global_point)
		Network.send_action({"type": "walk", "x": point.x, "y": point.y})
		return
	game._clear_target()
	_route_to(global_point)

func _route_to(global_point: Vector2) -> void:
	destination = _simulation_position(global_point)
	walk_waypoints.clear()
	walking = true
	if Network.online():
		var command := {"type": "walk", "x": destination.x, "y": destination.y}
		var node := _pending_node()
		if node != null:
			command["interaction_kind"] = _pending_type()
			command["interaction_id"] = Approach.identifier(game, node, _pending_type())
		Network.send_action(command)
		return
	if game.world.grid != null:
		var start: Vector2 = game.player.get_position()
		if game.world.grid.path(start, destination, _grid_reach(), Callable(), _goal_valid).is_empty():
			cancel_walk()
			game.show_fishing_notice("That spot cannot be reached from here.")
		return
	var map_root := game.get_parent()
	if map_root != null and map_root.has_method("interaction_path"):
		var sprite: Node2D = game.actor_sprites.get(game.player.entity_id)
		if sprite == null:
			cancel_walk()
			return
		var path: PackedVector2Array = map_root.interaction_path(sprite.global_position, global_point)
		if path.is_empty():
			cancel_walk()
			game.show_fishing_notice("That spot cannot be reached from here.")
			return
		for point: Vector2 in path:
			walk_waypoints.append(_simulation_position(point))

func request_pickup(drop: GroundItemDrop) -> void:
	if not is_instance_valid(drop) or drop.collected or drop not in game.ground_drops:
		return
	cancel_walk()
	select_drop(drop)
	game._reset_held_movement()
	if at_rest() and game._collect_ground_drop(drop):
		return
	pending_pickup = drop
	_route_to(drop.global_position)

func _pickup_instance(id: int) -> void:
	var drop := instance_from_id(id) as GroundItemDrop
	if is_instance_valid(drop):
		request_pickup(drop)

func request_portal(portal: CavePortal) -> void:
	if not _portal_is_current(portal):
		return
	cancel_walk()
	clear_drop_selection()
	game._clear_target()
	game._reset_held_movement()
	var actor: CombatActor = game.combat.actors.get(game.player.entity_id)
	if actor == null or not actor.is_alive or game.player.current_hp <= 0 or _travel_is_active():
		return
	if at_rest() and portal.is_in_interaction_range(game):
		portal.try_enter(game)
		return
	pending_portal = portal
	_route_to(portal.approach_position())

func request_cooking(station: Node2D) -> void:
	if not is_instance_valid(station) or not station.is_in_group("cooking_station") or not station.is_current(game):
		return
	cancel_walk()
	clear_drop_selection()
	game._clear_target()
	game._reset_held_movement()
	if game.player.current_hp <= 0 or _travel_is_active():
		return
	if at_rest() and station.in_range(game):
		game.cooking_controller.open(station)
		return
	pending_cooking = station
	_route_to(station.approach_position())

func request_fishing(spot: Node2D) -> void:
	_request_activity(spot, "fish")

func request_crafting(station: Node2D) -> void:
	_request_activity(station, "craft")

func request_mining(deposit: Node2D) -> void:
	_request_activity(deposit, "mine")

func _request_activity(node: Node2D, kind: String) -> void:
	var approach := Approach.describe(game, node, kind)
	if approach.is_empty() or game.player.current_hp <= 0 or _travel_is_active():
		return
	cancel_walk()
	game._reset_held_movement()
	if game.offline_mining != null:
		game.offline_mining.stop("new_action")
	pending_activity = node
	pending_kind = kind
	_route_to(game.to_global(game._screen_position(approach.point.x, approach.point.y)))

func at_rest() -> bool:
	if not Network.online() and game.world.grid != null:
		game.world.grid_traveller(game.player.entity_id)
	return game.world.at_grid_rest(game.player.entity_id)

func ready_for(node: Node2D, kind: String) -> bool:
	var actor: CombatActor = game.combat.actors.get(game.player.entity_id)
	return at_rest() and Approach.in_range(game.world, actor, Approach.describe(game, node, kind))

func _pending_node() -> Node2D:
	for node: Variant in [pending_pickup, pending_portal, pending_cooking, pending_activity]:
		if is_instance_valid(node):
			return node
	return null

func _pending_type() -> String:
	if is_instance_valid(pending_pickup):
		return "pickup"
	if is_instance_valid(pending_portal):
		return "portal"
	if is_instance_valid(pending_cooking):
		return "cook"
	return pending_kind

func _goal_valid(point: Vector2) -> bool:
	var node := _pending_node()
	if node == null:
		return true
	var approach := Approach.describe(game, node, _pending_type())
	return not approach.is_empty() and (not bool(approach.sight) or game.world.has_line_of_sight(point, approach.point))

func _cooking_instance(id: int) -> void:
	var station := instance_from_id(id) as Node2D
	if is_instance_valid(station):
		request_cooking(station)

func _portal_instance(id: int) -> void:
	var portal := instance_from_id(id) as CavePortal
	if is_instance_valid(portal):
		request_portal(portal)

func _travel_is_active() -> bool:
	var travel := game.get_tree().root.get_node_or_null("SceneTravel")
	return travel != null and travel.is_transitioning()

func cancel_walk() -> void:
	if game != null and game.world != null and not Network.online():
		game.world.cancel_grid_route(game.player.entity_id)
	walking = false
	pending_pickup = null
	pending_portal = null
	pending_cooking = null
	pending_activity = null
	pending_kind = ""
	walk_waypoints.clear()
	blocked_seconds = 0.0

func update_walk(delta: float) -> void:
	if game.grid_adapter != null and not game.grid_adapter.completed:
		return
	if _travel_is_active():
		cancel_walk()
		return
	if not walking or game.spawn_menu.visible or game.item_menu.visible or game.inventory_menu.visible or game._ui_is_editing() or game.context_menu.visible:
		return
	var cooking_controller: Node = game.get("cooking_controller")
	if cooking_controller != null and cooking_controller.panel.visible:
		return
	var actor: CombatActor = game.combat.actors.get(game.player.entity_id)
	if actor == null or not actor.is_alive:
		cancel_walk()
		return
	var can_interact := at_rest()
	if pending_kind != "":
		if not is_instance_valid(pending_activity) or Approach.describe(game, pending_activity, pending_kind).is_empty():
			cancel_walk()
			return
		if ready_for(pending_activity, pending_kind):
			var node := pending_activity
			var kind := pending_kind
			cancel_walk()
			match kind:
				"fish": game.request_fishing(node)
				"craft": game.request_crafting(node)
				"mine": game.request_mining(node)
			return
	if pending_pickup != null and can_interact:
		if not is_instance_valid(pending_pickup) or pending_pickup.collected or pending_pickup not in game.ground_drops:
			cancel_walk()
			return
		if game._collect_ground_drop(pending_pickup):
			cancel_walk()
			return
	if pending_portal != null and can_interact:
		if not _portal_is_current(pending_portal):
			cancel_walk()
			return
		if pending_portal.is_in_interaction_range(game):
			pending_portal.try_enter(game)
			cancel_walk()
			return
	if pending_cooking != null and can_interact:
		if not is_instance_valid(pending_cooking) or not pending_cooking.is_current(game):
			cancel_walk()
			return
		if pending_cooking.in_range(game):
			var station := pending_cooking
			cancel_walk()
			game.cooking_controller.open(station)
			return
	var start := Vector2(actor.x, actor.y)
	if Network.online():
		# The replicated position decides when to request an interaction; only
		# the server moves the character and rechecks the actual range.
		if can_interact and _pending_node() == null and start.distance_to(destination) <= 0.72:
			cancel_walk()
		return
	if game.world.grid != null:
		game.world.move_grid_toward(actor.entity_id, destination, delta, game.PLAYER_MOVE_SPEED_TILES_PER_SECOND, _grid_reach(), Callable(), _goal_valid)
		game._update_sprite_position(actor.entity_id)
		var traveller: GridTraveller = game.world.grid_traveller(actor.entity_id)
		if not traveller.active and traveller.route.is_empty():
			# Pending interactions are attempted on the following update, using
			# the original range rules and an arrived authoritative position.
			if _pending_node() == null:
				cancel_walk()
			elif Vector2(actor.x, actor.y).distance_to(destination) > _grid_reach():
				cancel_walk()
		return
	while not walk_waypoints.is_empty() and start.distance_to(walk_waypoints[0]) <= 0.08:
		walk_waypoints.pop_front()
	var next_point := walk_waypoints[0] if not walk_waypoints.is_empty() else destination
	var offset: Vector2 = next_point - start
	if offset.length() <= 0.08:
		cancel_walk()
		return
	game.world.move_actor_continuous(actor.entity_id, offset.normalized() * minf(offset.length(), game.PLAYER_MOVE_SPEED_TILES_PER_SECOND * delta))
	game._update_sprite_position(actor.entity_id)
	blocked_seconds = blocked_seconds + delta if start.distance_to(Vector2(actor.x, actor.y)) < 0.001 else 0.0
	if blocked_seconds >= 0.6:
		cancel_walk()

func _simulation_position(global_point: Vector2) -> Vector2:
	var local: Vector2 = game.to_local(global_point)
	if game.map_scene_mode:
		return Vector2((local.x - game.map_origin.x) / game.TILE_SIZE, (game.map_origin.y + game.map_height - local.y) / game.TILE_SIZE)
	return local / game.TILE_SIZE

func _grid_reach() -> float:
	var node := _pending_node()
	if node == null:
		return 0.0
	return float(Approach.describe(game, node, _pending_type()).get("reach", 0.0))
