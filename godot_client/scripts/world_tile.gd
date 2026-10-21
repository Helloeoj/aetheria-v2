class_name WorldTile
extends RefCounted

var x := 0
var y := 0
var region := ""
var biome := ""
var danger_level := 0
var description := ""
var safezone := false
var npcs: Array[String] = []
var services: Array[String] = []
var enemies: Array[String] = []

func _init(tile_x: int, tile_y: int, tile_region: String, tile_biome: String, danger: int,
		tile_description: String = "", is_safezone: bool = false,
		npc_names: Array[String] = [], service_names: Array[String] = [], enemy_names: Array[String] = []) -> void:
	x = tile_x
	y = tile_y
	region = tile_region
	biome = tile_biome
	danger_level = danger
	description = tile_description
	safezone = is_safezone
	npcs = npc_names.duplicate()
	services = service_names.duplicate()
	enemies = enemy_names.duplicate()

func to_dict() -> Dictionary:
	return {
		"x": x, "y": y, "region": region, "biome": biome,
		"danger_level": danger_level, "description": description,
		"safezone": safezone, "npcs": npcs, "services": services, "enemies": enemies
	}
