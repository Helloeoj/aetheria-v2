class_name MiningService
extends RefCounted
## Single-threaded region authority. No await, RPC, animation or client clock
## may enter the claim -> inventory -> XP transaction.
var _defs: MiningDefinitions
var _context: Callable
var _reward: Callable
var _rng: RandomNumberGenerator
var _clock := 0.0
var _deposits: Dictionary = {}
var _depleted: Dictionary = {}
var _sessions: Dictionary = {}
var _stopped: Dictionary = {}
var _advancing := false

func configure(definitions: MiningDefinitions, context: Callable, reward: Callable, rng: RandomNumberGenerator) -> void:
	_defs = definitions
	_context = context
	_reward = reward
	_rng = rng

func register_deposit(id: String, ore_id: int) -> Dictionary:
	if id.is_empty() or id.length() > 200 or _deposits.has(id) or _defs == null or _defs.ore(ore_id).is_empty():
		return _result(false, "deposit")
	_deposits[id] = {"deposit_id": id, "ore_item_id": ore_id, "state": "available", "generation": 0, "respawn_at": 0.0}
	return _result(true)

func start(id: String, deposit_id: String, generation: int) -> Dictionary:
	if id.is_empty() or generation < 0 or not _context.is_valid() or _rng == null:
		return _result(false, "unavailable")
	var deposit: Dictionary = _deposits.get(deposit_id, {})
	if deposit.is_empty() or deposit.state != "available" or int(deposit.generation) != generation:
		return _result(false, "deposit")
	var context: Dictionary = _context.call(id, deposit_id)
	if bool(context.get("paused", false)):
		return _result(false, "paused")
	var player: PlayerState = context.get("player")
	if player == null:
		return _result(false, "unavailable")
	if _sessions.has(id) and _sessions[id].deposit_id == deposit_id:
		var reason := _invalid(context, _sessions[id], deposit)
		if reason.is_empty():
			return _result(true) # Retransmission never resets a deadline.
		stop(id, reason)
		return _result(false, reason)
	var tool := _defs.best_pickaxe(player)
	if tool.is_empty():
		return _result(false, "pickaxe")
	var session := {
		"kind": "mine", "deposit_id": deposit_id, "generation": generation,
		"tool_item_id": int(tool.item_id), "attempt_interval_seconds": float(tool.attempt_interval_seconds),
		"attempt_started_at": _clock, "next_attempt_at": _clock + float(tool.attempt_interval_seconds),
		"attempt_sequence": 0, "position": player.get_position(), "hp": player.current_hp,
		"hands": _hands(player), "paused": false
	}
	var reason := _invalid(context, session, deposit)
	if not reason.is_empty():
		return _result(false, reason)
	_sessions[id] = session
	_stopped.erase(id)
	return _result(true)

func stop(id: String, reason: String = "cancelled") -> void:
	if _sessions.erase(id):
		_stopped[id] = {"kind": "mine", "active": false, "stop_reason": reason}

func forget_player(id: String) -> void:
	_sessions.erase(id)
	_stopped.erase(id)

func active(id: String) -> bool:
	return _sessions.has(id)

func advance(delta: float) -> void:
	if _advancing or not is_finite(delta) or delta <= 0.0:
		return
	_advancing = true
	_clock += minf(delta, 0.25)
	for deposit_id: String in _depleted.keys():
		var deposit: Dictionary = _deposits[deposit_id]
		if _clock + 0.000000001 >= float(deposit.respawn_at):
			deposit.state = "available"
			deposit.generation += 1
			deposit.respawn_at = 0.0
			_depleted.erase(deposit_id)
	var due: Array[Dictionary] = []
	for id: String in _sessions.keys():
		var session: Dictionary = _sessions[id]
		var context: Dictionary = _context.call(id, String(session.deposit_id)) if _context.is_valid() else {}
		# Frozen actors can be temporarily absent from combat. Resume from a fresh
		# interval, never spend time accumulated while persistence was uncertain.
		if bool(context.get("paused", false)):
			session.paused = true
			continue
		var reason := _invalid(context, session, _deposits.get(String(session.deposit_id), {}))
		if not reason.is_empty():
			stop(id, reason)
			continue
		if session.paused:
			session.paused = false
			_schedule(session)
		if _clock + 0.000000001 >= float(session.next_attempt_at):
			due.append({"id": id, "deadline": session.next_attempt_at, "tie": _rng.randi()})
	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.tie) < int(b.tie) if a.deadline == b.deadline else float(a.deadline) < float(b.deadline))
	for entry: Dictionary in due:
		_attempt(String(entry.id))
	_advancing = false

