class_name AuthoritativeRegion
extends RefCounted
## One server simulation per region. Commands carry intent; rules and clock stay here.
const Activities := preload("res://network/region_activities.gd")
const MiningEngine := preload("res://scripts/mining_service.gd")
const SPEED := 4.0
const INPUT_LIFETIME := 0.25
const STEP := 1.0 / 60.0
const SCHEMA := {
	"move": ["direction"], "walk": ["x", "y"], "target": ["target_id"],
	"attack": ["target_id"], "cast": ["spell_id", "target_id", "x", "y"],
	"equip": ["item_name"], "unequip": ["slot"], "eat": ["item_name"],
	"set_quick_food": ["item_name"], "craft": ["station_id", "recipe_id", "quantity"],
	"purchase": ["station_id", "item_name", "quantity"],
	"pickup": ["drop_id"], "drop": ["item_name", "quantity"],
	"fish_start": ["station_id", "rod", "bait", "action_id", "start_token"], "fish_stop": [],
	"mine_start": ["deposit_id", "deposit_generation"], "mine_stop": [],
	"fish_input": ["action", "steering", "encounter_id", "input_id", "action_id", "expected_state", "phase_elapsed", "plan_ack"], "pale_move": ["slot"], "pale_drop": ["slot"],
	"cook_start": ["station_id", "item_name", "quantity", "start_token", "action_id"], "cook_flip": ["encounter_id", "prompt_id", "action_id"], "cook_cancel": [],
	"attack_style": ["style"], "select_spell": ["spell_id"]
}
var region_id := ""
var players: Dictionary = {}
var frozen: Dictionary = {}
var dirty: Dictionary = {}
var world: WorldState
var geometry_game: Node
var stations: Dictionary = {}
var drops: Dictionary = {} # Published ground items only; hidden mutations never enter snapshots.
var _ground_mutations: Dictionary = {} # character_id -> ordered unpublished/reserved mutations
var _mutation_serials: Dictionary = {} # Monotonic across disconnect/rejoin and discard.
var activities: RefCounted
var mining: RefCounted
var _mining_nodes: Dictionary = {}
var _inputs: Dictionary = {}
var _walks: Dictionary = {}
var _attacking: Dictionary = {}
var _bodies: Dictionary = {}
var _pending_refresh: Dictionary = {}
var _clock := 0.0
var _tick_elapsed := 0.0
var _loot := LootSystem.new()

func configure(id: String, game: Node) -> void:
	region_id = id
	geometry_game = game
	world = WorldState.new()
	world.allow_player_damage = false
	if game != null:
		var old_world: Variant = game.get("world")
		if old_world is WorldState:
			world.set_movement_bounds(old_world.movement_min, old_world.movement_max)
		elif game.get("map_width") != null and game.get("map_height") != null:
			world.set_movement_bounds(Vector2(0.5, 0.5), Vector2(float(game.get("map_width")) / 32.0 - 0.5, float(game.get("map_height")) / 32.0 - 0.5))
		if game.has_method("_move_actor_with_map_collision"):
			world.collision_move_handler = Callable(self, "_move_collision")
		if game.has_method("_query_map_terrain_collision"):
			world.terrain_collision_handler = Callable(game, "_query_map_terrain_collision")
	activities = Activities.new()
	activities.configure(self)
	var definitions := MiningDefinitions.new()
	var loaded := definitions.load_data()
	if not loaded.ok:
		push_warning("Mining disabled: " + str(loaded.errors))
	mining = MiningEngine.new()
	var owner: WeakRef = weakref(self)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	mining.configure(definitions,
		func(character: String, deposit: String) -> Dictionary:
			var region: RefCounted = owner.get_ref()
			return region._mining_context(character, deposit) if region != null else {},
		func(character: String, _event: Dictionary) -> void:
			var region: RefCounted = owner.get_ref()
			if region != null:
				region.dirty[character] = true,
		rng)
	_discover_stations()
	_discover_mining()

func add_player(character_id: String, player: PlayerState) -> void:
	if character_id.is_empty() or player == null or players.has(character_id):
		return
	player.entity_id = character_id
	player.current_target = ""
	player.in_combat = false
	var position := _safe_position(player.get_position())
	if not position.is_finite():
		push_warning("No passable character spawn in region " + region_id)
		return
	player.x = position.x
	player.y = position.y
	players[character_id] = player
	world.players[character_id] = player
	_refresh_actor(character_id)
	_add_body(character_id)
	dirty[character_id] = true

