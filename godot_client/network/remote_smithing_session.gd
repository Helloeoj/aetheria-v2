extends "res://scripts/smithing_session.gd"
## Presentation and input only. Inventory, XP and all outcomes stay on the server.
var transport: Node
var station_id := ""
var _token := ""
var _encounter := 0
var _sample := -1
var _input := 0
var _action := 0
var _heartbeat := 0.0
var _waiting := false
var _closing := false
var _heat := {}
var _start_sequences := {}
var _cancel_retry := 0.0
var _start_retry := 0.0
var _start_confirmed := false
var _start_command := {}

func _init(owner: PlayerState, target: Node2D, network: Node) -> void:
	super(owner, target)
	transport = network
	_station_id = str(target.station_id)
	# Stations are registered relative to their containing gameplay scene.
	var scene: Node = target.get_parent().get_parent()
	station_id = str(scene.get_path_to(target))

func start(id: String, quantity: int = 1) -> String:
	_token = Crypto.new().generate_random_bytes(12).hex_encode()
	_start_command = {"type":"smith_start", "station_id":station_id, "recipe_id":id, "quantity":quantity, "start_token":_token}
	if not _send_start():
		_stop_watching_start()
		return "The server is unavailable."
	_waiting = true
	recipe_id = id
	batch = quantity
	var recipe := Crafting._find_recipe(id)
	if not recipe.get("outputs", []).is_empty(): output_name = str(recipe.outputs[0].item)
	message = "Waiting for the furnace/anvil to confirm your materials..."
	return ""

func _send_start() -> bool:
	_start_sequences[int(transport.get("sequence")) + 1] = true
	if _start_sequences.size() > 128: _start_sequences.erase(_start_sequences.keys()[0])
	if transport.has_signal("action_result") and not transport.is_connected("action_result", _on_start_result):
		transport.connect("action_result", _on_start_result)
	return transport.send_action(_start_command)

func _stop_watching_start() -> void:
	if transport.has_signal("action_result") and transport.is_connected("action_result", _on_start_result):
		transport.disconnect("action_result", _on_start_result)
	_start_sequences.clear()

func _on_start_result(sequence: int, outcome: Dictionary) -> void:
	if not _start_sequences.has(sequence): return
	_start_sequences.erase(sequence)
	if not outcome.get("ok", false) and outcome.get("code") == "unavailable": return
	_stop_watching_start()
	_start_confirmed = bool(outcome.get("ok", false))
	if not outcome.get("ok", false):
		_waiting = false
		state = State.FAILED
		message = str(outcome.get("message", "Smithing could not start."))

func is_active() -> bool:
	return _waiting or super()

func heat_profile() -> Dictionary:
	return _heat if not _heat.is_empty() else super()

func advance(delta: float, bellows: bool = false) -> void:
	if transport.has_method("online") and (not transport.online() or not bool(transport.get("authenticated"))):
		_waiting = false
		state = State.CANCELLED
		message = "Disconnected. Your Smithing work is owned by the server."
		return
	var data: Dictionary = transport.latest_snapshot.get("activity", {})
	if data.get("kind") == "smith" and data.get("start_token") == _token:
		var sample := int(data.get("sample_id", -1))
		if sample > _sample:
			_sample = sample
			_encounter = int(data.encounter_id)
			_waiting = false
			_stop_watching_start()
			for field: String in ["state", "recipe_id", "output_name", "batch", "tier", "temperature", "progress", "duration", "overheated_seconds", "hits", "target_elapsed", "target_index", "target_serial", "quench_elapsed", "reward_xp", "message", "_station_id"]:
				if data.has(field): set(field, data[field])
			_pattern = Rules.pattern_for(output_name, config)
			_heat = data.get("heat", {}).duplicate(true)
	elif _waiting and str(transport.get("status")).begins_with("Cannot"):
		message = str(transport.get("status"))
	if _waiting and not _start_confirmed:
		_start_retry += maxf(0.0, delta)
		if _start_retry >= 0.5:
			_start_retry = 0.0
			_send_start() # Same identity: an accepted but unseen start cannot spend twice.
	if state == State.QUENCHING:
		# Interpolate the visual descent/rise, but never confirm a reward locally.
		quench_elapsed = minf(quench_duration(), quench_elapsed + maxf(0.0, delta))
	if _closing and is_active() and state not in [State.QUENCHING, State.CLAIM_PENDING]:
		_cancel_retry += maxf(0.0, delta)
		if _cancel_retry >= 0.35:
			_cancel_retry = 0.0
			_send_cancel()
	_heartbeat += maxf(0.0, delta)
	if state == State.SMELTING and _encounter > 0 and _heartbeat >= 0.08:
		_heartbeat = 0.0
		_input += 1
		transport.send_action({"type":"smith_bellows", "encounter_id":_encounter, "input_id":_input, "bellows":int(bellows and not _closing)})

func strike(point: Vector2, aspect_ratio: float = 1.0) -> bool:
	if state != State.FORGING or not point.is_finite(): return false
	_action += 1
	return transport.send_action({"type":"smith_strike", "encounter_id":_encounter, "action_id":_action, "target_index":target_serial, "x":point.x, "y":point.y, "aspect":aspect_ratio})

func cancel() -> bool:
	_closing = true
	_cancel_retry = 0.0
	_send_cancel()
	return not is_active()

func _send_cancel() -> void:
	transport.send_action({"type":"smith_cancel", "encounter_id":_encounter, "start_token":_token})

func retain_for_later() -> void:
	pass # Never attach authoritative reservations to a client PlayerState.
