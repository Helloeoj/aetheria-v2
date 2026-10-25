class_name WorldState
extends RefCounted

var player: PlayerState
var players: Dictionary = {} # Stable entity ID -> PlayerState.
var allow_player_damage := true
var monsters: Array[MonsterState] = []
var combat: CombatEngine
var world: WorldDataWorld
var projectile_walls: Dictionary = {} # wall_id -> line segment and remaining duration
var _next_projectile_wall_id := 1
var movement_min := Vector2.ZERO
var movement_max := Vector2(299.0, 299.0)
var collision_move_handler: Callable
var terrain_collision_handler: Callable
var grid: HiddenGrid
var grid_travellers: Dictionary = {}

func set_grid(value: HiddenGrid) -> void:
	grid = value
	grid_travellers.clear()
	if grid != null:
		for actor: CombatActor in combat.actors.values():
			grid_traveller(actor.entity_id)

func grid_traveller(entity_id: String) -> GridTraveller:
	var actor: CombatActor = combat.actors.get(entity_id)
	if actor == null or grid == null:
		return null
	var point := Vector2(actor.x, actor.y)
	var traveller: GridTraveller = grid_travellers.get(entity_id)
	if traveller == null:
		traveller = GridTraveller.new()
		grid_travellers[entity_id] = traveller
		traveller.reset(point, grid)
	elif not traveller.position.is_equal_approx(point):
		# Knockback, respawn or external placement invalidates a previous segment.
		traveller.reset(point, grid)
	actor.logical_cell = traveller.cell
	return traveller

func cancel_grid_route(entity_id: String) -> void:
	var traveller: GridTraveller = grid_travellers.get(entity_id)
	if traveller != null:
		traveller.cancel_route()

func move_grid_direction(entity_id: String, direction: Vector2, delta: float, speed: float) -> Vector2:
	var traveller := grid_traveller(entity_id)
	if traveller == null:
		return Vector2.ZERO
	traveller.cancel_route()
	return _advance_grid(entity_id, traveller, direction, delta, speed)

func move_grid_toward(entity_id: String, point: Vector2, delta: float, speed: float, reach: float = 0.0, allowed: Callable = Callable(), goal_valid: Callable = Callable()) -> Vector2:
	var traveller := grid_traveller(entity_id)
	if traveller == null:
		return Vector2.ZERO
	traveller.retry_delay = maxf(0.0, traveller.retry_delay - delta)
	var arrived := traveller.position.distance_to(point) <= reach \
		and (not goal_valid.is_valid() or bool(goal_valid.call(traveller.position)))
	if arrived and not traveller.active:
		traveller.cancel_route()
		return traveller.position
	if not traveller.goal.is_finite() or traveller.goal.distance_to(point) > 0.25 \
		or (not traveller.active and traveller.route.is_empty() and traveller.retry_delay <= 0.0):
		var start := traveller.target if traveller.active else traveller.position
		traveller.set_route(grid.path(start, point, reach, allowed, goal_valid), point)
	return _advance_grid(entity_id, traveller, Vector2.ZERO, delta, speed)

func _advance_grid(entity_id: String, traveller: GridTraveller, direction: Vector2, delta: float, speed: float) -> Vector2:
	var actor: CombatActor = combat.actors.get(entity_id)
	if actor == null or not actor.can_move():
		return traveller.position
	traveller.advance(delta, speed, direction, grid,
		func(motion: Vector2) -> Vector2: return move_actor_continuous(entity_id, motion))
	actor.logical_cell = traveller.cell
	return traveller.position

func _init(player_ref: PlayerState = null, monster_list: Array[MonsterState] = []) -> void:
	player = player_ref
	monsters = monster_list
	combat = CombatEngine.new()
	world = WorldDataWorld.new()

func set_movement_bounds(minimum: Vector2, maximum: Vector2) -> void:
	movement_min = minimum
	movement_max = maximum

func set_collision_handlers(move_handler: Callable, terrain_handler: Callable) -> void:
	collision_move_handler = move_handler
	terrain_collision_handler = terrain_handler

func register_player_actor(actor: CombatActor) -> void:
	combat.add_actor(actor)
	if player != null:
		player.entity_id = actor.entity_id

func player_for_actor(entity_id: String) -> PlayerState:
	if players.has(entity_id):
		return players[entity_id]
	return player if player != null and player.entity_id == entity_id else null

func player_states() -> Array:
	return players.values() if not players.is_empty() else ([player] if player != null else [])

func register_monster_actor(monster: MonsterState, actor: CombatActor) -> void:
	monster.entity_id = actor.entity_id
	monsters.append(monster)
	combat.add_actor(actor)

func remove_monster(entity_id: String) -> void:
	grid_travellers.erase(entity_id)
	combat.remove_actor(entity_id)
	for index in range(monsters.size() - 1, -1, -1):
		if monsters[index].entity_id == entity_id:
			monsters.remove_at(index)

func move_actor(entity_id: String, dx: int, dy: int) -> Vector2i:
	var position := move_actor_continuous(entity_id, Vector2(dx, dy))
	return Vector2i(roundi(position.x), roundi(position.y))