func remove_player(character_id: String) -> void:
	activities.close(character_id)
	mining.forget_player(character_id)
	discard_mutations(character_id)
	# Region exits end this gameplay generation. Its attacks must not resume or
	# credit a different PlayerState when the same stable character ID rejoins.
	for projectile_id: String in world.combat.projectiles.keys():
		var projectile: CombatProjectile = world.combat.projectiles[projectile_id]
		if projectile.attacker_id == character_id or projectile.target_id == character_id:
			world.combat.projectiles.erase(projectile_id)
	for actor: CombatActor in world.combat.actors.values():
		for element: String in actor.active_orb_effects.keys():
			var effect: Dictionary = actor.active_orb_effects[element]
			if String(effect.get("source_id", "")) == character_id:
				if element == "ice" and actor.is_monster:
					actor.next_attack_tick = float(world.combat.current_tick) + maxf(0.0,
						actor.next_attack_tick - float(world.combat.current_tick)) * preload("res://scripts/orb_effects.gd").ATTACK_RATE_MULTIPLIER
				actor.active_orb_effects.erase(element)
	players.erase(character_id)
	world.grid_travellers.erase(character_id)
	world.players.erase(character_id)
	world.combat.remove_actor(character_id)
	world.combat.player_attack_enabled.erase(character_id)
	_inputs.erase(character_id)
	_walks.erase(character_id)
	_attacking.erase(character_id)
	frozen.erase(character_id)
	if _bodies.has(character_id):
		var body: Node = _bodies[character_id]
		if is_instance_valid(body):
			body.queue_free()
		_bodies.erase(character_id)
		if geometry_game != null and geometry_game.get("actor_sprites") is Dictionary:
			geometry_game.get("actor_sprites").erase(character_id)

