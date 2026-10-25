extends RefCounted
## Per-character activities call the same rule objects as offline play.
var _region: WeakRef
var region: RefCounted:
	get:
		return _region.get_ref()
var fishing: Dictionary = {}
var cooking: Dictionary = {}
var station_ids: Dictionary = {}
var steering: Dictionary = {}
var _fish_meta: Dictionary = {}
var _next_encounter := 0
var _sample_id := 0
var _cook_meta: Dictionary = {}
var _next_cook_encounter := 0
var _cook_sample_id := 0

func configure(owner_region: RefCounted) -> void:
	_region = weakref(owner_region)

func active(id: String) -> bool:
	return region.mining.active(id) or fishing.has(id) or (cooking.has(id) and cooking[id].is_active())

func close(id: String) -> void:
	if active(id):
		region.dirty[id] = true
	region.mining.stop(id, "cancelled")
	if fishing.has(id):
		fishing[id].close()
		fishing.erase(id)
	if cooking.has(id):
		cooking[id].close()
		cooking.erase(id)
		_cook_meta.erase(id)
	station_ids.erase(id)
	steering.erase(id)
	_fish_meta.erase(id)

func submit(id: String, command: Dictionary) -> Dictionary:
	var player: PlayerState = region.players[id]
	var kind := String(command.type)
	if kind in ["fish_start", "cook_start"]:
		region.mining.stop(id, "new_activity")
	match kind:
		"mine_start":
			if cooking.has(id) and not active(id):
				close(id) # Clear a finished batch's presentation, not an active action.
			var outcome: Dictionary = region.mining.start(id, String(command.get("deposit_id", "")), int(command.get("deposit_generation", -1)))
			if outcome.ok:
				_stop_movement(id)
			return outcome
		"mine_stop":
			region.mining.stop(id, "cancelled")
		"fish_start":
			if (active(id) and (not fishing.has(id) or fishing[id].active_cast())) or _busy(player):
				return _result(false, "Finish combat and other activities first.")
			var station: Dictionary = region.station_for(player, String(command.get("station_id", "")), "fish")
			if station.is_empty():
				return _result(false, "Move closer to an approved fishing spot.")
			var session := FishingSession.new(player)
			if command.has("rod"):
				session.rod = String(command.rod)
			if command.has("bait"):
				session.bait = String(command.bait)
			if session.rod not in FishingSession.RODS or session.bait not in FishingSession.BAITS or not session.available(session.rod) or not session.available(session.bait):
				return _result(false, "Choose an owned, unlocked rod and bait.")
			_next_encounter += 1
			_fish_meta[id] = {"start_token":String(command.get("start_token", "")),"encounter":_next_encounter,"input_ack":0,"action_ack":int(command.get("action_id", 0)),"plan_ack":0}
			steering.erase(id)
			fishing[id] = session
			station_ids[id] = String(station.station_id)
			session.act()
			_stop_movement(id)
		"fish_input":
			if not fishing.has(id):
				return _result(false, "Start fishing first.")
			if not command.get("action", "") in ["", "act"]:
				return _result(false, "Unsupported fishing input.")
			var session: FishingSession = fishing[id]
			var meta: Dictionary = _fish_meta[id]
			if int(command.get("encounter_id", -1)) != int(meta.encounter):
				return _result(false, "That fishing encounter has ended.")
			if command.has("plan_ack"):
				meta.plan_ack = int(command.plan_ack)
			if command.get("action", "") == "act":
				var action_id := int(command.get("action_id", 0))
				if action_id > 0 and action_id <= int(meta.action_ack):
					return _result(true)
				meta.action_ack = action_id
				if int(command.get("expected_state", -1)) != session.state or session.state not in [FishingSession.State.POWER, FishingSession.State.BITE]:
					return _result(false, "Fishing phase has changed.")
				if session.state == FishingSession.State.POWER:
					var phase := float(command.get("phase_elapsed", -1.0))
					# Clock intent is bounded to one input lifetime; outcome is derived here.
					if phase < 0.0 or absf(phase - session.elapsed) > 0.25:
						return _result(false, "Cast timing confirmation expired.")
					session.power = FishingSession.power_at_time(phase)
				session.act()
			if command.has("steering"):
				var input_id := int(command.get("input_id", int(meta.input_ack) + 1))
				if input_id <= int(meta.input_ack):
					return _result(true)
				meta.input_ack = input_id
				steering[id] = {"value": clampf(float(command.steering), -1.0, 1.0), "remaining": 0.25}

		"fish_stop", "cook_cancel":
			close(id)
		"pale_move":
			var slot := int(command.get("slot", -1))
			if slot < 0 or slot >= player.fishing_pale.size() or player.fishing_pale[slot].is_empty():
				return _result(false, "Choose a fish in your pale.")
			if not player.move_fishing_catch_to_inventory(slot):
				return _result(false, "Fish is unavailable.")
		"cook_start":
			# An accepted start stays the same batch even if its first sample was lost.
			var start_token := String(command.get("start_token", ""))
			if not start_token.is_empty() and _cook_meta.has(id) and String(_cook_meta[id].start_token) == start_token:
				_cook_meta[id].action_ack = maxi(int(_cook_meta[id].action_ack), int(command.get("action_id", 0)))
				return _result(true)
			if active(id) or _busy(player):
				return _result(false, "Finish combat and other activities first.")
			var station: Dictionary = region.station_for(player, String(command.get("station_id", "")), "cook")
			if station.is_empty():
				return _result(false, "Move closer to an approved stove.")
			var heat := CookingCampfire.new(Vector2(station.x, station.y))
			heat.active = true
			heat.cooking_reach = float(station.range)
			var session := CookingSession.new(player, heat, region.world.combat)
			var error := session.start(String(command.get("item_name", "")), int(command.get("quantity", 1)))
			if not error.is_empty():
				return _result(false, error)
			_next_cook_encounter += 1
			_cook_meta[id] = {"encounter":_next_cook_encounter,"start_token":String(command.get("start_token", "")),"phase":1,"prompt":0,"action_ack":int(command.get("action_id", 0))}
			cooking[id] = session
			station_ids[id] = String(station.station_id)
			_stop_movement(id)
		"cook_flip":
			if not cooking.has(id):
				return _result(false, "Wait for the server's flip prompt.")
			var meta: Dictionary = _cook_meta[id]
			if int(command.get("encounter_id", -1)) != int(meta.encounter) or int(command.get("prompt_id", -1)) != int(meta.prompt):
				return _result(false, "That cooking prompt has ended.")
			var action_id := int(command.get("action_id", 0))
			if action_id > 0 and action_id <= int(meta.action_ack):
				return _result(true)
			meta.action_ack = action_id
			if cooking[id].state != CookingSession.State.FLIP_PENDING:
				return _result(false, "Wait for the server's flip prompt.")
			cooking[id].flip()
			meta.phase += 1

		_:
			return _result(false, "Unsupported activity command.")
	return _result(true)

