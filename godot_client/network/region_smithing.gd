extends RefCounted
## Authoritative Smithing sessions using the original gameplay rules and clock.
var owner: WeakRef
var sessions := {}
var metadata := {}
var tokens := {}
var serial := 0
var sample := 0
var region: RefCounted:
	get: return owner.get_ref()

func configure(value: RefCounted) -> void:
	owner = weakref(value)

func active(id: String) -> bool:
	if sessions.has(id) and sessions[id].is_active(): return true
	if not region.players.has(id): return false
	var player: PlayerState = region.players[id]
	return not player.pending_smithing_record.is_empty() or (player.pending_smithing_session != null and player.pending_smithing_session.is_active())

func submit(id: String, command: Dictionary) -> Dictionary:
	var player: PlayerState = region.players[id]
	if command.type == "smith_start":
		var token := str(command.get("start_token", ""))
		if token.is_empty(): return result(false, "A Smithing start identity is required.")
		if metadata.has(id) and metadata[id].token == token: return result(true)
		if token in tokens.get(id, []): return result(false, "That Smithing request has ended.")
		if region.activities.active(id): return result(false, "Finish your current activity first.")
		var station: Dictionary = region.station_for(player, str(command.get("station_id", "")), "craft")
		if station.is_empty() or station.station not in ["anvil", "furnace"]: return result(false, "Move close to a furnace or anvil.")
		var session := SmithingSession.new(player, station.node, region.world.combat)
		var error := session.start(str(command.get("recipe_id", "")), int(command.get("quantity", 1)))
		if not error.is_empty(): return result(false, error)
		serial += 1
		sessions[id] = session
		metadata[id] = {"token":token, "encounter":serial, "station_id":station.station_id, "input":0, "action":0, "bellows":false, "remaining":0.0, "order_recorded":false}
		var history: Array = tokens.get(id, [])
		history.append(token)
		if history.size() > 64: history.pop_front()
		tokens[id] = history
		region.activities._stop_movement(id)
		region.dirty[id] = true
		return result(true)
	if not sessions.has(id): return result(false, "Start Smithing first.")
	var session: SmithingSession = sessions[id]
	var meta: Dictionary = metadata[id]
	var encounter := int(command.get("encounter_id", -1))
	if encounter != int(meta.encounter):
		if command.type != "smith_cancel" or command.get("start_token", "") != meta.token: return result(false, "That Smithing encounter has ended.")
	match str(command.type):
		"smith_bellows":
			var input := int(command.get("input_id", 0))
			if input <= int(meta.input): return result(true)
			meta.input = input
			meta.bellows = int(command.get("bellows", 0)) == 1
			meta.remaining = 0.25
			meta.expires = region._clock + 0.25
		"smith_strike":
			var action := int(command.get("action_id", 0))
			if action <= int(meta.action): return result(true)
			meta.action = action
			if int(command.get("target_index", -1)) != session.target_serial: return result(false, "That hammer target has moved.")
			var aspect := float(command.get("aspect", 0.0))
			if aspect < 1.0 or aspect > 4.0: return result(false, "Invalid workpiece coordinates.")
			session.strike(Vector2(float(command.get("x", -10.0)), float(command.get("y", -10.0))), aspect)
			region.dirty[id] = true
			return {"ok":true, "message":session.message, "transient":session.state == SmithingSession.State.FORGING}
		"smith_cancel":
			meta.bellows = false
			meta.remaining = 0.0
			session.cancel()
			region.dirty[id] = true
	return result(true)

func advance(id: String, delta: float) -> void:
	var player: PlayerState = region.players[id]
	if player.pending_smithing_session != null:
		# A blocked refund/output belongs to the character after area travel.
		# Retry it here even though the source region no longer owns its session.
		var pending: RefCounted = player.pending_smithing_session
		pending.advance(delta, false)
		if not pending.is_active(): region.dirty[id] = true
	if not player.pending_smithing_record.is_empty():
		if preload("res://scripts/smithing_settlement.gd").retry(player): region.dirty[id] = true
	if not sessions.has(id): return
	var session: SmithingSession = sessions[id]
	var meta: Dictionary = metadata[id]
	var before := session.state
	var held: bool = bool(meta.bellows) and region._clock <= float(meta.get("expires", -1.0))
	meta.remaining = maxf(0, float(meta.remaining) - delta)
	meta.bellows = held
	session.advance(delta, held)
	if session.state != before: region.dirty[id] = true
	if session.state == SmithingSession.State.FINISHED and not meta.order_recorded:
		meta.order_recorded = true
		region.record_order_action(id, "crafting", session.recipe_id, str(meta.station_id))

func close(id: String, departing: bool = false) -> void:
	if not sessions.has(id): return
	var session: SmithingSession = sessions[id]
	metadata[id].bellows = false
	metadata[id].remaining = 0.0
	session.cancel()
	if departing:
		if session.state == SmithingSession.State.QUENCHING: session.advance(session.quench_duration())
		elif session.state == SmithingSession.State.SMELTING: session.advance(30.0, false)
		session.retain_for_later()
		sessions.erase(id)
		metadata.erase(id)
	region.dirty[id] = true

func snapshot(id: String) -> Dictionary:
	if not sessions.has(id): return {}
	var session: SmithingSession = sessions[id]
	var meta: Dictionary = metadata[id]
	sample += 1
	var data := {"kind":"smith", "station_id":meta.station_id, "start_token":meta.token,
		"encounter_id":meta.encounter, "sample_id":sample, "sample_time":region._clock, "heat":session.heat_profile()}
	for field: String in ["state", "recipe_id", "output_name", "batch", "tier", "temperature", "progress", "duration", "overheated_seconds", "hits", "target_elapsed", "target_index", "target_serial", "quench_elapsed", "reward_xp", "message", "_station_id"]:
		data[field] = session.get(field)
	return data

func result(ok: bool, message: String = "") -> Dictionary:
	return {"ok":ok, "code":"ok" if ok else "smithing", "message":message}
