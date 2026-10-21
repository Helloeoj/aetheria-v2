class_name CombatEngine
extends RefCounted

const OrbRules := preload("res://scripts/orb_effects.gd")

const MIN_HIT_CHANCE := 0.05
const MAX_HIT_CHANCE := 0.99
const DEFAULT_MELEE_RANGE := 2.0
const DEFAULT_RANGED_RANGE := 20.0
const DEFAULT_MAGIC_RANGE := 20.0
const PROJECTILE_HIT_RADIUS := 0.5
const MONSTER_MOVE_SPEED_TILES_PER_SECOND := 2.5
const HYBRID_MELEE_ATTACKS_BEFORE_SECONDARY := 3

var actors: Dictionary = {} # entity_id -> CombatActor
var projectiles: Dictionary = {} # projectile_id -> CombatProjectile
var active_spell_casts: Dictionary = {} # caster_id -> cast data
var current_tick := 0
var random := RandomNumberGenerator.new()
var _next_projectile_id := 1
var _orb_blocked_seconds: Dictionary = {}
var _orb_ice_seconds: Dictionary = {}
# UI selection is independent of starting an attack. Non-interactive adapters
# retain their existing behavior until they opt into explicit attack controls.
var player_auto_attack_enabled := true

func _init() -> void:
	random.randomize()

func add_actor(actor: CombatActor) -> void:
	if actor == null or actor.entity_id.is_empty():
		return
	actors[actor.entity_id] = actor

func register_actor(actor: CombatActor) -> void:
	add_actor(actor)

func remove_actor(entity_id: String) -> void:
	var actor: CombatActor = actors.get(entity_id)
	if actor != null:
		actor.active_orb_effects.clear()
	actors.erase(entity_id)
	_orb_blocked_seconds.erase(entity_id)
	_orb_ice_seconds.erase(entity_id)
	active_spell_casts.erase(entity_id)
	# In-flight projectiles keep their captured path and can still hit another
	# actor in the way, even if their original target leaves the world.

func process_tick(world: Variant) -> Array[Dictionary]:
	## Monster attack rolls and hits happen on the fixed combat cadence.
	var events := _process_attacks(world)
	current_tick += 1
	return events

## Movement and projectile travel are real-time. Player attacks use the equipped
## weapon's interval; monsters attack on the shared 0.6-second combat tick.
func process_realtime(world: Variant, delta: float) -> Array[Dictionary]:
	var events := _process_orb_effects(world, maxf(0.0, delta))
	var player: Variant = _get_stat(world, "player", null)
	if player != null:
		_set_stat(player, "food_cooldown_seconds", maxf(0.0,
			float(_get_stat(player, "food_cooldown_seconds", 0.0)) - maxf(0.0, delta)))
		var food_attack_delay := float(_get_stat(player, "food_attack_cooldown_seconds", 0.0))
		if food_attack_delay > 0.0:
			var equipment: Dictionary = _get_stat(player, "equipment", {})
			var interval := PlayerStats.weapon_attack_interval_seconds(equipment.get("weapon", {}))
			var captured_interval := float(_get_stat(player, "food_attack_interval_seconds", interval))
			# A slower weapon extends the meal's pending penalty. A faster weapon
			# cannot reduce it; switching back cannot repeatedly add the same time.
			food_attack_delay += maxf(0.0, interval - captured_interval)
			_set_stat(player, "food_attack_interval_seconds", maxf(captured_interval, interval))
			var actor: CombatActor = actors.get(String(_get_stat(player, "entity_id", "")))
			if actor != null:
				actor.attack_cooldown_seconds = maxf(actor.attack_cooldown_seconds, food_attack_delay)
			_set_stat(player, "food_attack_cooldown_seconds", maxf(0.0, food_attack_delay - maxf(0.0, delta)))
	events.append_array(_process_spell_casts(world, delta))
	events.append_array(_process_monster_movement(world, delta))
	events.append_array(_process_player_attacks(world, delta))
	events.append_array(_process_projectiles(world, delta))
	if world is Object and world.has_method("advance_projectile_walls"):
		world.advance_projectile_walls(delta)
	return events

func cast_spell(world: Variant, caster_id: String, spell_id: String,
		target_id: String = "", target_point: Variant = null) -> Dictionary:
	var caster: CombatActor = actors.get(caster_id)
	if caster == null or not caster.is_alive:
		return {"ok": false, "error": "Caster is not available."}
	if not caster.can_attack():
		return {"ok": false, "error": "Paralysis prevents casting."}
	var player: Variant = _get_stat(world, "player", null)
	if player == null or String(_get_stat(player, "entity_id", "")) != caster_id:
		return {"ok": false, "error": "Only the player can cast known spells."}
	if maxf(float(_get_stat(player, "food_cooldown_seconds", 0.0)),
			float(_get_stat(player, "food_attack_cooldown_seconds", 0.0))) > 0.0:
		return {"ok": false, "error": "Recover from eating before casting."}
	var spell := GameData.get_spell(spell_id)
	if spell.is_empty():
		return {"ok": false, "error": "Unknown spell: %s" % spell_id}
	var magic_level := int(_get_stat(player, "magic_level", 1))
	if not GameData.is_spell_unlocked(spell_id, magic_level):
		return {"ok": false, "error": "%s is not unlocked yet." % String(spell.get("name", spell_id))}
	if active_spell_casts.has(caster_id):
		return {"ok": false, "error": "A spell is already being cast."}

	var kind := String(spell.get("kind", "projectile"))
	var targeting := String(spell.get("targeting", "single_target"))
	if target_id.is_empty():
		target_id = String(_get_stat(player, "current_target", ""))
	var target: CombatActor = actors.get(target_id)
	var resolved_point := Vector2.ZERO
	if targeting == "ally":
		if target == null or target.is_monster != caster.is_monster:
			target = caster
		target_id = target.entity_id
		resolved_point = Vector2(target.x, target.y)
	elif targeting == "ground_point":
		if target_point is Vector2:
			resolved_point = target_point
		elif target != null and target.is_alive:
			resolved_point = Vector2(target.x, target.y)
		else:
			return {"ok": false, "error": "Choose a target location first."}
	else:
		if target == null or not target.is_alive or target.is_monster == caster.is_monster:
			return {"ok": false, "error": "Choose a living enemy target first."}
		resolved_point = Vector2(target.x, target.y)

	var cast_range := maxf(0.0, float(spell.get("range", 0.0)))
	if Vector2(caster.x, caster.y).distance_to(resolved_point) > cast_range:
		return {"ok": false, "error": "Target is out of range for %s." % String(spell.get("name", spell_id))}
	var mana_cost := maxi(0, int(spell.get("mana_cost", 0)))
	var current_mana := int(_get_stat(player, "current_mana", 0))
	if current_mana < mana_cost:
		return {"ok": false, "error": "Not enough mana to cast %s." % String(spell.get("name", spell_id))}
	_set_stat(player, "current_mana", current_mana - mana_cost)
	if target != null and target.is_monster and kind != "heal":
		_register_monster_aggression(caster, target)

	var cast_data := {
		"caster_id": caster_id, "spell": spell.duplicate(true),
		"target_id": target_id, "target_point": resolved_point,
		"orb_element": caster.orb_element if caster.attack_style == "magic" else "",
		"remaining": maxf(0.0, float(spell.get("cast_time_seconds", 0.0)))
	}
	if _is_damaging_spell(spell) and caster.active_orb_effects.has("ice"):
		cast_data.remaining = float(cast_data.remaining) / OrbRules.ATTACK_RATE_MULTIPLIER
	active_spell_casts[caster_id] = cast_data
	var cast_time := float(cast_data.remaining)
	caster.attack_cooldown_seconds = maxf(caster.attack_cooldown_seconds, cast_time)
	var started_event := {
		"type": "spell_cast_started", "caster_id": caster_id,
		"spell_id": spell_id, "spell_name": String(spell.get("name", spell_id)),
		"mana_remaining": int(_get_stat(player, "current_mana", 0)),
		"cast_time_seconds": cast_time
	}
	if cast_time <= 0.0:
		active_spell_casts.erase(caster_id)
		var completed_events := _resolve_spell_cast(world, cast_data)
		var immediate_events: Array[Dictionary] = [started_event]
		immediate_events.append_array(completed_events)
		return {"ok": true, "events": immediate_events}
	return {"ok": true, "events": [started_event]}