func submit(character_id: String, command: Dictionary) -> Dictionary:
	_adopt_grid()
	if not players.has(character_id) or frozen.has(character_id):
		return _result(false, "unavailable", "Character is unavailable.")
	var validation := _validate(command)
	if not validation.ok:
		return validation
	var kind: String = command.type
	var player: PlayerState = players[character_id]
	var actor: CombatActor = world.combat.actors.get(character_id)
	if actor == null or not actor.is_alive:
		return _result(false, "dead", "You must be alive.")
	if world.grid != null and kind in ["fish_start", "cook_start", "mine_start", "craft", "purchase"]:
		if world.grid_traveller(character_id).active:
			return _result(false, "moving", "Finish your step before starting an activity.")
	if kind in ["move", "walk", "target", "attack", "cast"]:
		activities.close(character_id)
	match kind:
		"move":
			var direction := _vector(command.get("direction", null))
			if not direction.is_finite():
				return _result(false, "invalid", "Choose a finite movement direction.")
			_inputs[character_id] = {"direction": direction.limit_length(1.0), "until": _clock + INPUT_LIFETIME}
			_walks.erase(character_id)
			_attacking.erase(character_id)
			world.combat.player_attack_enabled[character_id] = false
			world.cancel_grid_route(character_id)
		"walk":
			if not command.has("x") or not command.has("y"):
				return _result(false, "invalid", "Choose a destination.")
			var point := Vector2(float(command.x), float(command.y))
			if not _inside(point):
				return _result(false, "blocked", "The destination has no clear path.")
			if world.grid != null:
				if world.grid.path(player.get_position(), point).is_empty():
					return _result(false, "blocked", "The destination has no clear path.")
			elif not world.has_line_of_sight(player.get_position(), point):
				return _result(false, "blocked", "The destination has no clear path.")
			_walks[character_id] = point
			_inputs.erase(character_id)
			_attacking.erase(character_id)
			world.combat.player_attack_enabled[character_id] = false
		"target", "attack":
			var target_id := String(command.get("target_id", ""))
			var target: CombatActor = world.combat.actors.get(target_id)
			if not target_id.is_empty() and (target == null or not target.is_alive or not target.is_monster):
				return _result(false, "target", "Choose a living monster.")
			player.current_target = target_id
			actor.current_target_id = target_id
			world.combat.player_attack_enabled[character_id] = kind == "attack"
			if kind == "attack" and not target_id.is_empty():
				_attacking[character_id] = target_id
			else:
				_attacking.erase(character_id)
			_inputs.erase(character_id)
			_walks.erase(character_id)
			world.cancel_grid_route(character_id)
		"cast":
			var target_id := String(command.get("target_id", ""))
			if not target_id.is_empty():
				var target: CombatActor = world.combat.actors.get(target_id)
				if target == null or not target.is_monster:
					return _result(false, "target", "Choose a monster target.")
			var point: Variant = null
			if command.has("x") and command.has("y"):
				point = Vector2(float(command.x), float(command.y))
				if not _inside(point):
					return _result(false, "bounds", "Choose a location inside this region.")
			var outcome := world.combat.cast_spell(world, character_id, String(command.get("spell_id", "")), target_id, point)
			if not outcome.ok:
				return _result(false, "cast", String(outcome.get("error", "Cannot cast.")))
			_handle_events(outcome.get("events", []))
			dirty[character_id] = true
		"equip", "unequip":
			var hands := [player.equipment.weapon.duplicate(), player.equipment.shield.duplicate()]
			var before := var_to_str([player.equipment, player.backpack, player.quiver_item, player.quiver_amount])
			var message: String = InventorySystem.equip_item(player, String(command.get("item_name", ""))) if kind == "equip" else InventorySystem.unequip_slot(player, String(command.get("slot", "")))
			if before == var_to_str([player.equipment, player.backpack, player.quiver_item, player.quiver_amount]):
				return _result(false, "equipment", message)
			if hands != [player.equipment.weapon, player.equipment.shield]:
				mining.stop(character_id, "equipment")
			_refresh_actor(character_id)
			dirty[character_id] = true
			return _result(true, "ok", message)
		"eat":
			if activities.active(character_id):
				return _result(false, "busy", "Finish your activity first.")
			var item_name := String(command.get("item_name", player.get_quick_food()))
			var reason := FishingSession.eating_error(player, item_name, world.combat)
			if not reason.is_empty():
				return _result(false, "food", reason)
			FishingSession.eat(player, item_name, world.combat)
			dirty[character_id] = true
		"set_quick_food":
			var name := String(command.get("item_name", ""))
			if int(player.backpack.get(name, 0)) <= 0 or int(GameData.get_item_by_name(name).get("food_healing", 0)) <= 0:
				return _result(false, "food", "Choose owned food.")
			player.quick_food_name = name
			dirty[character_id] = true
		"craft":
			if activities.active(character_id) or world.combat.active_spell_casts.has(character_id):
				return _result(false, "busy", "Finish your activity first.")
			var station := station_for(player, String(command.get("station_id", "")), "craft")
			if station.is_empty():
				return _result(false, "station", "Move close to an approved crafting station.")
			var crafted := CraftingService.craft(player, String(command.get("recipe_id", "")), String(station.station), int(command.get("quantity", 1)))
			if not crafted.ok:
				return _result(false, "craft", String(crafted.get("message", "Cannot craft.")))
			dirty[character_id] = true
			return _result(true, "ok", String(crafted.get("message", "Crafted.")))
		"purchase":
			if activities.active(character_id) or world.combat.active_spell_casts.has(character_id):
				return _result(false, "busy", "Finish your activity first.")
			var station := station_for(player, String(command.get("station_id", "")), "craft")
			if station.is_empty() or String(station.station) != "bait_store":
				return _result(false, "station", "Move close to the approved bait store.")
			var bought := ShopService.purchase(player, String(command.get("item_name", "")), int(command.get("quantity", 1)))
			if not bought.ok:
				return _result(false, "purchase", String(bought.get("message", "Cannot purchase.")))
			dirty[character_id] = true
			return _result(true, "ok", String(bought.get("message", "Purchased.")))
		"drop":
			var name := GameData.canonical_item_name(String(command.get("item_name", "")))
			var quantity := int(command.get("quantity", 1))
			if quantity < 1 or GameData.get_item_by_name(name).is_empty() or not InventorySystem.remove_from_backpack(player, name, quantity):
				return _result(false, "inventory", "That item quantity is unavailable.")
			_stage_drop(character_id, name, quantity, player.get_position())
			dirty[character_id] = true
		"pale_drop":
			var slot := int(command.get("slot", -1))
			if slot < 0 or slot >= player.fishing_pale.size() or player.fishing_pale[slot].is_empty():
				return _result(false, "inventory", "Choose an owned fish in your pale.")
			var name: String = player.fishing_pale[slot]
			if GameData.get_item_by_name(name).is_empty() or not player.remove_fishing_catch(slot, name):
				return _result(false, "inventory", "That fish is unavailable.")
			_stage_drop(character_id, name, 1, player.get_position())
			dirty[character_id] = true
		"pickup":
			var drop_id := String(command.get("drop_id", ""))
			if not drops.has(drop_id):
				return _result(false, "drop", "That drop was already collected.")
			var drop: Dictionary = drops[drop_id]
			if not String(drop.owner_id).is_empty() and String(drop.owner_id) != character_id:
				return _result(false, "owner", "That loot belongs to another character.")
			if player.get_position().distance_to(Vector2(drop.x, drop.y)) > 2.0:
				return _result(false, "range", "Move closer to the drop.")
			drops.erase(drop_id) # Reserve before credit: other claimants never see this item again.
			_record_ground_mutation(character_id, "pickup", drop)
			InventorySystem.add_to_backpack(player, String(drop.item_name), int(drop.quantity))
			dirty[character_id] = true
		"select_spell":
			if not player.select_spell(String(command.get("spell_id", ""))):
				return _result(false, "spell", "Spell is not unlocked.")
			dirty[character_id] = true
		"attack_style":
			if not player.set_attack_style(String(command.get("style", ""))):
				return _result(false, "style", "Weapon does not support that attack style.")
			_refresh_actor(character_id)
			dirty[character_id] = true
		_:
			var outcome: Dictionary = activities.submit(character_id, command)
			if outcome.ok:
				dirty[character_id] = true
			return outcome
	return _result(true)

