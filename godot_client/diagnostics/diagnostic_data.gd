extends RefCounted
## Pure, bounded serialization. Never retains gameplay Objects or stack variables.

static func now() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"

static func text(value: String, limit: int = 2048) -> String:
	var result := value.left(limit)
	var secret := RegEx.new()
	secret.compile("(?i)(password|passwd|token|authorization|api[_-]?key|secret|cookie)\\s*[:=]\\s*[^\\s,;]+")
	return secret.sub(result, "$1=[REDACTED]", true)

static func safe(value: Variant, depth: int = 0) -> Variant:
	if depth > 3:
		return "[depth limit]"
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			if result.size() >= 16:
				break
			if not key is String:
				continue
			var lower := String(key).to_lower()
			var sensitive := false
			for name: String in ["password", "passwd", "token", "authorization", "secret", "cookie", "api_key", "email", "credential"]:
				if name in lower:
					sensitive = true
			result[text(key, 80)] = "[REDACTED]" if sensitive else safe(value[key], depth + 1)
		if depth == 0:
			var encoded := JSON.stringify(result)
			if encoded.length() > 4096:
				return {"truncated": true, "preview": encoded.left(4096)}
		return result
	if value is Array:
		var result: Array = []
		for entry: Variant in value.slice(0, 16):
			result.append(safe(entry, depth + 1))
		return result
	if value is Vector2 or value is Vector2i:
		return [value.x, value.y]
	if value is String or value is StringName or value is NodePath:
		return text(str(value), 512)
	if value == null or value is bool or value is int or value is float:
		return value
	return "[object omitted]"

static func normalized(value: String) -> String:
	var result := value.replace("\\", "/")
	for pattern: String in ["0x[0-9a-fA-F]+", "(?i)(?:instance[_ ]?id|object[_ ]?id)[:= ]+[0-9]+", "[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9:.]+Z?"]:
		var regex := RegEx.new()
		regex.compile(pattern)
		result = regex.sub(result, "<volatile>", true)
	return result

static func fingerprint(error: Dictionary) -> String:
	# Preserve resource names, numeric gameplay IDs and call sites: they can identify different bugs.
	var signature := [error.get("kind", ""), error.get("system", ""), normalized(error.get("message", "")), normalized(error.get("code", "")), error.get("source", {}), error.get("engine_source", {})]
	for frame: Dictionary in error.get("backtrace", []).slice(0, 8):
		signature.append(frame)
	return JSON.stringify(signature, "", true).sha256_text()

static func compact(incident: Dictionary, detail_path: String) -> String:
	var source: Dictionary = incident.get("source", {})
	var context: Dictionary = incident.get("context", {})
	var lines: Array[String] = ["AETHERIA DIAGNOSTIC REPORT", "Incident: %s | %s | occurrences: %d" % [incident.id, incident.severity, incident.count], "First: %s | Last: %s" % [incident.first_seen, incident.last_seen], "Scene: %s | System: %s" % [context.get("scene", "unknown"), incident.system], "Error: " + String(incident.message).left(650), "Source: %s:%s @ %s" % [source.get("file", "unavailable"), source.get("line", "?"), source.get("function", "unavailable")]]
	var events: Array = incident.get("recent_events", [])
	lines.append("Recent events (observed; proximity does not prove cause):")
	for event: Dictionary in events.slice(maxi(0, events.size() - 6)):
		lines.append("- %s / %s %s" % [event.system, event.action, JSON.stringify(event.get("data", {})).left(160)])
	if events.is_empty():
		lines.append("- No gameplay breadcrumbs available.")
	lines.append("Context: " + JSON.stringify(context).left(350))
	var files: Array = []
	for frame: Dictionary in incident.get("backtrace", []):
		var path := String(frame.get("file", ""))
		if path.begins_with("res://") and path not in files and files.size() < 5:
			files.append(path)
	if source.get("file", "") not in files:
		files.push_front(source.get("file", "unavailable"))
	lines.append("Relevant files (evidence locations): " + ", ".join(files))
	lines.append("Evidence: %s; %d context samples in detailed JSON." % [incident.get("capture", "explicit report"), incident.get("samples", []).size()])
	lines.append("Hypothesis: None established. Inspect source and preceding actions first.")
	lines.append("Reproduction: Not confirmed; resolution requires recorded validation.")
	lines.append("Detailed JSON: " + detail_path)
	lines.append("Native logs: " + str(incident.get("native_logs", [])))
	return "\n".join(lines) + "\n"
