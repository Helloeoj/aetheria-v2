extends RefCounted
## Server/offline authority. Animation and warning ages are projections of these actions.
const PROFILE := "golem_titan"
const MAIN_KINDS := ["slam", "bolt", "eruption"]
var encounters: Dictionary = {}
var serial := 0

func forget(id: String) -> void:
	encounters.erase(id)

func advance(engine: Variant, delta: float, paused: Dictionary = {}) -> void:
	for id: String in encounters.keys():
		var state: Dictionary = encounters[id]
		var action: Dictionary = state.action
		if not action.is_empty() and not paused.has(id) and not paused.has(action.target_id):
			action.age += delta
		var boss: CombatActor = engine.actors.get(id)
		if boss == null or not boss.is_alive: forget(id)

func tick(engine: Variant, world: Variant) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for boss: CombatActor in engine.actors.values():
		if boss.boss_profile != PROFILE: continue
		var target: CombatActor = engine._refresh_monster_target(world, boss)
		if not boss.can_attack() or target == null:
			forget(boss.entity_id)
			continue
		if not encounters.has(boss.entity_id):
			var rng := RandomNumberGenerator.new()
			rng.seed = engine.random.randi()
			var pattern := RandomNumberGenerator.new()
			pattern.seed = rng.seed ^ 0x517c3
			encounters[boss.entity_id] = {"rng": rng, "pattern": pattern, "bag": [], "last": "", "next": engine.current_tick, "busy": 0, "action": {}}
		var state: Dictionary = encounters[boss.entity_id]
		var action: Dictionary = state.action
		if not action.is_empty() and not action.resolved and engine.current_tick >= action.hit_tick:
			action.resolved = true
			events.append_array(_resolve(engine, world, boss, action))
		if engine.current_tick < int(state.busy): continue
		state.action = {}
		if not engine._has_attack_line_of_sight(world, boss, target): continue
		var kind := ""
		if engine.current_tick >= int(state.next):
			kind = _next_kind(state)
			state.next = engine.current_tick + state.rng.randi_range(8, 12)
		elif int(state.next) - engine.current_tick >= 3 and engine._distance(boss, target) <= boss.attack_range:
			kind = "haymaker"
		if kind.is_empty(): continue
		serial += 1
		var cells: Array[Vector2i] = []
		if kind in ["slam", "eruption"]: cells = _cells(world, boss, target, state.pattern)
		action = {"attack_id": "titan_%d" % serial, "kind": kind, "caster_id": boss.entity_id,
			"target_id": target.entity_id, "cells": cells, "age": 0.0, "resolved": false,
			"tick": engine.current_tick, "hit_tick": engine.current_tick + (3 if kind in ["slam", "eruption"] else 2)}
		state.action = action
		state.busy = engine.current_tick + (3 if kind == "haymaker" else 4)
		var event := action.duplicate(true)
		event.type = "titan_attack_started"
		events.append(event)
	return events

func _next_kind(state: Dictionary) -> String:
	if state.bag.is_empty():
		state.bag = MAIN_KINDS.duplicate()
		for i in range(state.bag.size() - 1, 0, -1):
			var j: int = state.rng.randi_range(0, i)
			var swap: String = state.bag[i]
			state.bag[i] = state.bag[j]
			state.bag[j] = swap
		if state.bag[0] == state.last:
			var swap: String = state.bag[0]
			state.bag[0] = state.bag[1]
			state.bag[1] = swap
	state.last = state.bag.pop_front()
	return state.last