func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	# Clamp catch-up after stalls; no client can supply delta.
	var remaining := minf(delta, 1.0)
	var suspended: Dictionary = {}
	for id: String in frozen:
		if world.combat.actors.has(id):
			suspended[id] = world.combat.actors[id]
			world.combat.actors.erase(id)
			world.players.erase(id)
	while remaining > 0.000001:
		var step := minf(STEP, remaining)
		for id: String in players:
			if frozen.has(id):
				continue
			_advance_movement(id, step)
		_clock += step
		# Missing actors normally cancel casts. Persistence pauses instead retain
		# their paid casts, incoming/outgoing shots and source-owned effect timers.
		_handle_events(world.combat.process_realtime(world, step, frozen))
		_tick_elapsed += step
		if _tick_elapsed >= GameTickConfig.TICK_DURATION_SECONDS:
			_tick_elapsed -= GameTickConfig.TICK_DURATION_SECONDS
			_handle_events(world.tick())
		for id: String in players:
			if frozen.has(id):
				continue
			var actor: CombatActor = world.combat.actors.get(id)
			var player: PlayerState = players[id]
			if actor != null:
				if player.current_hp != actor.hp:
					dirty[id] = true
				player.current_hp = actor.hp
				player.x = actor.x
				player.y = actor.y
				player.in_combat = _in_combat(id)
			activities.advance(id, step)
		mining.advance(step)
		for id: String in _pending_refresh:
			if players.has(id) and not frozen.has(id):
				_refresh_actor(id)
		_pending_refresh.clear()
		remaining -= step
	for id: String in suspended:
		world.combat.actors[id] = suspended[id]
		world.players[id] = players[id]

func snapshot(character_id: String) -> Dictionary:
	_adopt_grid()
	var actors: Array[Dictionary] = []
	for actor: CombatActor in world.combat.actors.values():
		if frozen.has(actor.entity_id):
			continue
		var entry := {"entity_id": actor.entity_id, "name": actor.name, "x": actor.x, "y": actor.y,
			"hp": actor.hp, "max_hp": actor.max_hp, "is_alive": actor.is_alive,
			"is_monster": actor.is_monster, "attack_style": actor.attack_style,
			"target_id": actor.current_target_id, "gathering": mining.actor_activity(actor.entity_id),
			"equipment": players[actor.entity_id].get_equipped_names() if players.has(actor.entity_id) else {}}
		if world.grid != null:
			entry["grid_travel"] = world.grid_traveller(actor.entity_id).snapshot()
		actors.append(entry)
	var public_drops: Array[Dictionary] = []
	for drop: Dictionary in drops.values():
		public_drops.append(drop.duplicate())
	var public_stations: Array[Dictionary] = []
	for station: Dictionary in stations.values():
		var entry := station.duplicate()
		entry.erase("node")
		public_stations.append(entry)
	var result := {"region_id": region_id, "actors": actors, "drops": public_drops,
		"activity": activities.snapshot(character_id), "stations": public_stations, "deposits": mining.deposit_snapshots()}
	if world.grid != null:
		result["grid"] = {"origin": [world.grid.origin.x, world.grid.origin.y], "cell_pixels": 32}
	return result