func _process_spell_casts(world: Variant, delta: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var completed: Array[String] = []
	for caster_id_value: Variant in active_spell_casts.keys():
		var caster_id := String(caster_id_value)
		var cast_data: Dictionary = active_spell_casts[caster_id]
		var caster: CombatActor = actors.get(caster_id)
		if caster == null or not caster.is_alive:
			completed.append(caster_id)
			continue
		if not caster.can_attack():
			continue
		cast_data["remaining"] = _advance_attack_wait(caster, float(cast_data.get("remaining", 0.0)), delta,
			_is_damaging_spell(cast_data.get("spell", {})))
		if float(cast_data.remaining) <= 0.0:
			completed.append(caster_id)
			events.append_array(_resolve_spell_cast(world, cast_data))
	for caster_id: String in completed:
		active_spell_casts.erase(caster_id)
	return events

func _resolve_spell_cast(world: Variant, cast_data: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var caster: CombatActor = actors.get(String(cast_data.get("caster_id", "")))
	var spell: Dictionary = cast_data.get("spell", {})
	if caster == null or not caster.is_alive or spell.is_empty():
		return events
	var spell_id := String(spell.get("id", ""))
	var kind := String(spell.get("kind", "projectile"))
	var target_id := String(cast_data.get("target_id", ""))
	var target: CombatActor = actors.get(target_id)
	var point_value: Variant = cast_data.get("target_point", Vector2.ZERO)
	var target_point: Vector2 = point_value if point_value is Vector2 else Vector2.ZERO

	if kind in ["projectile", "knockback"]:
		if target == null or not target.is_alive or target.is_monster == caster.is_monster:
			return [{"type": "spell_cast_failed", "caster_id": caster.entity_id,
				"spell_id": spell_id, "reason": "target_lost"}]
	elif kind == "heal":
		if target == null or not target.is_alive or target.is_monster != caster.is_monster:
			return [{"type": "spell_cast_failed", "caster_id": caster.entity_id,
				"spell_id": spell_id, "reason": "ally_lost"}]

	# Roll once after casting time has elapsed, before any effect or cast XP.
	var casting_player: Variant = _get_stat(world, "player", null)
	var magic_level := caster.magic_level
	if casting_player != null and String(_get_stat(casting_player, "entity_id", "")) == caster.entity_id:
		magic_level = int(_get_stat(casting_player, "magic_level", magic_level))
	var required_magic_level := int(spell.get("unlock_level", SkillProgression.MIN_LEVEL))
	var failure_chance := SkillProgression.magic_cast_failure_chance(magic_level, required_magic_level)
	if failure_chance > 0.0 and random.randf() < failure_chance:
		return [{
			"type": "spell_cast_failed", "caster_id": caster.entity_id,
			"spell_id": spell_id, "spell_name": String(spell.get("name", spell_id)),
			"reason": "cast_fizzled", "failure_chance": failure_chance,
			"magic_level": magic_level, "required_magic_level": required_magic_level
		}]

	if kind == "projectile":
		_register_monster_aggression(caster, target)
		var projectile := _spawn_spell_projectile(caster, target, spell,
			String(cast_data.get("orb_element", "")))
		events.append({"type": "spell_projectile_spawned", "caster_id": caster.entity_id,
			"target_id": target.entity_id, "spell_id": spell_id,
			"projectile_id": projectile.projectile_id})
	elif kind == "area":
		var radius := maxf(0.0, float(spell.get("area_radius", 0.0)))
		var hit_ids: Array[String] = []
		for candidate: CombatActor in actors.values():
			if not candidate.is_alive or candidate.is_monster == caster.is_monster:
				continue
			if Vector2(candidate.x, candidate.y).distance_to(target_point) > radius:
				continue
			_register_monster_aggression(caster, candidate)
			var spell_max_damage := _get_spell_max_damage(caster, spell)
			var spell_damage := _roll_damage_for_level(
				1 if spell_max_damage > 0 else 0, spell_max_damage, caster.magic_level
			)
			var outcome := calculate_hit_outcome(caster, candidate,
				spell_damage, caster.magic_accuracy, String(spell.get("school", "arcane")),
				spell_max_damage)
			var state := apply_hit_to_target(candidate, outcome)
			hit_ids.append(candidate.entity_id)
			events.append({"type": "spell_area_hit", "caster_id": caster.entity_id,
				"target_id": candidate.entity_id, "spell_id": spell_id,
				"damage": outcome.damage, "hit": outcome.hit, "hp_after": state.hp_after})
			events.append_array(_skill_experience_events_for_hit(
				world, caster.entity_id, candidate.entity_id, "magic", state, true
			))
			events.append_array(_try_orb_effect(String(cast_data.get("orb_element", "")),
				caster.entity_id, candidate, outcome, state))
			var death_event := _death_event_if_needed(candidate, int(state.hp_after))
			if not death_event.is_empty():
				events.append(death_event)
		events.push_front({"type": "spell_area_resolved", "caster_id": caster.entity_id,
			"spell_id": spell_id, "point": target_point, "radius": radius,
			"targets": hit_ids})
	elif kind == "heal":
		var hp_before := target.hp
		target.hp = mini(target.max_hp, target.hp + maxi(0, int(spell.get("healing", 0))))
		var player: Variant = _get_stat(world, "player", null)
		if player != null and target.entity_id == String(_get_stat(player, "entity_id", "")):
			_set_stat(player, "current_hp", target.hp)
		events.append({"type": "spell_healed", "caster_id": caster.entity_id,
			"target_id": target.entity_id, "spell_id": spell_id,
			"healing": target.hp - hp_before, "hp_after": target.hp})
	elif kind == "wall":
		if world is Object and world.has_method("add_projectile_wall"):
			var direction := (target_point - Vector2(caster.x, caster.y)).normalized()
			if direction == Vector2.ZERO:
				direction = Vector2.RIGHT
			var center := (target_point + Vector2(caster.x, caster.y)) * 0.5
			var wall_id: String = world.add_projectile_wall(center, direction,
				float(spell.get("width_tiles", 4.0)), float(spell.get("duration_seconds", 6.0)))
			events.append({"type": "spell_wall_created", "caster_id": caster.entity_id,
				"spell_id": spell_id, "wall_id": wall_id, "center": center})
	elif kind == "knockback":
		var direction := (Vector2(target.x, target.y) - Vector2(caster.x, caster.y)).normalized()
		if direction == Vector2.ZERO:
			direction = Vector2.RIGHT
		var displacement := direction * maxf(0.0, float(spell.get("knockback_distance", 0.0)))
		var start := Vector2(target.x, target.y)
		if world is Object and world.has_method("move_actor_continuous"):
			world.move_actor_continuous(target.entity_id, displacement)
		else:
			target.x += displacement.x
			target.y += displacement.y
		events.append({"type": "spell_knockback", "caster_id": caster.entity_id,
			"target_id": target.entity_id, "spell_id": spell_id,
			"from": start, "to": Vector2(target.x, target.y)})
	events.push_front({"type": "spell_cast_completed", "caster_id": caster.entity_id,
		"spell_id": spell_id, "spell_name": String(spell.get("name", spell_id))})
	events.append_array(_award_spell_cast_experience(
		world, caster.entity_id, int(spell.get("unlock_level", SkillProgression.MIN_LEVEL))
	))
	return events

func _spawn_spell_projectile(caster: CombatActor, target: CombatActor,
		spell: Dictionary, captured_orb_element: String = "") -> CombatProjectile:
	var direction := Vector2(target.x - caster.x, target.y - caster.y).normalized()
	var spell_max_damage := _get_spell_max_damage(caster, spell)
	var spell_min_damage := 1 if spell_max_damage > 0 else 0
	var projectile_id := "projectile_%d" % _next_projectile_id
	_next_projectile_id += 1
	var projectile := CombatProjectile.new().configure({
		"projectile_id": projectile_id,
		"attacker_id": caster.entity_id,
		"target_id": target.entity_id,
		"spell_id": String(spell.get("id", "")),
		"orb_element": captured_orb_element,
		"x": caster.x, "y": caster.y,
		"dx": direction.x, "dy": direction.y,
		"speed": 20.0, "max_range": int(ceil(float(spell.get("range", 20.0)))),
		"damage": _roll_damage_for_level(spell_min_damage, spell_max_damage, caster.magic_level),
		"max_damage": spell_max_damage,
		"accuracy": caster.magic_accuracy,
		"damage_type": String(spell.get("school", "arcane")),
		"crit_chance": caster.crit_chance,
		"crit_multiplier": caster.crit_multiplier,
		"requires_line_of_sight": true
	})
	projectiles[projectile_id] = projectile
	return projectile

static func distance(first: Variant, second: Variant) -> float:
	return Vector2(float(first.x), float(first.y)).distance_to(Vector2(float(second.x), float(second.y)))

static func normalize(dx: float, dy: float) -> Vector2:
	return Vector2(dx, dy).normalized()

func _process_projectiles(world: Variant, delta: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var to_delete: Array[String] = []
	if delta <= 0.0:
		return events
	for projectile_id: String in projectiles.keys():
		var projectile: CombatProjectile = projectiles[projectile_id]
		var remaining_range := maxf(0.0, float(projectile.max_range) - projectile.travelled)
		if remaining_range <= 0.0:
			to_delete.append(projectile_id)
			continue

		var start := Vector2(projectile.x, projectile.y)
		var step_distance := minf(maxf(0.0, projectile.speed * delta), remaining_range)
		var finish := start + Vector2(projectile.dx, projectile.dy) * step_distance
		projectile.x = finish.x
		projectile.y = finish.y
		projectile.travelled += step_distance

		var collision := _find_projectile_collision(world, projectile, start, finish)
		if not collision.is_empty():
			var target: CombatActor = collision.get("actor") as CombatActor
			if target == null:
				# Future terrain/object colliders stop the shot here without damage.
				events.append({
					"type": "projectile_blocked", "projectile_id": projectile_id,
					"spell_id": projectile.spell_id,
					"attacker_id": projectile.attacker_id,
					"intended_target_id": projectile.target_id,
					"collider_id": String(collision.get("entity_id", "")),
					"point": collision.get("point", finish)
				})
				to_delete.append(projectile_id)
				continue

			var projectile_attacker: CombatActor = actors.get(projectile.attacker_id)
			_register_monster_aggression(projectile_attacker, target)
			# Collision chooses the first actor. Zone, party, and PvP rules can
			# later decide whether that actor may take damage without letting the
			# projectile pass through them.
			var outcome := calculate_hit_outcome(
				projectile, target, projectile.damage, projectile.accuracy, projectile.damage_type
			)
			var state := apply_hit_to_target(target, outcome)
			events.append({
				"type": "projectile_hit", "projectile_id": projectile_id,
				"spell_id": projectile.spell_id,
				"attacker_id": projectile.attacker_id, "target_id": target.entity_id,
				"intended_target_id": projectile.target_id,
				"point": collision.get("point", finish),
				"damage": outcome.damage, "crit": outcome.crit, "hit": outcome.hit,
				"status_effects": outcome.status_effects, "hp_after": state.hp_after
			})
			events.append_array(_skill_experience_events_for_hit(
				world, projectile.attacker_id, target.entity_id, projectile.damage_type,
				state, not projectile.spell_id.is_empty()
			))
			if not projectile.orb_element.is_empty():
				events.append_array(_try_orb_effect(projectile.orb_element,
					projectile.attacker_id, target, outcome, state))
			var death_event := _death_event_if_needed(target, int(state.hp_after))
			if not death_event.is_empty():
				events.append(death_event)
			to_delete.append(projectile_id)
			continue

		if projectile.travelled >= float(projectile.max_range):
			to_delete.append(projectile_id)
			continue

		events.append({
			"type": "projectile_moved", "projectile_id": projectile_id,
			"x": projectile.x, "y": projectile.y
		})

	for projectile_id: String in to_delete:
		projectiles.erase(projectile_id)
	return events

func _find_projectile_collision(world: Variant, projectile: CombatProjectile,
		start: Vector2, finish: Vector2) -> Dictionary:
	if projectile.requires_line_of_sight:
		var actor_collision := _first_actor_collision(
			start, finish, projectile.attacker_id
		)
		if world is Object and world.has_method("first_projectile_collision"):
			var world_collision: Dictionary = world.first_projectile_collision(
				start, finish, projectile.attacker_id, PROJECTILE_HIT_RADIUS
			)
			if actor_collision.is_empty():
				return world_collision
			if world_collision.is_empty():
				return actor_collision
			# The world query may add terrain/object colliders. Compare its result
			# with actors in this engine so both use the same active actor registry.
			if float(world_collision.get("fraction", 1.0)) <= float(actor_collision.get("fraction", 1.0)):
				return world_collision
			return actor_collision
		return actor_collision

	# Explicit line-of-sight exceptions bypass intervening actors and only
	# connect to their intended target.
	var target: CombatActor = actors.get(projectile.target_id)
	if target == null or not target.is_alive:
		return {}
	var segment := finish - start
	var fraction := _segment_circle_entry_fraction(
		start, segment, segment.length_squared(), Vector2(target.x, target.y), PROJECTILE_HIT_RADIUS
	)
	if fraction < 0.0:
		return {}
	return {
		"type": "actor", "actor": target, "entity_id": target.entity_id,
		"point": start + segment * fraction, "fraction": fraction
	}

func _first_actor_collision(start: Vector2, finish: Vector2,
		ignored_entity_id: String) -> Dictionary:
	var segment := finish - start
	var length_squared := segment.length_squared()
	var closest_fraction := INF
	var closest_actor: CombatActor
	for actor: CombatActor in actors.values():
		if actor.entity_id == ignored_entity_id or not actor.is_alive:
			continue
		var fraction := _segment_circle_entry_fraction(
			start, segment, length_squared, Vector2(actor.x, actor.y), PROJECTILE_HIT_RADIUS
		)
		if fraction < 0.0 or fraction >= closest_fraction:
			continue
		closest_fraction = fraction
		closest_actor = actor
	if closest_actor == null:
		return {}
	return {
		"type": "actor", "actor": closest_actor,
		"entity_id": closest_actor.entity_id,
		"point": start + segment * closest_fraction,
		"fraction": closest_fraction
	}

func _process_monster_movement(world: Variant, delta: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if delta <= 0.0:
		return events

	for monster: MonsterState in world.monsters:
		var actor: CombatActor = actors.get(monster.entity_id)
		if actor == null or not actor.is_alive:
			continue
		var movement_delta := _unblocked_delta(actor, delta)
		if not actor.can_move() or movement_delta <= 0.0:
			continue

		var spawn_position := Vector2(actor.spawn_x, actor.spawn_y)
		var actor_position := Vector2(actor.x, actor.y)
		var target := _refresh_monster_target(world, actor)
		monster.target = target
		monster.in_combat = target != null
		_select_monster_attack_style(actor, target)

		# Let monsters pursue far enough to use their attack range, but cap their
		# own travel at 20 tiles from spawn. This gives ranged monsters room to chase.
		var attack_range := _attack_range(actor)
		var has_target := target != null
		var target_position := Vector2(target.x, target.y) if has_target else spawn_position
		var destination := target_position if has_target else spawn_position
		var distance_to_destination := actor_position.distance_to(destination)
		var stop_distance := attack_range if has_target else 0.0
		if has_target and actor.monster_attack_type == "hybrid":
			# Hybrids keep closing for melee even while a ranged fallback is selected.
			stop_distance = DEFAULT_MELEE_RANGE
		var remaining_distance := maxf(0.0, distance_to_destination - stop_distance)
		if remaining_distance <= 0.0:
			continue

		var direction := (destination - Vector2(actor.x, actor.y)).normalized()
		var travel_distance := minf(MONSTER_MOVE_SPEED_TILES_PER_SECOND * movement_delta, remaining_distance)
		if direction == Vector2.ZERO or travel_distance <= 0.0:
			continue

		var displacement := direction * travel_distance
		var next_position := actor_position + displacement
		if has_target:
			var offset_from_spawn := next_position - spawn_position
			if offset_from_spawn.length() > GameTickConfig.MONSTER_CHASE_LEASH_TILES:
				next_position = spawn_position + offset_from_spawn.normalized() * GameTickConfig.MONSTER_CHASE_LEASH_TILES
			displacement = next_position - actor_position
		if displacement.is_zero_approx():
			continue
		if world is Object and world.has_method("move_actor_continuous"):
			world.call("move_actor_continuous", actor.entity_id, displacement)
		else:
			actor.x = next_position.x
			actor.y = next_position.y
			monster.move_to(actor.x, actor.y)
		events.append({
			"type": "monster_moved", "entity_id": actor.entity_id,
			"x": actor.x, "y": actor.y,
			"returning_to_spawn": not has_target
		})
	return events

func _process_attacks(world: Variant) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for actor: CombatActor in actors.values():
		if not actor.is_monster or not actor.can_attack() or float(current_tick) + 0.000001 < actor.next_attack_tick:
			continue
		var target := _refresh_monster_target(world, actor)
		if target == null or target == actor or not target.is_alive:
			continue
		_select_monster_attack_style(actor, target)
		if not _is_within_monster_leash(actor):
			continue

		if _distance(actor, target) > _attack_range(actor):
			continue
		if not _has_attack_line_of_sight(world, actor, target):
			continue

		# Keep fractional scheduled ticks so 10% slower means a 0.9 attack rate
		# over time, rather than rounding every interval to four full ticks.
		var interval_ticks := actor.effective_attack_interval_seconds() / GameTickConfig.TICK_DURATION_SECONDS
		var scheduled_tick := actor.next_attack_tick
		# A fresh/idle actor owes a full interval after attacking now. Only a
		# fractional deadline reached within this tick retains its phase.
		if float(current_tick) - scheduled_tick >= 1.0 - 0.000001:
			scheduled_tick = float(current_tick)
		actor.next_attack_tick = scheduled_tick + interval_ticks
		var used_style := actor.attack_style
		events.append_array(_resolve_attack(world, actor, target))
		if actor.monster_attack_type == "hybrid" and _distance(actor, target) <= DEFAULT_MELEE_RANGE:
			if used_style == actor.hybrid_melee_style:
				actor.hybrid_melee_attack_count += 1
			elif used_style == actor.hybrid_secondary_style:
				actor.hybrid_melee_attack_count = 0
	return events

func _select_monster_attack_style(monster: CombatActor, target: CombatActor) -> void:
	if monster.monster_attack_type != "hybrid":
		if not monster.monster_attack_type.is_empty():
			monster.attack_style = monster.monster_attack_type
		return

	var melee_style := monster.hybrid_melee_style
	if melee_style not in ["slash", "stab", "blunt"]:
		melee_style = "slash"
	var secondary_style := monster.hybrid_secondary_style
	if secondary_style not in ["magic", "ranged"]:
		secondary_style = "magic"
	monster.hybrid_melee_style = melee_style
	monster.hybrid_secondary_style = secondary_style

	if target == null:
		monster.attack_style = melee_style
	elif _distance(monster, target) > DEFAULT_MELEE_RANGE:
		monster.attack_style = secondary_style
	elif monster.hybrid_melee_attack_count >= HYBRID_MELEE_ATTACKS_BEFORE_SECONDARY:
		monster.attack_style = secondary_style
	else:
		monster.attack_style = melee_style

func _is_within_monster_leash(monster: CombatActor) -> bool:
	var spawn_position := Vector2(monster.spawn_x, monster.spawn_y)
	var monster_position := Vector2(monster.x, monster.y)
	return spawn_position.distance_to(monster_position) <= GameTickConfig.MONSTER_CHASE_LEASH_TILES + 0.001

func _register_monster_aggression(attacker: CombatActor, target: CombatActor) -> void:
	if attacker == null or target == null or attacker.is_monster or not target.is_monster:
		return
	attacker.current_target_id = target.entity_id
	target.aggro_attacker_ids.erase(attacker.entity_id)
	target.aggro_attacker_ids.append(attacker.entity_id)

func _refresh_monster_target(world: Variant, monster: CombatActor) -> CombatActor:
	if monster == null or not monster.is_monster:
		return null

	var spawn_position := Vector2(monster.spawn_x, monster.spawn_y)
	var chase_attack_range := _attack_range(monster)
	if monster.monster_attack_type == "hybrid":
		chase_attack_range = _attack_range_for_style(monster, monster.hybrid_secondary_style)
	var chase_area_radius := GameTickConfig.MONSTER_CHASE_LEASH_TILES + chase_attack_range
	var valid_attackers: Array[String] = []
	for attacker_id: String in monster.aggro_attacker_ids:
		var attacker: CombatActor = actors.get(attacker_id)
		if attacker == null or attacker.is_monster or not attacker.is_alive:
			continue
		if not _is_actor_attacking_monster(world, attacker, monster):
			continue
		if spawn_position.distance_to(Vector2(attacker.x, attacker.y)) > chase_area_radius:
			continue
		valid_attackers.append(attacker_id)
	monster.aggro_attacker_ids = valid_attackers

	# Prefer the most recent attacker who is still alive, in the chase area,
	# and actively targeting this monster.
	for index in range(valid_attackers.size() - 1, -1, -1):
		var target: CombatActor = actors.get(valid_attackers[index])
		if target != null:
			monster.current_target_id = target.entity_id
			return target
	monster.current_target_id = ""
	return null

func _is_actor_attacking_monster(world: Variant, attacker: CombatActor,
		monster: CombatActor) -> bool:
	var player: Variant = _get_stat(world, "player", null)
	if player != null and String(_get_stat(player, "entity_id", "")) == attacker.entity_id:
		return String(_get_stat(player, "current_target", "")) == monster.entity_id
	return attacker.current_target_id == monster.entity_id

func _process_player_attacks(world: Variant, delta: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var player: Variant = _get_stat(world, "player", null)
	if player == null:
		return events
	var player_actor: CombatActor = actors.get(String(_get_stat(player, "entity_id", "")))
	if player_actor == null or player_actor.is_monster or not player_actor.is_alive:
		return events

	player_actor.attack_cooldown_seconds = _advance_attack_wait(
		player_actor, player_actor.attack_cooldown_seconds, delta)
	if not player_actor.can_attack():
		return events
	if not player_auto_attack_enabled:
		return events
	if player_actor.attack_cooldown_seconds > 0.0 or float(_get_stat(player, "food_attack_cooldown_seconds", 0.0)) > 0.0:
		return events
	var target_id := String(_get_stat(player, "current_target", ""))
	if target_id.is_empty():
		return events
	var target: CombatActor = actors.get(target_id)
	if target == null or target == player_actor or not target.is_alive or target.is_monster == player_actor.is_monster:
		return events
	if _distance(player_actor, target) > _attack_range(player_actor):
		return events
	if not _has_attack_line_of_sight(world, player_actor, target):
		return events

	events.append_array(_resolve_attack(world, player_actor, target))
	player_actor.attack_cooldown_seconds = player_actor.effective_attack_interval_seconds()
	return events

func _has_attack_line_of_sight(world: Variant, attacker: CombatActor,
		target: CombatActor) -> bool:
	if not attacker.requires_line_of_sight:
		return true
	if world is Object and world.has_method("has_line_of_sight"):
		return bool(world.call("has_line_of_sight",
			Vector2(attacker.x, attacker.y), Vector2(target.x, target.y)))
	return true

func _resolve_attack(world: Variant, attacker: CombatActor, target: CombatActor) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	_register_monster_aggression(attacker, target)
	if attacker.attack_style in ["magic", "ranged"]:
		var projectile := _spawn_projectile(attacker, target, attacker.requires_line_of_sight)
		events.append({
			"type": "projectile_spawned", "projectile_id": projectile.projectile_id,
			"attacker_id": attacker.entity_id, "target_id": target.entity_id,
			"damage_type": projectile.damage_type
		})
		return events

	var outcome := calculate_hit_outcome(attacker, target)
	var state := apply_hit_to_target(target, outcome)
	events.append({
		"type": "entity_hit", "attacker_id": attacker.entity_id,
		"target_id": target.entity_id, "damage": outcome.damage,
		"crit": outcome.crit, "hit": outcome.hit,
		"status_effects": outcome.status_effects, "hp_after": state.hp_after
	})
	events.append_array(_skill_experience_events_for_hit(
		world, attacker.entity_id, target.entity_id, attacker.attack_style, state, false
	))
	var death_event := _death_event_if_needed(target, int(state.hp_after))
	if not death_event.is_empty():
		events.append(death_event)
	return events

## LOS is stored per projectile so a specific spell can override the default.
func _spawn_projectile(attacker: CombatActor, target: CombatActor,
		requires_line_of_sight: bool = true) -> CombatProjectile:
	var direction := Vector2(target.x - attacker.x, target.y - attacker.y).normalized()
	var profile := PlayerStats.get_default_projectile_profile(attacker.attack_style)
	var projectile_speed_per_second := float(profile.get("speed", 20.0))
	if not attacker.is_monster and attacker.projectile_speed > 0.0:
		projectile_speed_per_second = attacker.projectile_speed
	var minimum := maxi(0, attacker.min_damage)
	var maximum := maxi(minimum, attacker.max_damage)
	var projectile_id := "projectile_%d" % _next_projectile_id
	_next_projectile_id += 1
	var projectile := CombatProjectile.new().configure({
		"projectile_id": projectile_id,
		"attacker_id": attacker.entity_id,
		"target_id": target.entity_id,
		"x": float(attacker.x), "y": float(attacker.y),
		"dx": direction.x, "dy": direction.y,
		"speed": projectile_speed_per_second, "max_range": int(ceil(_attack_range(attacker))),
		"travelled": 0.0,
		"damage": _roll_damage_for_attacker(attacker, minimum, maximum),
		"max_damage": maximum if not attacker.is_monster else -1,
		"accuracy": clampf(attacker.accuracy, 0.0, 1.0),
		"damage_type": attacker.attack_style,
		"orb_element": attacker.orb_element if attacker.attack_style == "magic" else "",
		"crit_chance": attacker.crit_chance,
		"crit_multiplier": attacker.crit_multiplier,
		"status_effects": attacker.status_effects,
		"requires_line_of_sight": requires_line_of_sight
	})
	projectiles[projectile_id] = projectile
	return projectile

func fight_turn(attacker_id: String, defender_id: String, world: Variant = null) -> Array:
	var attacker: CombatActor = actors.get(attacker_id)
	var defender: CombatActor = actors.get(defender_id)
	if attacker == null or defender == null or not attacker.is_alive or not defender.is_alive:
		return [0, false, defender == null or not defender.is_alive]
	_register_monster_aggression(attacker, defender)
	var outcome := calculate_hit_outcome(attacker, defender)
	var state := apply_hit_to_target(defender, outcome)
	if world != null:
		_skill_experience_events_for_hit(
			world, attacker.entity_id, defender.entity_id, attacker.attack_style, state, false
		)
	return [outcome.damage, outcome.crit, int(state.hp_after) <= 0]

func calculate_hit_chance(attacker: Variant, target: Variant,
		forced_accuracy: Variant = null, damage_type: String = "") -> float:
	var raw_accuracy := float(forced_accuracy) if forced_accuracy != null else float(_get_stat(attacker, "accuracy", 0.5))
	var accuracy := clampf(raw_accuracy, 0.0, 1.0)
	var attack_style := damage_type if not damage_type.is_empty() else String(_get_stat(attacker, "attack_style", "slash"))
	var resistance_value: Variant = _get_stat(target, "resistances", {})
	var resistances: Dictionary = resistance_value if resistance_value is Dictionary else {}
	var resistance_style := _resistance_style_for_damage_type(attack_style)
	var resistance := float(resistances.get(resistance_style, 0.0))
	var melee_roll := float(_get_stat(attacker, "melee_attack_roll", -1.0))
	if forced_accuracy == null and attack_style in PlayerStats.MELEE_STYLES and melee_roll >= 0.0:
		var defence_rolls: Dictionary = _get_stat(target, "melee_defence_rolls", {})
		var defence_roll := float(defence_rolls.get(attack_style, PlayerStats.melee_defence_roll(
			int(_get_stat(target, "defence_level", 1)), resistance
		)))
		if target is CombatActor and target.active_orb_effects.has("hurricane"):
			# Preserve the target's cached equipment/resistance contribution while
			# replacing only its level contribution. Base stats are never mutated.
			defence_roll *= float(target.effective_defence_level() + 8) / float(target.defence_level + 8)
		return PlayerStats.melee_hit_chance(melee_roll, defence_roll)
	# Player equipment uses a bounded fractional reduction in incoming hit chance.
	# Authored monster resistances retain their existing accuracy-offset behavior.
	var adjusted_accuracy := accuracy - resistance
	if bool(_get_stat(target, "uses_armour_rating", false)):
		adjusted_accuracy = accuracy * (1.0 - clampf(
			resistance, PlayerStats.MIN_ARMOUR_RESISTANCE, PlayerStats.MAX_ARMOUR_RESISTANCE
		))
	return clampf(adjusted_accuracy, MIN_HIT_CHANCE, MAX_HIT_CHANCE)

func calculate_hit_outcome(attacker: Variant, target: Variant,
		forced_damage: Variant = null, forced_accuracy: Variant = null,
		damage_type: String = "", forced_max_damage: int = -1) -> HitOutcome:
	var effective_accuracy := calculate_hit_chance(attacker, target, forced_accuracy, damage_type)
	if random.randf() >= effective_accuracy:
		return HitOutcome.new(0, false, false, [])

	var damage: int
	var maximum_damage_cap := -1
	if forced_damage != null:
		damage = maxi(0, int(forced_damage))
		if attacker is CombatProjectile:
			maximum_damage_cap = int(_get_stat(attacker, "max_damage", -1))
		elif forced_max_damage >= 0:
			maximum_damage_cap = forced_max_damage
	else:
		var minimum := maxi(0, int(_get_stat(attacker, "min_damage", 0)))
		var maximum := maxi(minimum, int(_get_stat(attacker, "max_damage", maxi(minimum, 1))))
		var uses_melee_roll := String(_get_stat(attacker, "attack_style", "")) in PlayerStats.MELEE_STYLES and float(_get_stat(attacker, "melee_attack_roll", -1.0)) >= 0.0
		if uses_melee_roll:
			minimum = 1
			var melee_maximum := int(_get_stat(attacker, "melee_max_damage", -1))
			maximum = maxi(1, melee_maximum if melee_maximum >= 0 else maximum)
		if uses_melee_roll or not bool(_get_stat(attacker, "is_monster", false)):
			maximum_damage_cap = maximum
		damage = _roll_damage_for_attacker(attacker, minimum, maximum)

	var crit_chance := clampf(float(_get_stat(attacker, "crit_chance", 0.0)), 0.0, 1.0)
	var crit_multiplier := maxf(1.0, float(_get_stat(attacker, "crit_multiplier", 1.0)))
	var crit := random.randf() < crit_chance
	if crit:
		damage = int(float(damage) * crit_multiplier)
		if maximum_damage_cap >= 0:
			damage = mini(damage, maximum_damage_cap)
	var status_value: Variant = _get_stat(attacker, "status_effects", [])
	var effects: Array[String] = []
	if status_value is Array:
		for status: Variant in status_value:
			effects.append(String(status))
	var resolved_type := damage_type if not damage_type.is_empty() else String(_get_stat(attacker, "attack_style", "slash"))
	var reductions: Dictionary = _get_stat(target, "damage_reductions", {})
	var reduction := clampf(float(reductions.get(_resistance_style_for_damage_type(resolved_type), 0.0)), 0.0, 1.0)
	damage = floori(float(damage) * (1.0 - reduction) + 0.000001)
	return HitOutcome.new(damage, crit, true, effects)

func _roll_damage_for_attacker(attacker: Variant, minimum: int, maximum: int) -> int:
	if String(_get_stat(attacker, "attack_style", "")) in PlayerStats.MELEE_STYLES and float(_get_stat(attacker, "melee_attack_roll", -1.0)) >= 0.0:
		return random.randi_range(minimum, maximum)
	return _roll_damage_for_level(
		minimum, maximum, int(_get_stat(attacker, "damage_roll_level", 0))
	)

func _roll_damage_for_level(minimum: int, maximum: int, skill_level: int) -> int:
	if maximum <= minimum:
		return minimum
	if skill_level <= 0:
		return random.randi_range(minimum, maximum)

	var max_skill_level := maxi(2, SkillProgression.MAX_LEVEL)
	var skill_progress := clampf(float(skill_level - 1) / float(max_skill_level - 1), 0.0, 1.0)
	# Higher offensive skill still allows the full range but favors rolls toward its upper end.
	var roll_power := lerpf(1.0, 0.5, skill_progress)
	var roll_fraction := pow(random.randf(), roll_power)
	var damage_span := maximum - minimum
	var damage_offset := mini(damage_span, int(roll_fraction * float(damage_span + 1)))
	return minimum + damage_offset

func _get_spell_max_damage(caster: CombatActor, spell: Dictionary) -> int:
	var base_damage := maxi(0, int(spell.get("damage", 0)))
	if base_damage == 0:
		return 0
	# Spell data provides the level-100 cap. Magic grows each spell from half of
	# that cap at level 1 to its full listed power at level 100.
	var magic_progress := (
		float(clampi(caster.magic_level, 1, SkillProgression.MAX_LEVEL))
		/ float(SkillProgression.MAX_LEVEL)
	)
	var damage_scale := lerpf(0.5, 1.0, magic_progress)
	return maxi(1, roundi(float(base_damage) * damage_scale))

func _resistance_style_for_damage_type(damage_type: String) -> String:
	if damage_type in ["magic", "fire", "water", "earth", "air", "arcane"]:
		return "magic"
	return damage_type

func apply_hit_to_target(target: Variant, outcome: HitOutcome) -> Dictionary:
	var hp_key := "hp" if _has_stat(target, "hp") else "current_hp"
	var current_hp := maxi(0, int(_get_stat(target, hp_key, _get_stat(target, "max_hp", 0))))
	var new_hp := current_hp
	if outcome.hit and current_hp > 0:
		new_hp = maxi(0, current_hp - maxi(0, outcome.damage))
		_set_stat(target, hp_key, new_hp)
		if new_hp == 0:
			_set_stat(target, "is_alive", false)
			if target is CombatActor:
				target.active_orb_effects.clear()
	return {
		"hp_before": current_hp, "hp_after": new_hp,
		"status_effects": outcome.status_effects
	}

func _try_orb_effect(element: String, source_id: String, target: CombatActor,
		outcome: HitOutcome, hit_state: Dictionary) -> Array[Dictionary]:
	if not outcome.hit or not target.is_alive or not OrbRules.DURATIONS.has(element):
		return []
	var actual_damage := int(hit_state.hp_before) - int(hit_state.hp_after)
	if actual_damage <= 0 or target.active_orb_effects.has(element):
		return []
	if random.randf() >= OrbRules.PROC_CHANCE:
		return []
	target.active_orb_effects[element] = OrbRules.create(element, source_id, actual_damage)
	if element == "ice":
		target.attack_cooldown_seconds /= OrbRules.ATTACK_RATE_MULTIPLIER
		if active_spell_casts.has(target.entity_id):
			var cast_data: Dictionary = active_spell_casts[target.entity_id]
			if _is_damaging_spell(cast_data.get("spell", {})):
				cast_data.remaining = float(cast_data.remaining) / OrbRules.ATTACK_RATE_MULTIPLIER
		if target.is_monster:
			target.next_attack_tick = float(current_tick) + maxf(0.0,
				target.next_attack_tick - float(current_tick)) / OrbRules.ATTACK_RATE_MULTIPLIER
	return [{"type": "orb_effect_applied", "attacker_id": source_id,
		"target_id": target.entity_id, "element": element,
		"duration_seconds": OrbRules.DURATIONS[element]}]

func _is_damaging_spell(spell: Dictionary) -> bool:
	return String(spell.get("kind", "")) in ["projectile", "area"] and int(spell.get("damage", 0)) > 0

func _unblocked_delta(actor: CombatActor, delta: float) -> float:
	return maxf(0.0, delta - float(_orb_blocked_seconds.get(actor.entity_id, 0.0)))

func _advance_attack_wait(actor: CombatActor, remaining: float, delta: float,
		affected_by_ice: bool = true) -> float:
	var ice_remaining := float(_orb_ice_seconds.get(actor.entity_id, -1.0))
	if affected_by_ice and ice_remaining >= 0.0 and ice_remaining <= delta:
		var blocked := float(_orb_blocked_seconds.get(actor.entity_id, 0.0))
		var slowed_time := maxf(0.0, ice_remaining - blocked)
		var recovered_time := maxf(0.0, delta - maxf(ice_remaining, blocked))
		return maxf(0.0, maxf(0.0, remaining - slowed_time) * OrbRules.ATTACK_RATE_MULTIPLIER - recovered_time)
	return maxf(0.0, remaining - _unblocked_delta(actor, delta))

func _process_orb_effects(world: Variant, delta: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	_orb_blocked_seconds.clear()
	_orb_ice_seconds.clear()
	for actor: CombatActor in actors.values():
		if not actor.is_alive:
			actor.active_orb_effects.clear()
			continue
		for element: String in actor.active_orb_effects.keys():
			if not actor.is_alive:
				break
			var effect: Dictionary = actor.active_orb_effects[element]
			var elapsed := minf(delta, maxf(0.0, float(effect.remaining)))
			if element == "ice":
				_orb_ice_seconds[actor.entity_id] = maxf(0.0, float(effect.remaining))
			if element == "lightning":
				_orb_blocked_seconds[actor.entity_id] = elapsed
			if element == "fire":
				effect.tick_remaining = float(effect.tick_remaining) - elapsed
				while int(effect.ticks_left) > 0 and float(effect.tick_remaining) <= 0.000001 and actor.is_alive:
					effect.ticks_left = int(effect.ticks_left) - 1
					effect.tick_remaining = float(effect.tick_remaining) + GameTickConfig.TICK_DURATION_SECONDS
					effect.fractional_damage = float(effect.fractional_damage) + float(effect.damage_per_tick)
					var damage := floori(float(effect.fractional_damage) + 0.000001)
					effect.fractional_damage = float(effect.fractional_damage) - float(damage)
					if damage <= 0:
						continue
					var outcome := HitOutcome.new(damage, false, true, [])
					var state := apply_hit_to_target(actor, outcome)
					events.append({"type": "entity_hit", "attacker_id": String(effect.source_id),
						"target_id": actor.entity_id, "damage": damage, "crit": false,
						"hit": true, "status_effects": [], "hp_after": state.hp_after,
						"damage_over_time": true, "orb_element": "fire"})
					events.append_array(_skill_experience_events_for_hit(world,
						String(effect.source_id), actor.entity_id, "magic", state, false))
					var death_event := _death_event_if_needed(actor, int(state.hp_after))
					if not death_event.is_empty():
						death_event["attacker_id"] = String(effect.source_id)
						events.append(death_event)
			if not actor.is_alive:
				break
			effect.remaining = maxf(0.0, float(effect.remaining) - delta)
			if float(effect.remaining) <= 0.000001:
				if element == "ice" and actor.is_monster:
					actor.next_attack_tick = float(current_tick) + maxf(0.0,
						actor.next_attack_tick - float(current_tick)) * OrbRules.ATTACK_RATE_MULTIPLIER
				actor.active_orb_effects.erase(element)
				events.append({"type": "orb_effect_expired", "target_id": actor.entity_id, "element": element})
	return events

func _skill_experience_events_for_hit(world: Variant, attacker_id: String,
		target_id: String, attack_style: String, hit_state: Dictionary,
		is_spell: bool) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var player: Variant = _get_stat(world, "player", null)
	if player == null:
		return events
	var player_id := String(_get_stat(player, "entity_id", ""))
	var actual_damage := maxi(0, int(hit_state.get("hp_before", 0)) - int(hit_state.get("hp_after", 0)))
	if actual_damage <= 0:
		return events

	var player_actor: CombatActor = actors.get(player_id)
	if target_id == player_id and player_actor != null:
		_set_stat(player, "current_hp", player_actor.hp)

	if attacker_id == player_id:
		if is_spell or attack_style == "magic":
			_append_skill_experience_event(events, player, "magic",
				SkillProgression.damage_experience("magic", actual_damage))
		elif attack_style == "ranged":
			_append_skill_experience_event(events, player, "range",
				SkillProgression.damage_experience("range", actual_damage))
		else:
			_append_skill_experience_event(events, player, "attack",
				SkillProgression.damage_experience("attack", actual_damage))
			_append_skill_experience_event(events, player, "strength",
				SkillProgression.damage_experience("strength", actual_damage))
		_append_skill_experience_event(events, player, "health",
			SkillProgression.damage_experience("health", actual_damage))
	elif target_id == player_id:
		_append_skill_experience_event(events, player, "defense",
			SkillProgression.damage_experience("defense", actual_damage))

	if player_actor != null:
		if player.has_method("get_max_hp"):
			player_actor.max_hp = int(player.get_max_hp())
		player_actor.hp = int(_get_stat(player, "current_hp", player_actor.hp))
		player_actor.is_alive = player_actor.hp > 0
	return events

func _award_spell_cast_experience(world: Variant, caster_id: String,
		unlock_level: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var player: Variant = _get_stat(world, "player", null)
	if player == null or caster_id != String(_get_stat(player, "entity_id", "")):
		return events
	_append_skill_experience_event(events, player, "magic",
		SkillProgression.magic_experience_for_cast(unlock_level))
	return events

func _append_skill_experience_event(events: Array[Dictionary], player: Variant,
		skill_id: String, amount: int) -> void:
	if amount <= 0 or not player.has_method("add_skill_experience"):
		return
	var old_level := int(player.get_skill_level(skill_id))
	var old_experience := int(player.get_skill_experience(skill_id))
	var old_combat_level := int(player.get_combat_level())
	var new_level := int(player.add_skill_experience(skill_id, amount))
	var new_experience := int(player.get_skill_experience(skill_id))
	var new_combat_level := int(player.get_combat_level())
	var experience_gained := new_experience - old_experience
	if experience_gained <= 0:
		return
	events.append({
		"type": "skill_experience_gained",
		"skill": skill_id,
		"skill_name": String(SkillProgression.SKILL_NAMES[skill_id]),
		"experience_gained": experience_gained,
		"experience": new_experience,
		"old_level": old_level,
		"new_level": new_level,
		"level_up": new_level > old_level,
		"old_combat_level": old_combat_level,
		"new_combat_level": new_combat_level,
		"combat_level_up": new_combat_level > old_combat_level
	})

func _attack_range(actor: CombatActor) -> float:
	return _attack_range_for_style(actor, actor.attack_style)

func _attack_range_for_style(actor: CombatActor, attack_style: String) -> float:
	var configured_range := maxf(0.0, actor.attack_range)
	if attack_style in ["slash", "stab", "blunt"]:
		return configured_range if configured_range > 0.0 else DEFAULT_MELEE_RANGE
	if attack_style == "magic":
		return configured_range if configured_range > DEFAULT_MELEE_RANGE else DEFAULT_MAGIC_RANGE
	if attack_style == "ranged":
		return configured_range if configured_range > DEFAULT_MELEE_RANGE else DEFAULT_RANGED_RANGE
	return DEFAULT_MELEE_RANGE

func _segment_circle_entry_fraction(start: Vector2, segment: Vector2,
		length_squared: float, center: Vector2, radius: float) -> float:
	var relative := start - center
	if relative.length_squared() <= radius * radius:
		return 0.0
	if length_squared <= 0.0:
		return -1.0
	var projection := relative.dot(segment)
	var discriminant := projection * projection - length_squared * (relative.length_squared() - radius * radius)
	if discriminant < 0.0:
		return -1.0
	var entry_parameter := -projection - sqrt(discriminant)
	if entry_parameter < 0.0 or entry_parameter > length_squared:
		return -1.0
	return entry_parameter / length_squared

func _death_event_if_needed(target: Variant, hp_after: int) -> Dictionary:
	if hp_after > 0 or bool(_get_stat(target, "death_reported", false)):
		return {}
	_set_stat(target, "death_reported", true)
	return {
		"type": "entity_died",
		"entity_id": String(_get_stat(target, "entity_id", "")),
		"name": String(_get_stat(target, "name", ""))
	}

func _is_alive(entity: Variant) -> bool:
	if entity == null:
		return false
	var alive_value: Variant = _get_stat(entity, "is_alive", null)
	if alive_value != null:
		return bool(alive_value)
	return int(_get_stat(entity, "hp", _get_stat(entity, "current_hp", 0))) > 0

func _distance(first: Variant, second: Variant) -> float:
	return distance(first, second)

func _get_stat(source: Variant, key: String, default_value: Variant = null) -> Variant:
	if source is Dictionary:
		return source.get(key, default_value)
	if source is Object:
		var value: Variant = source.get(key)
		return default_value if value == null else value
	return default_value

func _has_stat(source: Variant, key: String) -> bool:
	if source is Dictionary:
		return source.has(key)
	if source is Object:
		return source.get(key) != null
	return false

func _set_stat(target: Variant, key: String, value: Variant) -> void:
	if target is Dictionary:
		target[key] = value
	elif target is Object and _has_stat(target, key):
		target.set(key, value)
