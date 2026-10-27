class_name WorldProtocol
extends RefCounted
const VERSION := 1
const MAX_PAYLOAD := 256 * 1024
const REGIONS := {
	"outskirts": "res://scenes/EastOutskirtsLayered.tscn",
	"golem": "res://scenes/GolemKingdom.tscn",
	"tavern": "res://scenes/TavernInterior.tscn",
	"catacombs": "res://scenes/CatacombsFloor01.tscn",
	"bracken_mine": "res://scenes/BrackenMine.tscn",
}

static func pack(message: Dictionary) -> PackedByteArray:
	return JSON.stringify(message).to_utf8_buffer()

static func unpack(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_PAYLOAD:
		return {}
	var message: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not message is Dictionary or not message.get("type") is String:
		return {}
	var version: Variant = message.get("v")
	if not (version is int or version is float) or not is_finite(float(version)) or float(version) != float(VERSION):
		return {}
	return message

static func region_for_scene(scene_path: String) -> String:
	for region: String in REGIONS:
		if REGIONS[region] == scene_path:
			return region
	return ""