func _attempt(id: String) -> void:
	if not _sessions.has(id):
		return # Another due attempt may already have claimed this generation.
	var session: Dictionary = _sessions[id]
	var deposit: Dictionary = _deposits[String(session.deposit_id)]
	var context: Dictionary = _context.call(id, String(session.deposit_id))
	if bool(context.get("paused", false)):
		session.paused = true
		return
	var reason := _invalid(context, session, deposit)
	if not reason.is_empty():
		stop(id, reason)
		return
	var player: PlayerState = context.player
	var ore := _defs.ore(int(deposit.ore_item_id))
	session.attempt_sequence += 1
	_schedule(session)
	if _rng.randf() >= _defs.success_probability(player.get_skill_level("mining"), ore):
		return
	# Claim first, with no yields/callbacks between claim and both grants.
	deposit.state = "depleted"
	deposit.generation += 1
	deposit.respawn_at = _clock + float(ore.respawn_seconds)
	_depleted[String(deposit.deposit_id)] = true
	for other: String in _sessions.keys():
		if _sessions[other].deposit_id == session.deposit_id:
			stop(other, "depleted")
	var before := player.get_skill_experience("mining")
	player.add_item(String(GameData.get_item(int(ore.item_id)).name), 1)
	player.add_skill_experience("mining", int(ore.xp_reward))
	if _reward.is_valid():
		_reward.call(id, {"type": "skill_experience_gained", "entity_id": id, "skill": "mining",
			"experience_gained": player.get_skill_experience("mining") - before,
			"ore_item_id":int(ore.item_id),"deposit_id":String(deposit.deposit_id),
			"deposit_generation":int(deposit.generation)})

func _invalid(context: Dictionary, session: Dictionary, deposit: Dictionary) -> String:
	var player: PlayerState = context.get("player")
	if player == null or not bool(context.get("eligible", false)):
		return "unavailable"
	if player.current_hp <= 0:
		return "dead"
	if not bool(context.get("in_range", false)):
		return "range"
	if player.in_combat or not player.current_target.is_empty() or player.current_hp < int(session.hp):
		return "interrupted"
	if player.get_position().distance_to(session.position) > 0.1:
		return "movement"
	if _hands(player) != session.hands:
		return "equipment"
	if deposit.is_empty() or deposit.state != "available" or deposit.generation != session.generation:
		return "depleted"
	var ore := _defs.ore(int(deposit.ore_item_id))
	var tool := _defs.pickaxe(int(session.tool_item_id))
	if ore.is_empty() or tool.is_empty() or not _defs.owns_pickaxe(player, tool):
		return "pickaxe"
	if player.get_skill_level("mining") < int(ore.required_level) or player.get_skill_level("mining") < int(tool.required_level):
		return "level"
	if not InventorySystem.can_add_to_backpack(player, String(GameData.get_item(int(ore.item_id)).get("name", "")), 1):
		return "inventory_full"
	return ""

func _schedule(session: Dictionary) -> void:
	session.attempt_started_at = _clock
	session.next_attempt_at = _clock + float(session.attempt_interval_seconds)

func _hands(player: PlayerState) -> Array:
	return [int(player.equipment.get("weapon", {}).get("id", 0)), int(player.equipment.get("shield", {}).get("id", 0))]

func snapshot(id: String) -> Dictionary:
	if not active(id):
		return _stopped.get(id, {}).duplicate(true)
	var value: Dictionary = _sessions[id].duplicate(true)
	for key: String in ["position", "hp", "hands"]:
		value.erase(key)
	value.active = true
	value.sample_time = _clock
	return value

func deposit_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for deposit: Dictionary in _deposits.values():
		result.append(deposit.duplicate(true))
	return result

func actor_activity(id: String) -> Dictionary:
	if not active(id):
		return {}
	var session: Dictionary = _sessions[id]
	return {"kind": "mine", "deposit_id": session.deposit_id, "tool_item_id": session.tool_item_id,
		"attempt_sequence": session.attempt_sequence, "attempt_started_at": session.attempt_started_at,
		"attempt_interval_seconds": session.attempt_interval_seconds}

func _result(ok: bool, code: String = "ok") -> Dictionary:
	var messages := {
		"deposit": "That deposit is unavailable. Select its current state.",
		"pickaxe": "An owned, Mining-eligible pickaxe is required.",
		"level": "Your Mining level is too low.", "range": "Move close to the deposit with a clear path.",
		"inventory_full": "There is no capacity for another ore.", "paused": "Character saving is paused."
	}
	return {"ok": ok, "code": code, "message": "" if ok else messages.get(code, "Mining was interrupted.")}
