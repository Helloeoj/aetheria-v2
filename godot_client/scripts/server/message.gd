class_name ServerMessage
extends RefCounted

const HELLO := "hello"
const WORLD_STATE := "world_state"
const PLAYER_INPUT := "player_input"
const SYSTEM := "system"

var type := SYSTEM
var payload: Dictionary = {}

func _init(message_type: String = SYSTEM, message_payload: Dictionary = {}) -> void:
	type = message_type
	payload = message_payload

func to_wire() -> String:
	return JSON.stringify({"type": type, "payload": payload})

static func from_wire(data: String) -> ServerMessage:
	var decoded: Variant = JSON.parse_string(data)
	if not decoded is Dictionary:
		return ServerMessage.new(SYSTEM, {})
	var message_type := String(decoded.get("type", SYSTEM))
	if message_type not in [HELLO, WORLD_STATE, PLAYER_INPUT, SYSTEM]:
		message_type = SYSTEM
	var message_payload: Variant = decoded.get("payload", {})
	return ServerMessage.new(message_type, message_payload if message_payload is Dictionary else {})
