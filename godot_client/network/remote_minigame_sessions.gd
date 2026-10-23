extends RefCounted
## Read-only session views for the ORIGINAL minigame interfaces. No client rewards.

class Fish extends FishingSession:
	const STALE_SECONDS := 0.25
	const ACTION_TIMEOUT := 1.0
	var transport: Node
	var station_id := ""
	var _last_status := ""
	var _encounter := 0
	var _sample := -1
	var _clock := 0.0
	var _sample_age := 0.0
	var _input_id := 0
	var _action_id := 0
	var _start_token := ""
	var _start_unconfirmed := false
	var _steering_elapsed := 0.0
	var _last_input := INF
	var _rules: Dictionary = {}
	var _history: Array[Dictionary] = []
	var _pending: Array[Dictionary] = []
	var _confirmed := State.READY
	var _simulation_time := 0.0
	var _sample_time := -INF
	var _offsets: Dictionary = {}
	const DISPLAY_FIELDS := ["lateral","velocity","strain","remaining","fight_time"]
	var _last: Dictionary = {}
	func _init(owner: PlayerState, network: Node, station: String) -> void:
		super(owner)
		transport = network
		station_id = station
		_last_status = String(network.get("status")) if network.get("status") is String else ""
	func act() -> void:
		if state == State.CLOSED or _pending.size() >= 2:
			return
		var from := state
		var command: Dictionary
		_action_id += 1
		if state in [State.READY, State.CAUGHT, State.LOST]:
			reward_xp = 0
			# Timeout is ambiguous: retry the same start identity until discovered.
			if not _start_unconfirmed:
				_start_token = Crypto.new().generate_random_bytes(8).hex_encode()
			_start_unconfirmed = true
			command = {"start_token":_start_token,"type":"fish_start","station_id":station_id,"rod":rod,"bait":bait,"action_id":_action_id}
			state = State.POWER
			elapsed = 0.0
			power = 0.0
			message = "Click or Space again to set cast power."
		elif state == State.POWER:
			command = {"type":"fish_input","action":"act","expected_state":from,"phase_elapsed":elapsed,"action_id":_action_id}
			cast_power = power
			distance = projected_cast_distance()
			remaining = distance
			state = State.CASTING
			elapsed = 0.0
			message = "Casting..."
		elif state == State.BITE:
			command = {"type":"fish_input","action":"act","expected_state":from,"action_id":_action_id}
			state = State.FIGHT
			elapsed = 0.0
			message = "Pull against the fish. Keep the bobber between the red lines!"
		else:
			return
		_pending.append({"command":command,"at":_clock,"sent":false})
		_flush_actions()
	func _flush_actions() -> void:
		for pending: Dictionary in _pending:
			if pending.sent:
				continue
			var command: Dictionary = pending.command
			if command.type != "fish_start":
				if _encounter == 0 or (_pending[0].command.type == "fish_start"):
					return
				command.encounter_id = _encounter
			pending.sent = transport.send_action(command)
	func sync_remote() -> void:
		if state == State.CLOSED:
			return
		var status: Variant = transport.get("status")
		if status is String and status != _last_status:
			_last_status = status
			message = status
		var data: Dictionary = transport.latest_snapshot.get("activity", {})
		if data.get("kind") != "fish" or data.get("station_id") != station_id:
			if not _last.is_empty():
				state = State.CLOSED
				_history.clear()
				_pending.clear()
			return
		if not _start_token.is_empty() and String(data.get("start_token", "")) != _start_token:
			return
		var encounter := int(data.get("encounter_id", 0))
		var sample := int(data.get("sample_id", 0))
		if encounter < _encounter or (encounter == _encounter and sample <= _sample) or data == _last:
			return
		var sample_time := float(data.get("sample_time", data.get("fight_time", 0.0)))
		if encounter == _encounter and sample_time < _sample_time - 0.000001:
			return
		var old_display: Dictionary = {}
		for field: String in DISPLAY_FIELDS:
			old_display[field] = float(get(field))
		var present_time := _simulation_time
		var continuing_fight := state == State.FIGHT and int(data.state) == State.FIGHT and encounter == _encounter
		if encounter != _encounter:
			_encounter = encounter
			_history.clear()
			fight_plan = []
			plan_index = 0
			_offsets.clear()
			_simulation_time = sample_time
		_sample_time = sample_time
		_sample = sample
		_sample_age = 0.0
		_last = data.duplicate(true)
		_confirmed = int(data.state)
		var ack := int(data.get("action_ack", 0))
		var start_confirmed := not _start_token.is_empty() and String(data.get("start_token", "")) == _start_token
		if start_confirmed: _start_unconfirmed = false
		while not _pending.is_empty() and (int(_pending[0].command.action_id) <= ack or (start_confirmed and _pending[0].command.type == "fish_start")):
			_pending.pop_front()
		var pending_state := state
		var pending_elapsed := elapsed
		var pending_power := power
		state = _confirmed
		message = String(data.get("message", ""))
		rod = String(data.get("rod", rod))
		bait = String(data.get("bait", bait))
		for field: String in ["elapsed","power","cast_power","distance","remaining","lateral","velocity","strain","fight_time","fish_pull"]:
			set(field, float(data.get(field, get(field))))
		if state == State.POWER and pending_state == State.POWER and absf(pending_elapsed - elapsed) <= 0.25:
			elapsed = pending_elapsed
			power = pending_power
		reward_xp = int(data.get("reward_xp", 0))
		fish = GameData.get_item(int(data.get("fish_id", 0)))
		_rules = data.get("motion", _rules)
		if data.has("fight_plan") and not data.fight_plan.is_empty():
			fight_plan = data.fight_plan.duplicate(true)
			transport.send_action({"type":"fish_input","encounter_id":_encounter,"plan_ack":_encounter})
		_offsets.clear()
		_simulation_time = sample_time
		if state == State.FIGHT:
			plan_index = 0
			# Steering ACK covers received intent, never all frames carrying its ID.
			# Replay precisely the timeline after the authoritative sample clock.
			var target_time := clampf(present_time, sample_time, sample_time + STALE_SECONDS) if continuing_fight else sample_time
			var cursor := sample_time
			var held := float(data.get("steering", 0.0))
			for entry: Dictionary in _history:
				if float(entry.until) <= cursor + 0.000001 or float(entry.since) >= target_time:
					continue
				var since := maxf(cursor, float(entry.since))
				if since > cursor:
					_predict(since - cursor, held)
				var until := minf(target_time, float(entry.until))
				_predict(until - since, float(entry.input))
				cursor = until
				held = float(entry.input)
			if cursor < target_time:
				_predict(target_time - cursor, held)
			_simulation_time = target_time
			if continuing_fight:
				for field: String in DISPLAY_FIELDS:
					var bound := _correction_bound(field)
					_offsets[field] = clampf(float(old_display[field]) - float(get(field)), -bound, bound)
					set(field, float(get(field)) + float(_offsets[field]))
		else:
			_history.clear()

		if not _pending.is_empty() and state not in [State.CAUGHT, State.LOST, State.CLOSED]:
			state = pending_state
			elapsed = pending_elapsed
			power = pending_power
		_flush_actions()
	func _correction_bound(field: String) -> float:
		match field:
			"lateral": return 0.12
			"velocity": return 0.7
			"strain": return 0.2
			"remaining": return float(_rules.get("reel", 9.0)) * STALE_SECONDS
		return STALE_SECONDS
	func _correction_rate(field: String) -> float:
		match field:
			"lateral": return 1.2
			"velocity": return 2.8
			"strain": return 0.8
			"remaining": return float(_rules.get("reel", 9.0))
		return 0.5
	func _remove_display_offsets() -> void:
		for field: String in _offsets:
			set(field, float(get(field)) - float(_offsets[field]))
	func _apply_display_offsets(delta: float) -> void:
		for field: String in _offsets:
			var raw := float(get(field))
			_offsets[field] = move_toward(float(_offsets[field]), 0.0, delta * _correction_rate(field))
			var shown := raw + float(_offsets[field])
			if field == "strain": shown = clampf(shown, 0.0, 1.0)
			elif field == "remaining" or field == "fight_time": shown = maxf(0.0, shown)
			elif field == "lateral": shown = clampf(shown, -float(_rules.limit), float(_rules.limit))
			set(field, shown)
			_offsets[field] = shown - raw

	func _predict(delta: float, input: float) -> void:
		if _rules.is_empty() or fight_plan.is_empty():
			return
		var left := minf(maxf(delta, 0.0), STALE_SECONDS)
		while left > 0.00001:
			var step := minf(left, 1.0 / 60.0)
			Motion.step(self, step, input, _rules)
			left -= step
	func advance(delta: float, input: float = 0.0) -> void:
		if state == State.CLOSED:
			return
		var dt := maxf(delta, 0.0)
		_clock += dt
		sync_remote()
		if player.current_hp <= 0 or transport.get("authenticated") == false:
			state = State.CLOSED
			_history.clear()
			_pending.clear()
			return
		if not _pending.is_empty() and _clock - float(_pending[0].at) > ACTION_TIMEOUT:
			_pending.clear()
			state = _confirmed
			message = "Waiting for fishing confirmation."
		if state == State.POWER:
			elapsed += minf(dt, 0.1)
			power = power_at_time(elapsed)
		elif state == State.CASTING:
			elapsed = minf(0.65, elapsed + minf(dt, 0.1))
		_steering_elapsed += dt
		if state == State.FIGHT:
			input = clampf(input, -1.0, 1.0)
			if (input != _last_input and (_steering_elapsed >= 0.05 or is_inf(_last_input) or (input in [-1.0, 0.0, 1.0] and _last_input in [-1.0, 0.0, 1.0]))) or _steering_elapsed >= 0.1:
				_input_id += 1
				_steering_elapsed = 0.0
				_last_input = input
				transport.send_action({"type":"fish_input","encounter_id":_encounter,"input_id":_input_id,"steering":input})
			var predicted := minf(minf(minf(dt, 0.1), maxf(0.0, STALE_SECONDS - _sample_age)), maxf(0.0, _sample_time + STALE_SECONDS - _simulation_time))
			if predicted > 0.0:
				_remove_display_offsets()
				_predict(predicted, input)
				_apply_display_offsets(predicted)
				_history.append({"since":_simulation_time,"until":_simulation_time + predicted,"input":input,"at":_clock})
				_simulation_time += predicted
			while not _history.is_empty() and (_clock - float(_history[0].at) > STALE_SECONDS or _history.size() > 64):
				_history.pop_front()
		_sample_age += dt
	func close() -> void:
		transport.send_action({"type":"fish_stop"})
		state = State.CLOSED
		_history.clear()
		_pending.clear()