func advance(id: String, delta: float) -> void:
	var player: PlayerState = region.players[id]
	if fishing.has(id):
		var session: FishingSession = fishing[id]
		if _busy(player) or region.station_for(player, String(station_ids.get(id, "")), "fish").is_empty() or player.get_position().distance_to(session.start_position) > 0.1 or player.current_hp < session.start_hp:
			close(id)
			return
		var input := 0.0
		if steering.has(id):
			var data: Dictionary = steering[id]
			input = float(data.value) if float(data.remaining) > 0.0 else 0.0
			data.remaining = maxf(0.0, float(data.remaining) - delta)
		var before := [session.state, player.get_skill_experience("fishing"), player.fishing_pale.duplicate()]
		session.advance(delta, input)
		if before != [session.state, player.get_skill_experience("fishing"), player.fishing_pale]:
			region.dirty[id] = true
	if cooking.has(id):
		var session: CookingSession = cooking[id]
		if region.station_for(player, String(station_ids.get(id, "")), "cook").is_empty():
			session.close("Move close to the stove.")
			region.dirty[id] = true
			return
		var before := [session.state, session.remaining, session.reward_xp]
		session.advance(delta)
		if before[0] != session.state:
			_cook_meta[id].phase += 1
			if session.state == CookingSession.State.FLIP_PENDING:
				_cook_meta[id].prompt += 1
		if before != [session.state, session.remaining, session.reward_xp]:
			region.dirty[id] = true

func snapshot(id: String) -> Dictionary:
	if fishing.has(id):
		var session: FishingSession = fishing[id]
		_sample_id += 1
		var meta: Dictionary = _fish_meta[id]
		return {"sample_time":region._clock,"steering":float(steering[id].value) if steering.has(id) and float(steering[id].remaining) > 0.0 else 0.0,
			"start_token":meta.start_token,"encounter_id":meta.encounter,"sample_id":_sample_id,"input_ack":meta.input_ack,"action_ack":meta.action_ack,
			"fight_plan":session.fight_plan if int(meta.plan_ack) != int(meta.encounter) else [],"motion":session.motion_rules(),
			"kind":"fish", "state":session.state, "message":session.message, "station_id":station_ids.get(id,""),
			"rod":session.rod,"bait":session.bait,"power":session.power,"cast_power":session.cast_power,
			"distance":session.distance,"remaining":session.remaining,"lateral":session.lateral,
			"velocity":session.velocity,"strain":session.strain,"boundary":session.boundary(),
			"lateral_limit":session.lateral_limit(),"reward_xp":session.reward_xp,
			"elapsed":session.elapsed,"fight_time":session.fight_time,"fish_pull":session.fish_pull,
			"fish_id":int(session.fish.get("id",0)) if session.state in [FishingSession.State.FIGHT,FishingSession.State.CAUGHT,FishingSession.State.LOST] else 0}
	if cooking.has(id):
		var session: CookingSession = cooking[id]
		_cook_sample_id += 1
		var meta: Dictionary = _cook_meta[id]
		return {"encounter_id":meta.encounter,"phase_id":meta.phase,"prompt_id":meta.prompt,"sample_id":_cook_sample_id,"sample_time":region._clock,
			"start_token":meta.start_token,"action_ack":meta.action_ack,"prediction_enabled":not region.frozen.has(id),
			"kind":"cook", "state":session.state,"message":session.message,"station_id":station_ids.get(id,""),
			"raw_item":session.raw_item,"remaining":session.remaining,"elapsed":session.elapsed,
			"flip_elapsed":session.flip_elapsed,"flip_window":session.flip_window if is_finite(session.flip_window) else -1.0,
			"cooked_count":session.cooked_count,"burnt_count":session.burnt_count,"reward_xp":session.reward_xp,
			"feedback_elapsed":session.feedback_elapsed,"last_result":session.last_result.duplicate(true)}
	return region.mining.snapshot(id)

func _stop_movement(id: String) -> void:
	region._inputs.erase(id)
	region.cancel_walk(id)
	region.world.cancel_grid_route(id)
	region._attacking.erase(id)
	region.world.combat.player_attack_enabled[id] = false

func _busy(player: PlayerState) -> bool:
	return player.current_hp <= 0 or player.in_combat or not player.current_target.is_empty() or region.world.combat.active_spell_casts.has(player.entity_id)

func _result(ok: bool, message: String = "") -> Dictionary:
	return {"ok":ok,"code":"ok" if ok else "activity","message":message}
