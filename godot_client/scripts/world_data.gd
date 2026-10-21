class_name WorldDataWorld
extends RefCounted

var width := 300
var height := 300
var world_map: Dictionary = {}
var ticks := 0

func _init(world_width: int = 300, world_height: int = 300) -> void:
	width = world_width
	height = world_height
	var source: Dictionary = GameData.world_data
	for raw_tile: Dictionary in source.get("tiles", []):
		add_tile(
			int(raw_tile.get("x", 0)), int(raw_tile.get("y", 0)),
			String(raw_tile.get("region", "")), String(raw_tile.get("biome", "")),
			int(raw_tile.get("danger_level", 0)), String(raw_tile.get("description", "")),
			bool(raw_tile.get("safezone", false)), raw_tile.get("npcs", []),
			raw_tile.get("services", []), raw_tile.get("enemies", [])
		)

func add_tile(x: int, y: int, region: String, biome: String, danger_level: int,
		description: String = "", safezone: bool = false, npcs = [],
		services = [], enemies = []) -> void:
	var npc_names: Array[String] = []
	var service_names: Array[String] = []
	var enemy_names: Array[String] = []
	for entry: Variant in npcs:
		npc_names.append(String(entry))
	for entry: Variant in services:
		service_names.append(String(entry))
	for entry: Variant in enemies:
		enemy_names.append(String(entry))
	world_map[Vector2i(x, y)] = WorldTile.new(x, y, region, biome, danger_level,
		description, safezone, npc_names, service_names, enemy_names)

func get_tile(x: int, y: int) -> WorldTile:
	return world_map.get(Vector2i(x, y))

func tick() -> Dictionary:
	ticks += 1
	var towns: Array[String] = []
	for tile: WorldTile in world_map.values():
		if tile.safezone:
			towns.append(tile.region)
	return {"tick": ticks, "towns": towns, "tiles": world_map.size()}
