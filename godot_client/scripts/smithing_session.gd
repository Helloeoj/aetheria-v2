class_name SmithingSession
extends RefCounted
## Owns one reserved batch/workpiece. UI never submits recipes or grants rewards.
enum State { READY, SMELTING, FORGING, QUENCHING, FINISHED, FAILED, CANCELLED, CLAIM_PENDING }
const Rules = preload("res://scripts/smithing_rules.gd")
const Crafting = preload("res://scripts/crafting_service.gd")

var _player_ref: WeakRef
var player: PlayerState:
	get:
		return _player_ref.get_ref() as PlayerState if _player_ref != null else null
var station: Node2D
var engine: CombatEngine
var config: Dictionary
var state := State.READY
var recipe_id := ""
var output_name := ""
var batch := 1
var tier := 1
var temperature := 0.0
var progress := 0.0
var duration := 0.0
var overheated_seconds := 0.0
var hits := 0
var target_elapsed := 0.0
var target_index := 0
var quench_elapsed := 0.0
var reward_xp := 0
var message := "Choose a Smithing recipe."
var _inputs: Dictionary = {}
var _outputs: Dictionary = {}
var _pattern: Array = []
var _settled := false
var _start_hp := 0
var _station_id := ""
var _cancel_requested := false

func _init(owner_player: PlayerState, work_station: Node2D, combat: CombatEngine = null, options: Dictionary = {}) -> void:
	# PlayerState may own a pending settlement; a weak reverse reference avoids
	# a RefCounted cycle while keeping it alive independently of the old scene.
	_player_ref = weakref(owner_player) if owner_player != null else null
	station = work_station
	engine = combat
	config = Rules.settings()
	config.merge(options, true)

func start(id: String, quantity: int = 1) -> String:
	if state != State.READY:
		return "This Smithing session has already started."
	var error := _conditions_error()
	if not error.is_empty():
		return error
	_station_id = String(station.station_id)
	if _station_id not in ["furnace", "anvil"]:
		return "Use a furnace or anvil."
	if quantity < 1 or quantity > (10 if _station_id == "furnace" else 1):
		return "Choose 1–10 bars, or forge one workpiece at a time."
	var exchange: Dictionary = Crafting.prepare_exchange(player, id, _station_id, quantity)
	if not bool(exchange.ok):
		return String(exchange.message)
	if exchange.outputs.size() != 1:
		return "Smithing needs one output type."
	var name_key := String(exchange.outputs.keys()[0])
	var item := GameData.get_item_by_name(name_key)
	var item_tier := int(item.get("tier", 0))
	var required := Rules.required_level(item_tier)
	if player.get_skill_level("smithing") < required:
		return "You need Smithing %d to make %s." % [required, name_key]
	if Rules.heat_profile(item_tier, player.get_skill_level("smithing"), config).is_empty():
		return "This tier's Smithing rules are not configured."
	if _station_id == "furnace" and (int(exchange.outputs[name_key]) != quantity or not name_key.ends_with(" Ingot")):
		return "A smelting batch must produce one ingot per bar selected."
	# Validate completely, then reserve only the inputs. Reserved ore/bars cannot
	# be dropped, equipped, sold or spent by a second recipe during the minigame.
	var reserved := player.backpack.duplicate(true)
	for input_name: String in exchange.inputs:
		Crafting._consume(reserved, input_name, int(exchange.inputs[input_name]))
	_inputs = exchange.inputs.duplicate(true)
	_outputs = exchange.outputs.duplicate(true)
	player.backpack = reserved
	player.active_smithing_session = weakref(self)
	recipe_id = id
	output_name = name_key
	tier = item_tier
	batch = quantity
	_start_hp = player.current_hp
	duration = Rules.smelt_seconds(batch, config)
	_pattern = Rules.pattern_for(output_name, config)
	state = State.SMELTING if _station_id == "furnace" else State.FORGING
	message = "Hold the bellows to raise heat. Keep the gold temperature range." if state == State.SMELTING else "Hammer the glowing targets. Misses never damage your workpiece."
	return ""

func heat_profile() -> Dictionary:
	return Rules.heat_profile(tier, player.get_skill_level("smithing"), config)

func is_active() -> bool:
	return state in [State.SMELTING, State.FORGING, State.QUENCHING, State.CLAIM_PENDING]

func is_furnace_work() -> bool:
	return _station_id == "furnace"

