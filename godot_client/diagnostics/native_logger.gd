extends Logger
## Callbacks may run on worker threads. No scene access, file I/O, prints or gameplay callbacks.
const Data = preload("res://diagnostics/diagnostic_data.gd")
var mutex := Mutex.new()
var events: Array[Dictionary] = []
var cursor := 0
var event_limit := 64
var pending_limit := 128
var context := {}
var pending := {}
var dropped := 0
var include_warnings := false
var accepting := true
var _inside := {}
var _revision := 0

func breadcrumb(system: String, action: String, data: Dictionary) -> void:
	mutex.lock()
	var event := {"time": Data.now(), "ticks_ms": Time.get_ticks_msec(), "system": Data.text(system, 80), "action": Data.text(action, 160), "data": Data.safe(data), "thread": OS.get_thread_caller_id()}
	if events.size() < event_limit:
		events.append(event)
	else:
		events[cursor] = event
	cursor = (cursor + 1) % event_limit
	_revision += 1
	mutex.unlock()

func set_context(values: Dictionary) -> void:
	mutex.lock()
	context = Data.safe(values)
	_revision += 1
	mutex.unlock()

func _recent() -> Array:
	if events.size() < event_limit or cursor == 0:
		return events.duplicate(true)
	return events.slice(cursor) + events.slice(0, cursor)

func capture(error: Dictionary) -> void:
	mutex.lock()
	var thread_id := OS.get_thread_caller_id()
	if not accepting or _inside.has(thread_id):
		mutex.unlock()
		return
	_inside[thread_id] = true
	error["time"] = Data.now()
	error["thread"] = thread_id
	var key := Data.fingerprint(error)
	if pending.has(key):
		pending[key].count += 1
		pending[key].last_seen = error.time
		if pending[key].context_revision != _revision:
			pending[key].latest_context = context.duplicate(true)
			pending[key].latest_events = _recent()
			pending[key].context_revision = _revision
	elif pending.size() < pending_limit:
		error["fingerprint"] = key
		error["count"] = 1
		error["first_seen"] = error.time
		error["last_seen"] = error.time
		error["context"] = context.duplicate(true)
		error["recent_events"] = _recent()
		error["latest_context"] = error.context
		error["latest_events"] = error.recent_events
		error["context_revision"] = _revision
		pending[key] = error
	else:
		dropped += 1
	_inside.erase(thread_id)
	mutex.unlock()

func drain() -> Dictionary:
	mutex.lock()
	var result := {"errors": pending, "dropped": dropped}
	pending = {}
	dropped = 0
	mutex.unlock()
	return result

func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING and not include_warnings:
		return
	var frames: Array[Dictionary] = []
	for trace: ScriptBacktrace in script_backtraces:
		for index in mini(trace.get_frame_count(), 64):
			if frames.size() >= 64:
				break
			frames.append({"file": trace.get_frame_file(index).replace("\\", "/"), "function": trace.get_frame_function(index), "line": trace.get_frame_line(index), "language": trace.get_language_name()})
	var engine_source := {"file": file.replace("\\", "/"), "line": line, "function": function}
	var source: Dictionary = frames[0] if not frames.is_empty() else engine_source
	capture({"kind": "native_%d" % error_type, "capture": "Godot Logger._log_error (observed)", "severity": "WARNING" if error_type == ERROR_TYPE_WARNING else "ERROR", "message": Data.text(rationale if not rationale.is_empty() else code), "code": Data.text(code), "source": source, "engine_source": engine_source, "backtrace": frames, "system": _system(String(source.get("file", "")))})

func _log_message(message: String, error: bool) -> void:
	if error:
		capture({"kind": "stderr", "capture": "Godot stderr message (no source supplied)", "severity": "ERROR", "message": Data.text(message), "source": {}, "backtrace": [], "system": "Engine"})

func _system(file: String) -> String:
	for key: String in ["inventory", "equipment", "character", "sprite", "animation", "shader", "physics", "collision", "world", "combat", "network", "game_data", "diagnostic"]:
		if key in file:
			return key.capitalize()
	return "Engine" if not file.begins_with("res://") else "Gameplay"