class Cook extends CookingSession:
	const STALE_SECONDS := 0.25
	const ACTION_TIMEOUT := 1.0
	var transport: Node
	var station_id := ""
	var _last_status := ""
	var _last: Dictionary = {}
	var _encounter := 0
	var _phase := 0
	var _prompt := 0
	var _sample := -1
	var _sample_time := 0.0
	var _simulation_time := 0.0
	var _sample_age := 0.0
	var _clock := 0.0
	var _request := 0
	var _start_token := ""
	var _start_unconfirmed := false
	var _pending_kind := ""
	var _pending_since := 0.0
	var _pending_phase := 0
	var _confirmed := State.READY
	var _timer_correction := 0.0
	var _prediction_enabled := true
	var _closed := false
	func _init(owner: PlayerState, heat: CookingCampfire, combat: CombatEngine, network: Node, station: String) -> void:
		super(owner, heat, combat)
		transport = network
		station_id = station
		start_position = owner.get_position()
		start_hp = owner.current_hp
		_last_status = String(network.get("status")) if network.get("status") is String else ""
	func pending_action() -> String:
		return _pending_kind
	func start(item_name: String, quantity: int = 1) -> String:
		if _closed or is_active() or not _pending_kind.is_empty():
			return "You are already cooking."
		# A timed-out request may already own an active authoritative batch.
		if not _start_unconfirmed:
			_start_token = Crypto.new().generate_random_bytes(8).hex_encode()
		_request += 1
		if not transport.send_action({"type":"cook_start","station_id":station_id,"item_name":item_name,"quantity":quantity,"start_token":_start_token,"action_id":_request}):
			return "Cooking connection is unavailable."
		_start_unconfirmed = true
		_pending_kind = "start"
		_pending_since = _clock
		start_position = player.get_position()
		start_hp = player.current_hp
		state = State.COOKING
		raw_item = item_name
		remaining = quantity
		elapsed = 0.0
		flip_elapsed = 0.0
		feedback_elapsed = 0.0
		last_result = {}
		cooked_count = 0
		burnt_count = 0
		reward_xp = 0
		_sample_age = 0.0
		_timer_correction = 0.0
		message = "Starting cooking... waiting for the stove."
		return ""
	func _timer_field(phase_state: int) -> String:
		match phase_state:
			State.COOKING: return "elapsed"
			State.FLIP_PENDING: return "flip_elapsed"
			State.FEEDBACK: return "feedback_elapsed"
		return ""
	func _timer_limit() -> float:
		match state:
			State.COOKING: return float(recipe_for_item(raw_item).get("cooking_seconds", INF))
			State.FLIP_PENDING: return flip_window
			State.FEEDBACK: return FEEDBACK_SECONDS
		return INF
	func _clear_pending() -> void:
		_pending_kind = ""
	func sync_remote() -> void:
		if _closed:
			return
		var status: Variant = transport.get("status")
		if status is String and status != _last_status:
			_last_status = status
			if not status.is_empty():
				if _pending_kind == "start": state = _confirmed
				_clear_pending()
				_timer_correction = 0.0
				message = status
		var data: Dictionary = transport.latest_snapshot.get("activity", {})
		if data.get("kind") != "cook" or data.get("station_id") != station_id:
			if not _last.is_empty():
				_clear_pending()
				state = State.CANCELLED
				_closed = true
			return
		if not _start_token.is_empty() and String(data.get("start_token", "")) != _start_token:
			return
		var encounter := int(data.get("encounter_id", 0))
		var sample_id := int(data.get("sample_id", 0))
		var phase := int(data.get("phase_id", 0))
		var sample_time := float(data.get("sample_time", 0.0))
		if encounter < _encounter or (encounter == _encounter and (sample_id <= _sample or phase < _phase or sample_time < _sample_time - 0.000001)):
			return
		var next_state := int(data.state)
		var field := _timer_field(next_state)
		var old_timer := float(get(field)) if not field.is_empty() else 0.0
		var continuing := next_state == state and ((encounter == _encounter and phase == _phase) or _pending_kind == "start")
		var present_time := _simulation_time
		var same_encounter := encounter == _encounter
		_encounter = encounter
		_phase = phase
		_prompt = int(data.get("prompt_id", 0))
		_sample = sample_id
		_sample_time = sample_time
		_sample_age = 0.0
		_simulation_time = clampf(present_time, sample_time, sample_time + STALE_SECONDS) if same_encounter else sample_time
		_last = data.duplicate(true)
		_confirmed = next_state
		var start_confirmed := not _start_token.is_empty() and String(data.get("start_token", "")) == _start_token
		if start_confirmed: _start_unconfirmed = false
		if int(data.get("action_ack", 0)) >= _request or (_pending_kind == "start" and start_confirmed) or (_pending_kind == "flip" and phase > _pending_phase):
			_clear_pending()
		state = next_state
		message = String(data.get("message", ""))
		raw_item = String(data.get("raw_item", ""))
		remaining = int(data.get("remaining", 0))
		for timer: String in ["elapsed","flip_elapsed","feedback_elapsed"]:
			set(timer, float(data.get(timer, 0.0)))
		flip_window = INF if float(data.get("flip_window", 0.8)) < 0.0 else float(data.get("flip_window", 0.8))
		last_result = data.get("last_result", {}).duplicate(true)
		cooked_count = int(data.get("cooked_count", 0))
		burnt_count = int(data.get("burnt_count", 0))
		reward_xp = int(data.get("reward_xp", 0))
		_prediction_enabled = bool(data.get("prediction_enabled", true))
		_timer_correction = 0.0
		if not field.is_empty():
			var extra := _simulation_time - sample_time if _prediction_enabled else 0.0
			if state == State.FLIP_PENDING and is_inf(flip_window): extra = 0.0
			var projected := minf(_timer_limit(), float(get(field)) + extra)
			if continuing:
				_timer_correction = clampf(projected - old_timer, -STALE_SECONDS, STALE_SECONDS)
				set(field, clampf(projected - _timer_correction, 0.0, _timer_limit()))
			else:
				set(field, projected)
		if _pending_kind == "start": message = "Starting cooking... waiting for the stove."
		elif _pending_kind == "flip": message = "Flip sent... waiting for the stove."
	func advance(delta: float) -> Array[Dictionary]:
		if _closed:
			return []
		var dt := maxf(0.0, delta)
		_clock += dt
		sync_remote()
		if player.current_hp <= 0 or player.current_hp < start_hp or not player.get_position().is_equal_approx(start_position) or transport.get("authenticated") == false:
			_clear_pending()
			state = State.CANCELLED
			_closed = true
			return []
		if not _pending_kind.is_empty() and _clock - _pending_since >= ACTION_TIMEOUT:
			if _pending_kind == "start": state = _confirmed
			_clear_pending()
			_timer_correction = 0.0
			message = "Waiting for cooking confirmation."
		var step := minf(minf(dt, 0.1), maxf(0.0, STALE_SECONDS - _sample_age))
		step = minf(step, maxf(0.0, _sample_time + STALE_SECONDS - _simulation_time))
		var field := _timer_field(state)
		if _prediction_enabled and not field.is_empty() and not (state == State.FLIP_PENDING and is_inf(flip_window)):
			var correction := clampf(_timer_correction, -step * 0.5, step * 0.5)
			set(field, minf(_timer_limit(), float(get(field)) + step + correction))
			_timer_correction -= correction
			_simulation_time += step
		_sample_age += dt
		return []
	func flip() -> Array[Dictionary]:
		# Eligibility comes only from the latest server-confirmed prompt.
		if _closed or state != State.FLIP_PENDING or _confirmed != State.FLIP_PENDING or not _pending_kind.is_empty() or not _prediction_enabled:
			return []
		_request += 1
		if transport.send_action({"type":"cook_flip","encounter_id":_encounter,"prompt_id":_prompt,"action_id":_request}):
			_pending_kind = "flip"
			_pending_since = _clock
			_pending_phase = _phase
			message = "Flip sent... waiting for the stove."
		return []
	func close(_reason: String = "") -> void:
		if not _closed:
			transport.send_action({"type":"cook_cancel"})
		_clear_pending()
		_closed = true
		state = State.CANCELLED

static func raise_modal(panel: Control, game: Node) -> void:
	var canvas := game.get_node_or_null("UI") as CanvasLayer
	var social := game.get_node_or_null("/root/Social/SocialOverlay") as CanvasLayer
	if canvas != null and social != null and not panel.has_meta("original_ui_layer"):
		panel.set_meta("original_ui_layer", canvas.layer)
		canvas.layer = maxi(canvas.layer, social.layer + 1)
	for name: String in ["OnlineLogoutButton", "OnlineStatusLabel"]:
		var hud := game.ui_root.get_node_or_null(name) as Control
		if hud != null:
			hud.hide()

static func restore_modal(panel: Control, game: Node) -> void:
	var canvas := game.get_node_or_null("UI") as CanvasLayer
	if canvas != null and panel.has_meta("original_ui_layer"):
		canvas.layer = int(panel.get_meta("original_ui_layer"))
		panel.remove_meta("original_ui_layer")
	for name: String in ["OnlineLogoutButton", "OnlineStatusLabel"]:
		var hud := game.ui_root.get_node_or_null(name) as Control
		if hud != null:
			hud.show()
