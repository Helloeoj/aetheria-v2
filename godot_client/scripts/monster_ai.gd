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

func _init(monster_sprite: Variant) -> void:
	sprite = monster_sprite
	random.randomize()
	next_move_delay_ticks = random.randi_range(ROAM_MIN_DELAY_TICKS, ROAM_MAX_DELAY_TICKS)

## Called by the world simulation once per game tick.
func tick(current_game_tick: int) -> void:
	var monster: MonsterState = sprite.get("monster")
	if monster == null or not monster.is_alive or monster.in_combat:
		return
	if current_game_tick - last_move_tick < next_move_delay_ticks:
		return
	if target_x == null or target_y == null:
		_pick_new_target()
	_move_toward_target()
	last_move_tick = current_game_tick
	next_move_delay_ticks = random.randi_range(ROAM_MIN_DELAY_TICKS, ROAM_MAX_DELAY_TICKS)

func _pick_new_target() -> void:
	var radius := int(sprite.get("roam_radius"))
	var spawn_x := float(sprite.get("spawn_x"))
	var spawn_y := float(sprite.get("spawn_y"))
	while true:
		var candidate_x := spawn_x + random.randi_range(-radius, radius)
		var candidate_y := spawn_y + random.randi_range(-radius, radius)
		if Vector2(candidate_x, candidate_y).distance_to(Vector2(spawn_x, spawn_y)) <= radius:
			target_x = candidate_x
			target_y = candidate_y
			return

func _move_toward_target() -> void:
	var monster: MonsterState = sprite.get("monster")
	var dx := signi(int(target_x) - int(monster.x))
	var dy := signi(int(target_y) - int(monster.y))
	if dx == 0 and dy == 0:
		target_x = null
		target_y = null
		return
	monster.x += dx
	monster.y += dy
	sprite.call("update_position_from_monster")
