class_name WorldInteraction
extends Node
## Converts pointer intent into selection, context actions and collision-aware walking.
var game: Node
var selected_drop: GroundItemDrop
var pending_pickup: GroundItemDrop
var pending_portal: CavePortal
var pending_cooking: Node2D
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
		else:
			clear_drop_selection()
			game._clear_target()
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
	if Network.online():
		var point := _simulation_position(global_point)
		Network.send_action({"type": "walk", "x": point.x, "y": point.y})
		return
	cancel_walk()
	game._clear_target()
	clear_drop_selection()
	game._reset_held_movement()
	_route_to(global_point)

func _route_to(global_point: Vector2) -> void:
	destination = _simulation_position(global_point)
	walk_waypoints.clear()
	walking = true
	if Network.online():
		Network.send_action({"type": "walk", "x": destination.x, "y": destination.y})
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
	if game._collect_ground_drop(drop):
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
	if portal.is_in_interaction_range(game):
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
	if station.in_range(game):
		game.cooking_controller.open(station)
		return
	pending_cooking = station
	_route_to(station.approach_position())

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
	walking = false
	pending_pickup = null
	pending_portal = null
	pending_cooking = null
	walk_waypoints.clear()
	blocked_seconds = 0.0

func update_walk(delta: float) -> void:
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
	if pending_pickup != null:
		if not is_instance_valid(pending_pickup) or pending_pickup.collected or pending_pickup not in game.ground_drops:
			cancel_walk()
			return
		if game._collect_ground_drop(pending_pickup):
			cancel_walk()
			return
	if pending_portal != null:
		if not _portal_is_current(pending_portal):
			cancel_walk()
			return
		if pending_portal.is_in_interaction_range(game):
			pending_portal.try_enter(game)
			cancel_walk()
			return
	if pending_cooking != null:
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
		if start.distance_to(destination) <= 0.08:
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