func _cells(world: Variant, boss: CombatActor, target: CombatActor, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var chosen: Array[Vector2i] = [world.occupied_cell(target.entity_id)]
	var candidates: Array[Vector2i] = []
	var center: Vector2i = world.cell_grid.cell_at(Vector2(boss.x, boss.y))
	for x in range(-7, 8):
		for y in range(-7, 8):
			var cell := center + Vector2i(x, y)
			var point: Vector2 = world.cell_grid.center(cell)
			if cell == center or chosen.has(cell) or not world.cell_grid.contains(point): continue
			if world.grid != null and not world.grid.clear_point(point): continue
			if world.monster_spawn_validator.is_valid() and not bool(world.monster_spawn_validator.call(point)): continue
			candidates.append(cell)
	while chosen.size() < 10 and not candidates.is_empty():
		var index := rng.randi_range(0, candidates.size() - 1)
		var cell := candidates[index]
		candidates.remove_at(index)
		# Prefer scattered cells; permit neighbours only if the arena is tight.
		if candidates.size() > 20 and chosen.any(func(other: Vector2i) -> bool: return absi(other.x-cell.x) <= 1 and absi(other.y-cell.y) <= 1): continue
		chosen.append(cell)
	return chosen

func _resolve(engine: Variant, world: Variant, boss: CombatActor, action: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var target: CombatActor = engine.actors.get(action.target_id)
	if action.kind == "bolt":
		if target == null or not target.is_alive: return events
		var direction := Vector2(target.x-boss.x, target.y-boss.y).normalized()
		var id := "%s_bolt" % action.attack_id
		var p := CombatProjectile.new().configure({"projectile_id": id, "spell_id": "titan_dark_bolt",
			"attacker_id": boss.entity_id, "target_id": target.entity_id, "x": boss.x, "y": boss.y,
			"dx": direction.x, "dy": direction.y, "speed": 10.0, "max_range": 40, "homing_turn_rate": 4.0,
			"initial_distance": engine._distance(boss, target), "damage_type": "magic", "accuracy": boss.accuracy,
			"damage": engine._roll_damage_for_attacker(boss, boss.min_damage, boss.max_damage),
			"crit_chance": boss.crit_chance, "crit_multiplier": boss.crit_multiplier})
		engine.projectiles[id] = p
		return events
	for victim: CombatActor in engine.actors.values():
		if victim.is_monster or not victim.is_alive or not world.permits_damage(boss.entity_id, victim.entity_id): continue
		if action.kind == "haymaker":
			if victim != target or engine._distance(boss, victim) > boss.attack_range or not engine._has_attack_line_of_sight(world, boss, victim): continue
		elif not action.cells.has(world.occupied_cell(victim.entity_id)): continue
		var style := "magic" if action.kind == "eruption" else "blunt"
		var outcome: HitOutcome = engine.calculate_hit_outcome(boss, victim, null, null, style)
		var result: Dictionary = engine.apply_hit_to_target(victim, outcome)
		events.append({"type": "entity_hit", "attacker_id": boss.entity_id, "target_id": victim.entity_id,
			"titan_attack_id": action.attack_id, "kind": action.kind, "damage": outcome.damage,
			"hit": outcome.hit, "crit": outcome.crit, "status_effects": outcome.status_effects, "hp_after": result.hp_after})
		var death: Dictionary = engine._death_event_if_needed(victim, int(result.hp_after))
		if not death.is_empty():
			death.attacker_id = boss.entity_id
			events.append(death)
	return events

func snapshot(engine: Variant, paused: Dictionary = {}) -> Dictionary:
	var actions: Array[Dictionary] = []
	for id: String in encounters:
		var boss: CombatActor = engine.actors.get(id)
		var action: Dictionary = encounters[id].action
		if boss == null or not boss.is_alive or action.is_empty() or paused.has(id) or paused.has(action.target_id): continue
		var entry := action.duplicate(true)
		entry.cells = []
		for cell: Vector2i in action.cells: entry.cells.append([cell.x, cell.y])
		actions.append(entry)
	var shots: Array[Dictionary] = []
	for p: CombatProjectile in engine.projectiles.values():
		if p.spell_id != "titan_dark_bolt" or paused.has(p.attacker_id) or paused.has(p.target_id): continue
		shots.append({"id": p.projectile_id, "x": p.x, "y": p.y, "dx": p.dx, "dy": p.dy,
			"speed": p.speed, "travelled": p.travelled, "initial_distance": p.initial_distance})
	return {"titan_actions": actions, "titan_projectiles": shots}
