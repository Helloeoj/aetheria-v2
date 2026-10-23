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

func reset(origin: Vector2) -> void:
	position = origin
	_clock = 0.0
	_since_snapshot = 0.0
	_commands.clear()
	_frames.clear()
	_visual_error = Vector2.ZERO
	enabled = true

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
		position = _move(position, normalized * SPEED * duration)
	_clock += delta
	_since_snapshot += delta
	_visual_error *= exp(-20.0 * delta)
	while not _frames.is_empty() and float(_frames[0].end) < _clock - 1.0:
		_frames.pop_front()

func reconcile(authority: Vector2, sequence: int, age: float, can_move: bool = true) -> void:
	var old_visual := render_position()
	var hard_reset := not can_move or position.distance_to(authority) > TELEPORT_DISTANCE
	if hard_reset:
		reset(authority)
		enabled = can_move
		return
	enabled = can_move
	_since_snapshot = 0.0
	position = authority
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
			position = _move(position, frame.direction * SPEED * duration)
	_visual_error = old_visual - position
	while _commands.size() > 1 and int(_commands[1].sequence) <= sequence:
		_commands.pop_front()

func render_position() -> Vector2:
	return position + _visual_error

func _move(start: Vector2, motion: Vector2) -> Vector2:
	return move_resolver.call(start, motion) if move_resolver.is_valid() else start + motion
