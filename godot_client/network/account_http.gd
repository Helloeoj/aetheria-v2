class_name AccountHTTP
extends Node
## Credentials stay in memory and never enter diagnostics or gameplay RPCs.
var endpoint := "http://127.0.0.1:8780"

func request_json(route: String, data: Dictionary = {}, bearer: String = "", server_key: String = "", method: int = HTTPClient.METHOD_POST) -> Dictionary:
	if not _allowed_endpoint(endpoint) or not route.begins_with("/"):
		return {"ok": false, "code": "endpoint", "message": "Use HTTPS for a remote account service."}
	var http := HTTPRequest.new()
	http.timeout = 8.0
	http.body_size_limit = 2 * 1024 * 1024
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not bearer.is_empty():
		headers.append("Authorization: Bearer " + bearer)
	if not server_key.is_empty():
		headers.append("X-Aetheria-Server-Key: " + server_key)
	var error := http.request(endpoint.trim_suffix("/") + route, headers, method, "" if method == HTTPClient.METHOD_GET else JSON.stringify(data))
	if error != OK:
		http.queue_free()
		return {"ok": false, "code": "unavailable", "message": "The account service is unavailable."}
	var response: Array = await http.request_completed
	http.queue_free()
	if int(response[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "code": "unavailable", "message": "The account service could not confirm the request. Please try again."}
	var parsed: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	if not parsed is Dictionary or not parsed.has("ok"):
		return {"ok": false, "code": "response", "message": "The account service returned an invalid response."}
	return parsed

static func _allowed_endpoint(url: String) -> bool:
	if url.length() > 256 or url.contains("@") or url.contains("?") or url.contains("#"):
		return false
	return url.begins_with("https://") or RegEx.create_from_string("^http://(127\\.0\\.0\\.1|localhost|\\[::1\\])(:[0-9]+)?/?$").search(url) != null