func move_actor_continuous(entity_id: String, displacement: Vector2) -> Vector2:
	var actor: CombatActor = combat.actors.get(entity_id)
	if actor == null or not actor.is_alive:
		return Vector2.ZERO
	if not actor.can_move():
		return Vector2(actor.x, actor.y)
	var start := Vector2(actor.x, actor.y)
	var bounded_target := Vector2(
		clampf(start.x + displacement.x, movement_min.x, movement_max.x),
		clampf(start.y + displacement.y, movement_min.y, movement_max.y)
	)
	var allowed_displacement := bounded_target - start
	var actual_displacement := allowed_displacement
	if collision_move_handler.is_valid():
		var movement_result: Variant = collision_move_handler.call(entity_id, allowed_displacement)
		if movement_result is Vector2:
			actual_displacement = movement_result
	actor.x = clampf(start.x + actual_displacement.x, movement_min.x, movement_max.x)
	actor.y = clampf(start.y + actual_displacement.y, movement_min.y, movement_max.y)
	var moved_player := player_for_actor(entity_id)
	if moved_player != null:
		moved_player.x = actor.x
		moved_player.y = actor.y
	else:
		for monster: MonsterState in monsters:
			if monster.entity_id == entity_id:
				monster.move_to(actor.x, actor.y)
				break
	return Vector2(actor.x, actor.y)

## Returns the nearest actor intersected by a projectile's path segment.
## World geometry can join this query when collidable tiles and objects are added.
func first_projectile_collision(start: Vector2, finish: Vector2,
		ignored_entity_id: String, collision_radius: float) -> Dictionary:
	var segment := finish - start
	var length_squared := segment.length_squared()
	var closest_fraction := INF
	var closest_actor: CombatActor
	for actor: CombatActor in combat.actors.values():
		if actor.entity_id == ignored_entity_id or not actor.is_alive:
			continue
		var fraction := _segment_circle_entry_fraction(
			start, segment, length_squared, Vector2(actor.x, actor.y), collision_radius
		)
		if fraction < 0.0:
			continue
		if fraction < closest_fraction:
			closest_fraction = fraction
			closest_actor = actor
	var closest_collision: Dictionary = {}
	if closest_actor != null:
		closest_collision = {
		"type": "actor",
		"actor": closest_actor,
		"entity_id": closest_actor.entity_id,
		"point": start + segment * closest_fraction,
		"fraction": closest_fraction
		}
	if terrain_collision_handler.is_valid():
		var terrain_result: Variant = terrain_collision_handler.call(start, finish)
		if terrain_result is Dictionary and not terrain_result.is_empty():
			if float(terrain_result.get("fraction", 1.0)) < float(closest_collision.get("fraction", INF)):
				closest_collision = terrain_result
	for wall_id_value: Variant in projectile_walls:
		var wall: Dictionary = projectile_walls[wall_id_value]
		var wall_fraction := _segment_intersection_fraction(
			start, finish, wall.get("start", Vector2.ZERO), wall.get("end", Vector2.ZERO)
		)
		if wall_fraction < 0.0 or wall_fraction >= float(closest_collision.get("fraction", INF)):
			continue
		closest_collision = {
			"type": "projectile_wall", "actor": null,
			"entity_id": String(wall_id_value),
			"point": start + segment * wall_fraction,
			"fraction": wall_fraction
		}
	return closest_collision

func has_line_of_sight(start: Vector2, finish: Vector2) -> bool:
	if not terrain_collision_handler.is_valid():
		return true
	var collision: Variant = terrain_collision_handler.call(start, finish)
	return not (collision is Dictionary and not collision.is_empty())

func add_projectile_wall(center: Vector2, facing: Vector2, length: float,
		duration: float) -> String:
	var normal := Vector2(-facing.y, facing.x).normalized()
	if normal == Vector2.ZERO:
		normal = Vector2.UP
	var half_segment := normal * maxf(0.5, length) * 0.5
	var wall_id := "spell_wall_%d" % _next_projectile_wall_id
	_next_projectile_wall_id += 1
	projectile_walls[wall_id] = {
		"start": center - half_segment,
		"end": center + half_segment,
		"remaining": maxf(0.1, duration)
	}
	return wall_id

func advance_projectile_walls(delta: float) -> void:
	var expired: Array[String] = []
	for wall_id_value: Variant in projectile_walls:
		var wall_id := String(wall_id_value)
		var wall: Dictionary = projectile_walls[wall_id]
		wall["remaining"] = float(wall.get("remaining", 0.0)) - maxf(0.0, delta)
		if float(wall.remaining) <= 0.0:
			expired.append(wall_id)
	for wall_id: String in expired:
		projectile_walls.erase(wall_id)

func _segment_circle_entry_fraction(start: Vector2, segment: Vector2,
		length_squared: float, center: Vector2, radius: float) -> float:
	var relative := start - center
	var radius_squared := radius * radius
	if relative.length_squared() <= radius_squared:
		return 0.0
	if length_squared <= 0.0:
		return -1.0
	var projection := relative.dot(segment)
	var discriminant := projection * projection - length_squared * (relative.length_squared() - radius_squared)
	if discriminant < 0.0:
		return -1.0
	var entry_distance := -projection - sqrt(discriminant)
	if entry_distance < 0.0 or entry_distance > length_squared:
		return -1.0
	return entry_distance / length_squared

func _segment_intersection_fraction(start: Vector2, finish: Vector2,
		wall_start: Vector2, wall_end: Vector2) -> float:
	var ray := finish - start
	var wall_segment := wall_end - wall_start
	var denominator := ray.cross(wall_segment)
	if is_zero_approx(denominator):
		return -1.0
	var offset := wall_start - start
	var ray_fraction := offset.cross(wall_segment) / denominator
	var wall_fraction := offset.cross(ray) / denominator
	if ray_fraction < 0.0 or ray_fraction > 1.0 or wall_fraction < 0.0 or wall_fraction > 1.0:
		return -1.0
	return ray_fraction

func tick() -> Array[Dictionary]:
	return combat.process_tick(self)

func permits_damage(attacker_id: String, target_id: String) -> bool:
	if allow_player_damage or player_for_actor(target_id) == null:
		return true
	var source: CombatActor = combat.actors.get(attacker_id)
	return source != null and source.is_monster