func advance(delta: float, bellows: bool = false) -> void:
	if not is_finite(delta) or delta <= 0.0 or not is_active():
		return
	if state == State.CLAIM_PENDING:
		_complete()
		return
	if state == State.QUENCHING:
		quench_elapsed = minf(quench_duration(), quench_elapsed + delta)
		if quench_elapsed >= quench_duration():
			_complete()
		return
	if _cancel_requested:
		if cancel():
			return
		bellows = false
	var error := _conditions_error()
	if not error.is_empty() or player.current_hp < _start_hp:
		if cancel():
			message = error if not error.is_empty() else "Smithing interrupted by damage; materials returned."
			return
		bellows = false
	if state == State.FORGING:
		target_elapsed += delta
		var window := float(config.target_seconds)
		if target_elapsed >= window:
			target_index = (target_index + int(target_elapsed / window)) % _pattern.size()
			target_elapsed = fmod(target_elapsed, window)
		return
	# Small deterministic steps give correct heat-boundary and grace behavior
	# under long frames, and never credit a whole frame spent crossing the band.
	var remaining := delta
	while remaining > 0.000001 and state == State.SMELTING:
		var step := minf(remaining, 1.0 / 60.0)
		remaining -= step
		temperature = clampf(temperature + (float(config.bellows_per_second) * float(bellows) - float(config.cooling_per_second)) * step, 0.0, 1.0)
		var heat := heat_profile()
		if _cancel_requested and temperature <= float(heat.high):
			cancel()
			continue
		if temperature > float(heat.high):
			if not bool(heat.immune):
				overheated_seconds += step
				if overheated_seconds + 0.000001 >= float(heat.grace):
					state = State.FAILED
					_settled = true
					_inputs.clear()
					_release()
					message = "Overheated! The entire batch's ore was destroyed."
			else:
				overheated_seconds = 0.0
		else:
			overheated_seconds = 0.0
			if temperature >= float(heat.low) and error.is_empty():
				progress = minf(duration, progress + step)
				if progress + 0.000001 >= duration:
					_complete()

func target_position() -> Vector2:
	if _pattern.is_empty():
		return Vector2.ZERO
	var point: Array = _pattern[target_index % _pattern.size()]
	return Vector2(float(point[0]), float(point[1]))

func total_hits() -> int:
	return _pattern.size() * maxi(1, int(config.pattern_repetitions))

func shape_stage() -> int:
	return mini(int(config.shaping_stages) - 1, floori(float(hits) / float(maxi(1, total_hits())) * float(config.shaping_stages)))

func strike(point: Vector2, aspect_ratio: float = 1.0) -> bool:
	if state != State.FORGING or not point.is_finite() or not _conditions_error().is_empty():
		return false
	if not is_finite(aspect_ratio) or aspect_ratio <= 0.0 or ((point - target_position()) * Vector2(aspect_ratio, 1)).length() > float(config.target_radius):
		return false
	hits += 1
	target_index = (target_index + 1) % _pattern.size()
	target_elapsed = 0.0
	if hits >= total_hits():
		state = State.QUENCHING
		message = "Shaping complete. Quenching your %s..." % output_name
	return true

func quench_duration() -> float:
	return float(config.quench_lower_seconds) + float(config.quench_immerse_seconds) + float(config.quench_raise_seconds)

func cancel() -> bool:
	if state not in [State.SMELTING, State.FORGING]:
		return false
	_cancel_requested = true
	if state == State.SMELTING:
		var heat := heat_profile()
		if temperature > float(heat.high) and not bool(heat.immune):
			message = "Cool the furnace before cancelling; the overheat timer is still running."
			return false
	if not _merge_items(_inputs):
		message = "Make room in the material stack before cancelling."
		return false
	_settled = true
	_inputs.clear()
	state = State.CANCELLED
	message = "Smithing cancelled. Unfinished materials returned."
	_release()
	return true

func retain_for_later() -> void:
	if is_active() and player != null:
		player.pending_smithing_session = self

func _complete() -> void:
	if _settled:
		return
	if not _merge_items(_outputs):
		state = State.CLAIM_PENDING
		message = "Make room in the output stack to receive your finished work."
		return
	_settled = true
	var bars := batch
	if _station_id == "anvil":
		bars = 0
		for input_name: String in _inputs:
			if input_name.ends_with(" Ingot"):
				bars += int(_inputs[input_name])
	var before := player.get_skill_experience("smithing")
	player.add_skill_experience("smithing", bars * Rules.xp_per_bar(tier))
	reward_xp = player.get_skill_experience("smithing") - before
	_inputs.clear()
	state = State.FINISHED
	message = "Created %d %s. +%d Smithing XP" % [int(_outputs[output_name]), output_name, reward_xp]
	_release()

func _merge_items(items: Dictionary) -> bool:
	var next := player.backpack.duplicate(true)
	for item_name: String in items:
		if GameData.get_item_by_name(item_name).is_empty():
			return false
		var current := Crafting._available(next, item_name)
		var count := int(items[item_name])
		if current < 0 or current > Crafting.MAX_COUNT - count:
			return false
		next[item_name] = int(next.get(item_name, 0)) + count
	player.backpack = next
	return true

func _release() -> void:
	if player.pending_smithing_session == self:
		player.pending_smithing_session = null
	if player.active_smithing_session != null and player.active_smithing_session.get_ref() == self:
		player.active_smithing_session = null

func _conditions_error() -> String:
	if player == null or player.current_hp <= 0:
		return "You must be alive to smith."
	if player.in_combat or not player.current_target.is_empty():
		return "Finish combat before Smithing."
	if engine != null and engine.active_spell_casts.has(player.entity_id):
		return "Finish casting before Smithing."
	if not is_instance_valid(station) or not station.is_available(player):
		return "Move within reach of the Smithing station."
	if player.active_cooking_session != null and player.active_cooking_session.get_ref() != null:
		return "Finish cooking before Smithing."
	return ""