func _adopt_grid() -> void:
	if world.grid == null and geometry_game != null:
		var source: WorldState = geometry_game.get("world")
		if source != null and source.grid != null:
			world.set_grid(source.grid)

func station_for(player: PlayerState, id: String, kind: String) -> Dictionary:
	var station: Dictionary = stations.get(id, {})
	if station.is_empty() or String(station.kind) != kind:
		return {}
	var node: Node = station.get("node")
	if not is_instance_valid(node) or not node.is_inside_tree():
		return {}
	if kind == "cook" and not bool(node.get("enabled")):
		return {}
	if player.get_position().distance_to(Vector2(station.x, station.y)) > float(station.range):
		return {}
	return station

func _advance_movement(id: String, delta: float) -> void:
	_adopt_grid()
	var actor: CombatActor = world.combat.actors.get(id)
	if actor == null or not actor.is_alive:
		return
	if world.grid != null:
		_advance_grid_movement(id, actor, delta)
		return
	var direction := Vector2.ZERO
	var distance := SPEED * delta
	if _inputs.has(id):
		var input: Dictionary = _inputs[id]
		var time_left := maxf(0.0, float(input.until) - _clock)
		if time_left <= 0.000001:
			_inputs.erase(id)
		else:
			direction = input.direction
			distance = SPEED * minf(delta, time_left)
	elif _walks.has(id):
		var offset: Vector2 = _walks[id] - Vector2(actor.x, actor.y)
		distance = minf(distance, offset.length())
		direction = offset.normalized()
		if offset.length() <= 0.02:
			_walks.erase(id)
	elif _attacking.has(id):
		var target: CombatActor = world.combat.actors.get(String(_attacking[id]))
		if target == null or not target.is_alive:
			_attacking.erase(id)
			players[id].current_target = ""
			actor.current_target_id = ""
		else:
			var offset := Vector2(target.x - actor.x, target.y - actor.y)
			distance = minf(distance, maxf(0.0, offset.length() - actor.attack_range * 0.9))
			direction = offset.normalized()
	if not direction.is_zero_approx() and distance > 0.0:
		var before := Vector2(actor.x, actor.y)
		world.move_actor_continuous(id, direction * distance)
		if not Vector2(actor.x, actor.y).is_equal_approx(before):
			dirty[id] = true
	_sync_body(id)

func _advance_grid_movement(id: String, actor: CombatActor, delta: float) -> void:
	if activities.active(id):
		world.cancel_grid_route(id)
		return
	var before := Vector2(actor.x, actor.y)
	if _inputs.has(id):
		var input: Dictionary = _inputs[id]
		var direction: Vector2 = input.direction if float(input.until) > _clock + 0.000001 else Vector2.ZERO
		world.move_grid_direction(id, direction, delta, SPEED)
		if float(input.until) <= _clock:
			_inputs.erase(id)
	elif _walks.has(id):
		world.move_grid_toward(id, _walks[id], delta, SPEED)
		var traveller := world.grid_traveller(id)
		if not traveller.active and traveller.route.is_empty():
			_walks.erase(id)
	elif _attacking.has(id):
		var target: CombatActor = world.combat.actors.get(String(_attacking[id]))
		if target != null and target.is_alive:
			world.move_grid_toward(id, Vector2(target.x, target.y), delta, SPEED, actor.attack_range * 0.9, Callable(),
				func(point: Vector2) -> bool: return world.has_line_of_sight(point, Vector2(target.x, target.y)))
		else:
			_attacking.erase(id)
			world.cancel_grid_route(id)
			world.move_grid_direction(id, Vector2.ZERO, delta, SPEED)
	else:
		world.move_grid_direction(id, Vector2.ZERO, delta, SPEED)
	if not Vector2(actor.x, actor.y).is_equal_approx(before):
		dirty[id] = true
	_sync_body(id)

