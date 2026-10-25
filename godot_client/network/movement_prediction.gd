extends RefCounted
## Presentation only. The server's live actor always supplies the correction.
const SPEED := 4.0
const MAX_SPECULATION := 0.25
const TELEPORT_DISTANCE := 2.0
var position := Vector2.ZERO
var move_resolver: Callable
var enabled := true
var _clock := 0.0
var _since_snapshot := 0.0
var _commands: Array[Dictionary] = []
var _frames: Array[Dictionary] = []
var _visual_error := Vector2.ZERO
var grid: HiddenGrid
var _travel := GridTraveller.new()
var _authority_epoch := -1

func use_grid(value: HiddenGrid) -> void:
	if grid != value:
		_authority_epoch = -1
		grid = value
		if grid != null:
			_travel.reset(position, grid)

func cancel_inputs() -> void:
	_commands.clear()
	_frames.clear()

func reset(origin: Vector2) -> void:
	position = origin
	_clock = 0.0
	_since_snapshot = 0.0
	_commands.clear()
	_frames.clear()
	_visual_error = Vector2.ZERO
	enabled = true
	if grid != null:
		_travel.reset(origin, grid)

func record_input(sequence: int, direction: Vector2) -> void:
	_commands.append({"sequence": sequence, "at": _clock, "direction": direction.limit_length(1.0)})
	if _commands.size() > 128:
		_commands.pop_front()

func advance(delta: float, direction: Vector2) -> void:
	if delta <= 0.0 or not is_finite(delta):
		return
	var duration := minf(delta, maxf(0.0, MAX_SPECULATION - _since_snapshot)) if enabled else 0.0
	if duration > 0.0:
		var normalized := direction.limit_length(1.0)
		_frames.append({"start": _clock, "end": _clock + duration, "direction": normalized})
		_predict(duration, normalized)
	_clock += delta
	_since_snapshot += delta
	_visual_error *= exp(-20.0 * delta)
	while not _frames.is_empty() and float(_frames[0].end) < _clock - 1.0:
		_frames.pop_front()

func reconcile(authority: Vector2, sequence: int, age: float, can_move: bool = true, travel_state: Dictionary = {}) -> void:
	var old_visual := render_position()
	var epoch := int(travel_state.get("epoch", -1))
	var displaced := epoch >= 0 and _authority_epoch >= 0 and epoch != _authority_epoch
	_authority_epoch = epoch
	var hard_reset := displaced or not can_move or position.distance_to(authority) > TELEPORT_DISTANCE
	if hard_reset:
		reset(authority)
		_restore_travel(authority, travel_state)
		enabled = can_move
		return
	enabled = can_move
	_since_snapshot = 0.0
	position = authority
	_restore_travel(authority, travel_state)
	var replay_from := _clock
	# A packet can have been captured before our first input reached the host.
	# Those frames are all pending, rather than all already acknowledged.
	if not _commands.is_empty() and sequence < int(_commands[0].sequence):
		replay_from = maxf(float(_commands[0].at), _clock - MAX_SPECULATION)
	for command: Dictionary in _commands:
		if int(command.sequence) == sequence:
			replay_from = clampf(float(command.at) + maxf(0.0, age), _clock - MAX_SPECULATION, _clock)
			break
	for frame: Dictionary in _frames:
		var duration := maxf(0.0, float(frame.end) - maxf(replay_from, float(frame.start)))
		if duration > 0.0:
			_predict(duration, frame.direction)
	_visual_error = old_visual - position
	while _commands.size() > 1 and int(_commands[1].sequence) <= sequence:
		_commands.pop_front()

func render_position() -> Vector2:
	var rendered := position + _visual_error
	if grid != null and not grid.clear_segment(position, rendered):
		return position
	return rendered

func _move(start: Vector2, motion: Vector2) -> Vector2:
	return move_resolver.call(start, motion) if move_resolver.is_valid() else start + motion

func _predict(duration: float, direction: Vector2) -> void:
	if grid == null:
		position = _move(position, direction * SPEED * duration)
		return
	_travel.advance(duration, SPEED, direction, grid,
		func(motion: Vector2) -> Vector2: return _move(_travel.position, motion))
	position = _travel.position

func _restore_travel(point: Vector2, state: Dictionary) -> void:
	if grid == null:
		return
	_travel.reset(point, grid)
	var cell: Array = state.get("cell", [])
	var target: Array = state.get("target", [])
	if cell.size() == 2 and target.size() == 2:
		_travel.cell = Vector2i(int(cell[0]), int(cell[1]))
		_travel.target = Vector2(float(target[0]), float(target[1]))
		_travel.active = bool(state.get("active", false))
		_travel.epoch = int(state.get("epoch", _travel.epoch))
		_travel.arrival = int(state.get("arrival", 0))
