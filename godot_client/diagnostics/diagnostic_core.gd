extends Node
## ADC: early native capture, timer-batched persistence, conservative restart recovery.
const Data = preload("res://diagnostics/diagnostic_data.gd")
const Bridge = preload("res://diagnostics/native_logger.gd")
const API = preload("res://diagnostics/diagnostics.gd")
var enabled := false
var bridge
var storage := ""
var session_id := ""
var session_path := ""
var native_log := ""
var incidents := {}
var metadata := {}
var io_failed := false
var dropped_occurrences := 0
var max_incidents := 128
var max_sessions := 16
var max_bytes := 67108864
var _dirty := {}
var _provider := Callable()
var _checkpoint_ticks := 0
var _prune_ticks := 0
var _closed := false
var _ending := false

func _init() -> void:
	enabled = bool(ProjectSettings.get_setting("aetheria/diagnostics/enabled", OS.is_debug_build()))
	var mode := OS.get_environment("AETHERIA_DIAGNOSTICS")
	if mode in ["0", "off"]:
		enabled = false
	elif mode in ["1", "on"]:
		enabled = true
	API._core = weakref(self)
	if not enabled:
		return
	bridge = Bridge.new()
	bridge.event_limit = clampi(int(ProjectSettings.get_setting("aetheria/diagnostics/event_history", 64)), 8, 256)
	bridge.pending_limit = clampi(int(ProjectSettings.get_setting("aetheria/diagnostics/max_incidents", 128)), 8, 256)
	bridge.include_warnings = bool(ProjectSettings.get_setting("aetheria/diagnostics/include_warnings", false))
	max_incidents = bridge.pending_limit
	max_sessions = clampi(int(ProjectSettings.get_setting("aetheria/diagnostics/retained_sessions", 16)), 2, 64)
	max_bytes = clampi(int(ProjectSettings.get_setting("aetheria/diagnostics/storage_limit_mb", 64)), 8, 512) * 1048576
	OS.add_logger(bridge)
	storage = OS.get_environment("AETHERIA_DIAGNOSTICS_DIR")
	if storage.is_empty():
		storage = "user://diagnostics"
	storage = ProjectSettings.globalize_path(storage).replace("\\", "/")
	session_id = "%s-%d-%s" % [Data.now().replace(":", "").replace("-", ""), OS.get_process_id(), str(Time.get_ticks_usec())]
	session_path = storage.path_join("sessions").path_join(session_id)
	if DirAccess.make_dir_recursive_absolute(session_path.path_join("incidents")) != OK:
		io_failed = true
	native_log = ProjectSettings.globalize_path(String(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log"))).replace("\\", "/")
	var arguments := OS.get_cmdline_args()
	var log_index := arguments.find("--log-file")
	if log_index >= 0 and log_index + 1 < arguments.size():
		native_log = arguments[log_index + 1].replace("\\", "/")
	if not OS.get_environment("AETHERIA_NATIVE_LOG").is_empty():
		native_log = OS.get_environment("AETHERIA_NATIVE_LOG").replace("\\", "/")
	metadata = {"schema_version": 1, "session_id": session_id, "pid": OS.get_process_id(), "started": Data.now(), "started_unix": Time.get_unix_time_from_system(), "clean_shutdown": false, "engine_version": Engine.get_version_info().string, "project_version": ProjectSettings.get_setting("application/config/version", "unversioned"), "native_log": native_log, "dropped_occurrences": 0, "context": {}}
	_write_json(session_path.path_join("session.json"), metadata)

func _ready() -> void:
	if not enabled:
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not io_failed:
		_recover()
	var timer := Timer.new()
	timer.wait_time = clampf(float(ProjectSettings.get_setting("aetheria/diagnostics/flush_seconds", 2.0)), 0.25, 30.0)
	timer.timeout.connect(flush)
	add_child(timer)
	timer.start()
	get_tree().scene_changed.connect(_scene_changed)
	API.event("Session", "started", {"engine": metadata.engine_version})
	_prune()
	flush()

func register_context_provider(provider: Callable) -> void:
	# Main-thread only. Weakly bound Godot Callable becomes invalid when the owner is freed.
	if not enabled:
		return
	_provider = provider
	_refresh_context()

func _refresh_context() -> void:
	if _ending:
		return
	if _provider.is_valid():
		var owner: Object = _provider.get_object()
		if owner is Node and not owner.is_inside_tree():
			return
		var result: Variant = _provider.call()
		if result is Dictionary:
			bridge.set_context(result)
	else:
		var scene := get_tree().current_scene
		bridge.set_context({"scene": scene.scene_file_path if scene != null else "initializing"})

func _scene_changed() -> void:
	_refresh_context()
	API.event("Scene", "scene loaded", {"scene": get_tree().current_scene.scene_file_path if get_tree().current_scene != null else "unknown"})

func change_scene(path: String) -> Error:
	API.event("Scene", "change scene requested", {"resource": path})
	var result := get_tree().change_scene_to_file(path)
	if result != OK:
		API.report("Scene", "Scene transition failed", {"resource": path, "error_code": result})
	return result

func report(system: String, message: String, details: Dictionary = {}, stack: Array = []) -> void:
	if not enabled:
		return
	var frames: Array[Dictionary] = []
	for frame: Dictionary in stack.slice(1, 65):
		frames.append({"file": String(frame.get("source", "")).replace("\\", "/"), "function": frame.get("function", ""), "line": frame.get("line", 0), "language": "GDScript"})
	bridge.capture({"kind": "gameplay", "capture": "explicit gameplay report (observed)", "severity": "ERROR", "message": Data.text(message), "system": Data.text(system, 80), "source": frames[0] if not frames.is_empty() else {}, "backtrace": frames, "details": Data.safe(details)})

func flush() -> void:
	if not enabled or _closed:
		return
	# Capture callbacks never call this. Providers and all persistence stay on the main thread.
	_refresh_context()
	var batch: Dictionary = bridge.drain()
	dropped_occurrences += int(batch.dropped)
	for key: String in batch.errors:
		var incoming: Dictionary = batch.errors[key]
		if incidents.has(key):
			var incident: Dictionary = incidents[key]
			incident.count += incoming.count
			incident.last_seen = incoming.last_seen
			incident.latest_context = incoming.latest_context
			incident.latest_events = incoming.latest_events
			_sample(incident, incoming)
		elif incidents.size() < max_incidents:
			incoming["schema_version"] = 1
			incoming["id"] = "ADC-" + session_id + "-" + key.left(12)
			incoming["session_id"] = session_id
			incoming["engine_version"] = metadata.engine_version
			incoming["project_version"] = metadata.project_version
			incoming["native_logs"] = incoming.get("native_logs", [native_log])
			incoming["related_incidents"] = []
			incoming["samples"] = []
			_sample(incoming, incoming)
			incidents[key] = incoming
		else:
			dropped_occurrences += int(incoming.count)
			continue
		_dirty[key] = true
	if io_failed:
		return # Latch storage faults: preserve bounded RAM capture, never retry-loop on disk errors.
	for key: String in _dirty:
		var incident: Dictionary = incidents[key]
		var path := session_path.path_join("incidents").path_join(incident.id + ".json")
		_write_json(path, incident)
		_write(path.trim_suffix(".json") + ".txt", Data.compact(incident, path))
	var changed := not _dirty.is_empty()
	if changed:
		_write_index()
		_publish_latest()
		_dirty.clear()
	var ticks := Time.get_ticks_msec()
	if changed or ticks - _checkpoint_ticks >= 10000 or metadata.get("dropped_occurrences", 0) != dropped_occurrences:
		bridge.mutex.lock()
		metadata.context = bridge.context.duplicate(true)
		metadata["recent_events"] = bridge._recent()
		bridge.mutex.unlock()
		metadata["checkpoint"] = Data.now()
		metadata.dropped_occurrences = dropped_occurrences
		_write_json(session_path.path_join("session.json"), metadata)
		_checkpoint_ticks = ticks
	if changed and ticks - _prune_ticks >= 30000:
		_prune()
		_prune_ticks = ticks

func _sample(incident: Dictionary, incoming: Dictionary) -> void:
	var sample := {"time": incoming.last_seen, "context": incoming.latest_context, "recent_events": incoming.latest_events, "details": incoming.get("details", {})}
	var samples: Array = incident.samples
	if samples.is_empty() or JSON.stringify(samples[-1].context) != JSON.stringify(sample.context) or JSON.stringify(samples[-1].recent_events) != JSON.stringify(sample.recent_events):
		if samples.size() >= 4:
			samples.remove_at(1) # Keep first evidence and the latest three distinct contexts.
		samples.append(sample)

func _write_index() -> void:
	var entries: Array = []
	for incident: Dictionary in incidents.values():
		entries.append({"id": incident.id, "last_seen": incident.last_seen, "fingerprint": incident.fingerprint, "count": incident.count})
	_write_json(session_path.path_join("index.json"), entries)

func _publish_latest() -> void:
	# Build a small root entry point from per-session indexes, without reopening detailed reports.
	if io_failed:
		return
	var latest := ""
	var latest_time := ""
	var unresolved: Array[String] = []
	for dir_name: String in DirAccess.get_directories_at(storage.path_join("sessions")):
		var base := storage.path_join("sessions").path_join(dir_name)
		var index: Variant = _read_json(base.path_join("index.json"))
		if not index is Array:
			continue
		for entry: Dictionary in index:
			var resolution: Variant = _read_json(storage.path_join("resolutions").path_join(entry.id + ".json"))
			if resolution is Dictionary and int(resolution.get("occurrence_count", 0)) >= int(entry.count):
				continue
			var path := base.path_join("incidents").path_join(entry.id + ".txt")
			unresolved.append(path)
			if String(entry.last_seen) >= latest_time:
				latest = path
				latest_time = entry.last_seen
	_write(storage.path_join("unresolved.txt"), "\n".join(unresolved) + "\n")
	_write(storage.path_join("latest.txt"), FileAccess.get_file_as_string(latest) if not latest.is_empty() and FileAccess.file_exists(latest) else "No unresolved ADC incidents.\n")

func _recover() -> void:
	for dir_name: String in DirAccess.get_directories_at(storage.path_join("sessions")):
		if dir_name == session_id:
			continue
		var previous_path := storage.path_join("sessions").path_join(dir_name)
		var previous: Variant = _read_json(previous_path.path_join("session.json"))
		if not previous is Dictionary or previous.get("clean_shutdown", false) or previous.has("recovered_by"):
			continue
		if OS.is_process_running(int(previous.get("pid", -1))):
			continue # Parallel editor/test sessions are not crashes. PID reuse is conservatively skipped.
		var evidence := _native_evidence(previous, previous_path)
		bridge.set_context(previous.get("context", {}))
		bridge.capture({"kind": "suspected_termination", "capture": "missing clean-shutdown marker; not proof of a crash", "severity": "ERROR", "system": "Session", "message": "Suspected abnormal termination of session " + dir_name, "source": {}, "backtrace": [], "native_logs": [previous.get("native_log", "unavailable")], "details": {"previous_session": dir_name, "last_checkpoint": previous.get("checkpoint", "unavailable"), "previous_recent_events": previous.get("recent_events", []), "native_evidence": evidence}})
		previous["recovered_by"] = session_id
		_write_json(previous_path.path_join("session.json"), previous)
	_refresh_context()
	_publish_latest()

func _native_evidence(previous: Dictionary, previous_path: String) -> Dictionary:
	var path := String(previous.get("native_log", ""))
	var candidates: Array[String] = []
	if path != native_log and FileAccess.file_exists(path):
		candidates.append(path)
	else:
		# Shared default log has already rotated. Timestamps identify candidates, not proven attribution.
		for file: String in DirAccess.get_files_at(path.get_base_dir()):
			var candidate := path.get_base_dir().path_join(file)
			if candidate != native_log and file.begins_with(path.get_file().get_basename()) and file.ends_with(".log") and FileAccess.get_modified_time(candidate) >= int(previous.get("started_unix", 0)):
				candidates.append(candidate)
	var result := {"candidate_logs": candidates, "attribution": "exact path" if path != native_log else "timestamp candidates; attribution unconfirmed", "crash_signature_found": false}
	for candidate: String in candidates:
		var file := FileAccess.open(candidate, FileAccess.READ)
		if file == null:
			continue
		var length := file.get_length()
		file.seek(maxi(0, length - 1048576))
		var tail := file.get_buffer(mini(length, 1048576)).get_string_from_utf8()
		file.close()
		if "Program crashed with signal" in tail or "Dumping the backtrace" in tail:
			var saved := previous_path.path_join("recovered-native-tail.log")
			_write(saved, tail)
			result["crash_signature_found"] = true
			result["preserved_tail"] = saved
			result["original_bytes"] = length
			break
	return result

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parser := JSON.new()
	var result := parser.parse(file.get_as_text())
	file.close()
	return parser.data if result == OK else null

func _write_json(path: String, value: Variant) -> bool:
	return _write(path, JSON.stringify(value, "\t", true) + "\n")

func _write(path: String, contents: String) -> bool:
	if io_failed:
		return false
	# Same-directory temp + rename avoids partially replacing the last valid report.
	var temporary := path + "." + session_id + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		io_failed = true
		return false
	file.store_string(contents)
	file.flush()
	var result := file.get_error()
	file.close()
	if result != OK or DirAccess.rename_absolute(temporary, path) != OK:
		io_failed = true
		return false
	return true

func _prune() -> void:
	# Only delete closed/recovered ADC-owned session directories; never touch live sessions/native originals.
	if io_failed:
		return
	var sessions: Array[Dictionary] = []
	var total := 0
	for dir_name: String in DirAccess.get_directories_at(storage.path_join("sessions")):
		var path := storage.path_join("sessions").path_join(dir_name)
		var info: Variant = _read_json(path.path_join("session.json"))
		var bytes := _directory_bytes(path)
		total += bytes
		if info is Dictionary and dir_name != session_id and (info.get("clean_shutdown", false) or info.has("recovered_by")) and not OS.is_process_running(int(info.get("pid", -1))):
			sessions.append({"path": path, "time": info.get("started", ""), "bytes": bytes})
	sessions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)
	var count := DirAccess.get_directories_at(storage.path_join("sessions")).size()
	var removed := 0
	for session: Dictionary in sessions:
		if count <= max_sessions and total <= max_bytes:
			break
		_remove_directory(session.path)
		count -= 1
		total -= int(session.bytes)
		removed += 1
	if removed > 0:
		_write_json(storage.path_join("retention.json"), {"time": Data.now(), "removed_sessions": removed, "remaining_bytes": total, "note": "Old ADC evidence expires under configured retention. Native originals are separate."})
	_publish_latest()

func _directory_bytes(path: String) -> int:
	var total := 0
	for file_name: String in DirAccess.get_files_at(path):
		var file := FileAccess.open(path.path_join(file_name), FileAccess.READ)
		if file != null:
			total += file.get_length()
			file.close()
	for directory: String in DirAccess.get_directories_at(path):
		total += _directory_bytes(path.path_join(directory))
	return total

func _remove_directory(path: String) -> void:
	if not path.begins_with(storage.path_join("sessions") + "/"):
		return
	for file_name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory: String in DirAccess.get_directories_at(path):
		_remove_directory(path.path_join(directory))
	DirAccess.remove_absolute(path)

func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE and enabled and not _closed:
		_ending = true
		flush()
		metadata["clean_shutdown"] = true
		metadata["ended"] = Data.now()
		metadata["dropped_occurrences"] = dropped_occurrences
		_write_json(session_path.path_join("session.json"), metadata)
		_closed = true
		OS.remove_logger(bridge)
		API._core = null