func _refresh_actor(id: String) -> void:
	var player: PlayerState = players[id]
	var stats := player.get_combat_stats()
	var data := stats.duplicate(true)
	data.merge({"entity_id": id, "name": player.name, "x": player.x, "y": player.y,
		"hp": player.current_hp, "max_hp": player.get_max_hp(), "attack_style": stats.style}, true)
	var previous: CombatActor = world.combat.actors.get(id)
	if previous != null:
		for key: String in ["attack_cooldown_seconds", "active_orb_effects", "current_target_id", "death_reported"]:
			data[key] = previous.get(key)
	world.combat.add_actor(CombatActor.new().configure(data))
	if not world.combat.player_attack_enabled.has(id):
		world.combat.player_attack_enabled[id] = false

func _handle_events(events: Array) -> void:
	for event: Dictionary in events:
		if int(event.get("damage", 0)) > 0:
			mining.stop(String(event.get("target_id", "")), "damage")
		if event.get("type", "") == "entity_died":
			mining.stop(String(event.get("entity_id", "")), "death")
		if event.get("type", "") == "skill_experience_gained":
			_pending_refresh[String(event.get("entity_id", ""))] = true
		for key: String in ["entity_id", "attacker_id", "target_id", "caster_id"]:
			var id := String(event.get(key, ""))
			if players.has(id) and not frozen.has(id):
				dirty[id] = true
		if String(event.get("type", "")) != "entity_died":
			continue
		var entity_id := String(event.get("entity_id", ""))
		var owner_id := String(event.get("attacker_id", ""))
		for monster: MonsterState in world.monsters:
			if monster.entity_id != entity_id or not monster.is_alive:
				continue
			monster.is_alive = false
			monster.current_hp = 0
			var loot := _loot.roll_monster_loot(monster)
			if players.has(owner_id) and not frozen.has(owner_id):
				players[owner_id].gold += int(loot.get("gold", 0))
				dirty[owner_id] = true
			var items: Array = loot.get("items", [])
			if items.is_empty() and loot.get("item") is Dictionary:
				items.append({"item": loot.item, "quantity": loot.get("quantity", 1)})
			for item: Dictionary in items:
				var value: Variant = item.get("item")
				if value is Dictionary:
					_add_drop(String(value.get("name", "")), int(item.get("quantity", 1)), monster.get_position(), owner_id)
			break

func _add_drop(item_name: String, quantity: int, point: Vector2, owner_id: String = "") -> void:
	var drop := _ground_drop(item_name, quantity, point, owner_id)
	if not drop.is_empty():
		drops[String(drop.drop_id)] = drop

func _stage_drop(character_id: String, item_name: String, quantity: int, point: Vector2) -> void:
	var drop := _ground_drop(item_name, quantity, point)
	if not drop.is_empty():
		_record_ground_mutation(character_id, "outgoing", drop)

func _ground_drop(item_name: String, quantity: int, point: Vector2, owner_id: String = "") -> Dictionary:
	if quantity < 1 or GameData.get_item_by_name(item_name).is_empty():
		return {}
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	return {"drop_id": id, "item_name": item_name, "quantity": quantity,
		"x": point.x, "y": point.y, "owner_id": owner_id}

func _record_ground_mutation(character_id: String, kind: String, drop: Dictionary) -> void:
	var serial := mutation_checkpoint(character_id) + 1
	_mutation_serials[character_id] = serial
	if not _ground_mutations.has(character_id):
		_ground_mutations[character_id] = []
	_ground_mutations[character_id].append({"checkpoint": serial, "kind": kind, "drop": drop.duplicate(true)})

func mutation_checkpoint(character_id: String) -> int:
	## Capture alongside the exact PlayerState snapshot submitted for durable save.
	return int(_mutation_serials.get(character_id, 0))

func commit_mutations(character_id: String, through_checkpoint: int = -1) -> void:
	## Call only after the save containing this checkpoint is durably acknowledged.
	var checkpoint := mutation_checkpoint(character_id) if through_checkpoint < 0 else through_checkpoint
	var retained: Array[Dictionary] = []
	for mutation: Dictionary in _ground_mutations.get(character_id, []):
		if int(mutation.checkpoint) > checkpoint:
			retained.append(mutation)
			continue
		if String(mutation.kind) == "outgoing":
			var drop: Dictionary = mutation.drop
			drops[String(drop.drop_id)] = drop
		# A pickup was removed from public ground items when reserved. A durable
		# acknowledgement finalizes that removal; it must never publish the item.
	if retained.is_empty():
		_ground_mutations.erase(character_id)
	else:
		_ground_mutations[character_id] = retained

