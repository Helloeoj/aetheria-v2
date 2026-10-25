class_name MonsterRoamingAI
extends RefCounted

const ROAM_MIN_DELAY_TICKS := 1
const ROAM_MAX_DELAY_TICKS := 2

var sprite: Variant
var last_move_tick := -1
var next_move_delay_ticks := 1
var target_x: Variant = null
var target_y: Variant = null
var random := RandomNumberGenerator.new()
var _world: WeakRef
var _step_goal := Vector2.ZERO
var _scheduled := false

var world: WorldState:
	get:
		return _world.get_ref() if _world != null else null

func _init(monster_sprite: Variant, shared_world: WorldState = null) -> void:
	sprite = monster_sprite
	if shared_world != null:
		_world = weakref(shared_world)
	random.randomize()
	next_move_delay_ticks = random.randi_range(ROAM_MIN_DELAY_TICKS, ROAM_MAX_DELAY_TICKS)

## Called by the world simulation once per game tick.
func tick(current_game_tick: int) -> void:
	var monster: MonsterState = sprite.get("monster")
	if monster == null or not monster.is_alive or monster.in_combat:
		_scheduled = false
		return
	if current_game_tick - last_move_tick < next_move_delay_ticks:
		return
	if _scheduled:
		return
	if target_x == null or target_y == null:
		_pick_new_target()
	_move_toward_target()
	last_move_tick = current_game_tick
	next_move_delay_ticks = random.randi_range(ROAM_MIN_DELAY_TICKS, ROAM_MAX_DELAY_TICKS)

func _pick_new_target() -> void:
	var radius := maxi(0, int(sprite.get("roam_radius")))
	var spawn_x := float(sprite.get("spawn_x"))
	var spawn_y := float(sprite.get("spawn_y"))
	for attempt in range(32):
		var candidate_x := spawn_x + random.randi_range(-radius, radius)
		var candidate_y := spawn_y + random.randi_range(-radius, radius)
		if Vector2(candidate_x, candidate_y).distance_to(Vector2(spawn_x, spawn_y)) <= radius:
			if world != null and world.grid != null:
				var monster: MonsterState = sprite.get("monster")
				var path := world.grid.path(monster.get_position(), Vector2(candidate_x, candidate_y), 0.0, _inside_roam)
				if path.is_empty():
					continue
			target_x = candidate_x
			target_y = candidate_y
			return
	target_x = null
	target_y = null

func _move_toward_target() -> void:
	var monster: MonsterState = sprite.get("monster")
	if target_x == null or target_y == null:
		return
	if world != null and world.grid != null:
		var path := world.grid.path(monster.get_position(), Vector2(target_x, target_y), 0.0, _inside_roam)
		for point: Vector2 in path:
			if point.distance_to(monster.get_position()) > 0.00001:
				_step_goal = point
				_scheduled = true
				return
		target_x = null
		target_y = null
		return
	var dx := signi(int(target_x) - int(monster.x))
	var dy := signi(int(target_y) - int(monster.y))
	if dx == 0 and dy == 0:
		target_x = null
		target_y = null
		return
	monster.x += dx
	monster.y += dy
	sprite.call("update_position_from_monster")

## Grid consumers advance every frame; ticks retain the existing roam pauses.
func advance(delta: float) -> void:
	var monster: MonsterState = sprite.get("monster")
	if world == null or world.grid == null or not _scheduled or monster == null or not monster.is_alive or monster.in_combat:
		return
	world.move_grid_toward(monster.entity_id, _step_goal, delta,
		CombatEngine.MONSTER_MOVE_SPEED_TILES_PER_SECOND, 0.0, _inside_roam)
	var traveller := world.grid_traveller(monster.entity_id)
	if traveller == null or (not traveller.active and traveller.route.is_empty()):
		_scheduled = false
	if sprite is Object and sprite.has_method("update_position_from_monster"):
		sprite.call("update_position_from_monster")

func _inside_roam(point: Vector2) -> bool:
	var spawn := Vector2(float(sprite.get("spawn_x")), float(sprite.get("spawn_y")))
	return point.distance_to(spawn) <= maxf(0.0, float(sprite.get("roam_radius")))
