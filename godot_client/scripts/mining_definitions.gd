class_name MiningDefinitions
extends RefCounted
## Activity metadata only. GameData remains the sole item catalog.
const Acquisition := preload("res://scripts/acquisition_rules.gd")
var _ores: Dictionary = {}
var _pickaxes: Dictionary = {}

func load_data(path: String = "res://data/mining.json") -> Dictionary:
	return load_records(JSON.parse_string(FileAccess.get_file_as_string(path)))

func load_records(data: Variant) -> Dictionary:
	_ores.clear()
	_pickaxes.clear()
	var errors: Array[String] = []
	if not data is Dictionary or data.get("schema_version") != 1 or not data.get("ores") is Array or not data.get("pickaxes") is Array:
		return {"ok": false, "errors": ["Mining metadata requires schema 1, ores and pickaxes arrays."]}
	for kind: String in ["ores", "pickaxes"]:
		var records: Dictionary = _ores if kind == "ores" else _pickaxes
		for row: Variant in data[kind]:
			if not row is Dictionary or not _integer(row.get("item_id"), 1, CharacterCodec.MAX_COUNT):
				errors.append(kind + ": expected an existing item ID.")
				continue
			var id := int(row.item_id)
			var item := GameData.get_item(id)
			if item.is_empty() or records.has(id) or not _integer(row.get("required_level"), 1, 100):
				errors.append("%s/%d: unknown/duplicate ID or invalid level." % [kind, id])
				continue
			if kind == "ores":
				if not Acquisition.can_mine(item) or not _valid_ore(row):
					errors.append("ores/%d: restricted acquisition or invalid extraction/resource settings." % id)
					continue
			else:
				if not String(item.get("name", "")).to_lower().contains("pickaxe") or not _number(row.get("attempt_interval_seconds"), 0.25, 10.0):
					errors.append("pickaxes/%d: expected a catalog pickaxe and interval 0.25–10." % id)
					continue
			records[id] = row.duplicate(true)
	if not errors.is_empty():
		_ores.clear()
		_pickaxes.clear()
	return {"ok": errors.is_empty(), "errors": errors}

func ore(item_id: int) -> Dictionary:
	return _ores.get(item_id, {}).duplicate(true)

func pickaxe(item_id: int) -> Dictionary:
	return _pickaxes.get(item_id, {}).duplicate(true)

func owns_pickaxe(player: PlayerState, tool: Dictionary) -> bool:
	var item := GameData.get_item(int(tool.get("item_id", 0)))
	return not item.is_empty() and (int(player.backpack.get(String(item.name), 0)) > 0 or int(player.equipment.get("weapon", {}).get("id", 0)) == int(item.id))

func best_pickaxe(player: PlayerState) -> Dictionary:
	var best := {}
	for tool: Dictionary in _pickaxes.values():
		if player.get_skill_level("mining") < int(tool.required_level) or not owns_pickaxe(player, tool):
			continue
		if best.is_empty() or float(tool.attempt_interval_seconds) < float(best.attempt_interval_seconds) or (
			is_equal_approx(float(tool.attempt_interval_seconds), float(best.attempt_interval_seconds)) and int(tool.item_id) < int(best.item_id)):
			best = tool
	return best.duplicate(true)

func success_probability(level: int, definition: Dictionary) -> float:
	if definition.is_empty() or level < int(definition.required_level):
		return 0.0
	var params: Dictionary = definition.success
	var mastery := clampf(float(mini(level, 100) - int(definition.required_level)) / float(params.mastery_levels), 0.0, 1.0)
	return float(params.p_at_unlock) + (float(params.p_at_mastery) - float(params.p_at_unlock)) * pow(mastery, float(params.curve_exponent))

func _valid_ore(row: Dictionary) -> bool:
	if not _integer(row.get("xp_reward"), 1, SkillProgression.MAX_EXPERIENCE) or not _positive(row.get("respawn_seconds")):
		return false
	var params: Variant = row.get("success")
	if not params is Dictionary or not _positive(params.get("p_at_unlock")) or not _number(params.get("p_at_mastery"), float(params.p_at_unlock), 1.0):
		return false
	if not _integer(params.get("mastery_levels"), 1, 99) or not _positive(params.get("curve_exponent")):
		return false
	var scene_path: Variant = row.get("node_scene")
	if not scene_path is String or not ResourceLoader.exists(scene_path, "PackedScene"):
		return false
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return false
	var state := scene.get_state()
	var shared_script := false
	for property in state.get_node_property_count(0):
		if state.get_node_property_name(0, property) == "script":
			var script: Variant = state.get_node_property_value(0, property)
			shared_script = script is Script and script.resource_path == "res://scripts/mining_deposit.gd"
	if not shared_script or not row.get("visual") is Dictionary:
		return false
	for key: String in ["available", "depleted"]:
		var path: Variant = row.visual.get(key)
		# Empty means unbound content, never a fabricated texture or live placement.
		if not path is String or (not path.is_empty() and not ResourceLoader.exists(path, "Texture2D")):
			return false
	return true

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func _integer(value: Variant, low: int, high: int) -> bool:
	return _number(value, low, high) and floor(float(value)) == float(value)

static func _positive(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) > 0.0