func discard_mutations(character_id: String) -> void:
	## Terminal ownership loss only: discard the actor and reload its durable save.
	## Never restore inventory or a reserved pickup after an ambiguous save result;
	## it may already have committed. Retried saves keep mutations until their ack.
	_ground_mutations.erase(character_id)
	# Keep the serial so a late acknowledgement cannot commit a new session's drops.

func _in_combat(id: String) -> bool:
	for actor: CombatActor in world.combat.actors.values():
		if actor.is_monster and actor.is_alive and actor.current_target_id == id:
			return true
	return false

func _inside(point: Vector2) -> bool:
	return point.is_finite() and point.x >= world.movement_min.x and point.y >= world.movement_min.y and point.x <= world.movement_max.x and point.y <= world.movement_max.y

func _safe_position(wanted: Vector2) -> Vector2:
	var point := wanted.clamp(world.movement_min + Vector2.ONE, world.movement_max - Vector2.ONE)
	if point.is_finite() and _passable(point):
		return point
	# A saved/new default coordinate can predate the map's north/west expansion.
	# Prefer its authored startup spawn instead of searching inside unbuilt land.
	var authored: Variant = geometry_game.get("player") if geometry_game != null else null
	if authored is PlayerState:
		var spawn: Vector2 = authored.get_position()
		if _inside(spawn):
			point = spawn
			if _passable(point):
				return point
	for radius in range(1, 33):
		for offset in [Vector2(radius, 0), Vector2(-radius, 0), Vector2(0, radius), Vector2(0, -radius),
			Vector2(radius,radius),Vector2(radius,-radius),Vector2(-radius,radius),Vector2(-radius,-radius)]:
			var candidate: Vector2 = point + offset
			if _inside(candidate) and _passable(candidate):
				return candidate
	return Vector2(INF,INF)

func _passable(point: Vector2) -> bool:
	if geometry_game == null or not geometry_game.has_method("_screen_position") or not geometry_game.is_inside_tree():
		return true
	# A point can be clear while the actor's 24px collision body overlaps a wall.
	var shape := RectangleShape2D.new()
	shape.size = Vector2(24,24)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0,geometry_game.to_global(geometry_game._screen_position(point.x, point.y)))
	query.collision_mask = 1
	query.collide_with_areas = false
	return geometry_game.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()

func _add_body(id: String) -> void:
	if geometry_game == null or not geometry_game.get("actor_sprites") is Dictionary or not geometry_game.has_method("_screen_position"):
		return
	var body := ActorSprite.new().configure(Vector2(32,32), Color.TRANSPARENT, id)
	body.visible = false
	body.set_process(false)
	geometry_game.add_child(body)
	geometry_game.get("actor_sprites")[id] = body
	_bodies[id] = body
	_sync_body(id)

func _sync_body(id: String) -> void:
	if not _bodies.has(id) or not world.combat.actors.has(id):
		return
	var actor: CombatActor = world.combat.actors[id]
	var body: Node2D = _bodies[id]
	body.position = geometry_game._screen_position(actor.x, actor.y)

func _move_collision(id: String, displacement: Vector2) -> Vector2:
	_sync_body(id)
	var actual: Vector2 = geometry_game._move_actor_with_map_collision(id, displacement)
	# CharacterBody recovery can eject a pre-existing overlap by many tiles.
	# Recovery is never allowed to become extra authoritative movement.
	if not actual.is_finite() or actual.length() > displacement.length() + 0.001:
		_sync_body(id)
		return Vector2.ZERO
	actual = actual.limit_length(displacement.length())
	if _bodies.has(id):
		var actor: CombatActor = world.combat.actors[id]
		_bodies[id].position = geometry_game._screen_position(actor.x + actual.x, actor.y + actual.y)
	return actual

