extends RefCounted
## A public release profile; never contains a private key or developer credential.
const PATH := "res://data/beta_client.json"

static func read_profile() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return value if valid(value) else {}

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("schema") != 1:
		return false
	for field: String in ["release_id", "world_id", "world_host", "tls_name", "tls_certificate", "account_url"]:
		if not value.get(field) is String or String(value[field]).is_empty():
			return false
	if RegEx.create_from_string("^[A-Za-z0-9_.-]{1,80}$").search(value.release_id) == null:
		return false
	if RegEx.create_from_string("^[A-Za-z0-9_-]{1,64}$").search(value.world_id) == null:
		return false
	if not String(value.account_url).begins_with("https://") or "@" in String(value.account_url):
		return false
	if not String(value.tls_certificate).begins_with("res://data/") or ".." in String(value.tls_certificate):
		return false
	var port_value: Variant = value.get("world_port")
	return (port_value is int or port_value is float) and is_finite(float(port_value)) and float(port_value) == floor(float(port_value)) and float(port_value) >= 1 and float(port_value) <= 65535