func _discover_stations() -> void:
	if geometry_game == null or not geometry_game.is_inside_tree():
		return
	var root: Node = geometry_game.get_parent() if geometry_game.get_parent() != null else geometry_game
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child: Node in node.get_children():
			pending.append(child)
		var entry := {}
		if node is CraftingStation:
			entry = {"kind":"craft", "station":node.station_id, "name":node.station_name,
				"x":node.simulation_position.x, "y":node.simulation_position.y,"range":2.5}
		elif node is FishingSpot and node.name != "FishingPracticeSpot":
			var point := _simulation_point(node.shore_position())
			entry = {"kind":"fish","station":"fishing","name":node.spot_name,"x":point.x,"y":point.y,"range":node.interact_radius / 32.0}
		elif node is CookingStation:
			var point := _simulation_point(node.approach_position())
			entry = {"kind":"cook","station":"cooking","name":node.station_name,"x":point.x,"y":point.y,"range":node.interaction_radius / 32.0}
		if not entry.is_empty():
			var id := String(root.get_path_to(node))
			entry["station_id"] = id
			entry["node"] = node
			stations[id] = entry

func _simulation_point(global_point: Vector2) -> Vector2:
	var local: Vector2 = geometry_game.to_local(global_point)
	var origin: Vector2 = geometry_game.get("map_origin")
	return Vector2((local.x - origin.x) / 32.0, (origin.y + float(geometry_game.get("map_height")) - local.y) / 32.0)

func _discover_mining() -> void:
	if geometry_game == null or not geometry_game.is_inside_tree():
		return
	var root: Node = geometry_game.get_parent() if geometry_game.get_parent() != null else geometry_game
	var pending: Array[Node] = [root]
	var candidates := {}
	var duplicates := {}
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if not node is MiningDeposit:
			continue
		if candidates.has(node.deposit_id):
			duplicates[node.deposit_id] = true
		candidates[node.deposit_id] = node
	for id: String in candidates:
		var node: MiningDeposit = candidates[id]
		if duplicates.has(id) or not node.enabled or not is_finite(node.interaction_radius) or node.interaction_radius <= 0.0 or not node.approach_position().is_finite():
			continue
		if mining.register_deposit(id, node.ore_item_id).ok:
			_mining_nodes[id] = node

func _mining_context(id: String, deposit_id: String) -> Dictionary:
	if frozen.has(id):
		return {"paused": true}
	var player: PlayerState = players.get(id)
	var actor: CombatActor = world.combat.actors.get(id)
	# Keep the lookup Variant until validity is checked: a removed scene node
	# cannot be assigned to a typed Object reference in GDScript.
	var node: Variant = _mining_nodes.get(deposit_id)
	if player == null or actor == null or not is_instance_valid(node) or not node.is_inside_tree() or not node.enabled:
		return {}
	var point := _simulation_point(node.approach_position())
	return {"player": player, "paused": false,
		"eligible": actor.is_alive and actor.hp > 0 and not _in_combat(id) and
			not world.combat.active_spell_casts.has(id) and not activities.fishing.has(id) and
			not (activities.cooking.has(id) and activities.cooking[id].is_active()),
		"in_range": player.get_position().distance_to(point) <= node.interaction_radius / 32.0 and world.has_line_of_sight(player.get_position(), point)}

func _validate(command: Dictionary) -> Dictionary:
	var kind: Variant = command.get("type")
	if not kind is String or not SCHEMA.has(kind):
		return _result(false, "unsupported", "Unsupported gameplay command.")
	for key: Variant in command:
		if not key is String or (key != "type" and key not in SCHEMA[kind]):
			return _result(false, "invalid", "Unexpected command field.")
		var value: Variant = command[key]
		if key in ["x", "y", "steering", "phase_elapsed"]:
			if not (value is int or value is float) or not is_finite(float(value)):
				return _result(false, "invalid", "Expected a finite number.")
		elif key in ["slot", "quantity", "encounter_id", "input_id", "action_id", "expected_state", "plan_ack", "prompt_id", "deposit_generation"] and not (kind == "unequip" and key == "slot"):
			if not (value is int or value is float) or not is_finite(float(value)) or floor(float(value)) != float(value) or float(value) < 0.0 or float(value) > 2147483647.0:
				return _result(false, "invalid", "Expected a supported integer.")
		elif key != "direction":
			if not value is String or value.length() > 200:
				return _result(false, "invalid", "Expected a short text field.")
	return _result(true)

func _vector(value: Variant) -> Vector2:
	if value is Array and value.size() == 2:
		if (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float):
			return Vector2(float(value[0]), float(value[1]))
	return Vector2(INF, INF)

func _result(ok: bool, code: String = "ok", message: String = "") -> Dictionary:
	return {"ok": ok, "code": code, "message": message}
