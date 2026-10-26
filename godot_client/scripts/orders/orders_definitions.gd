extends RefCounted
## Authored metadata only. Disabled rewards never enter the live acquisition pool.
const Protocol := preload("res://network/world_protocol.gd")
const Acquisition := preload("res://scripts/acquisition_rules.gd")
const Selection := preload("res://scripts/orders/orders_selection.gd")
const KINDS := ["riddle", "search", "cipher", "fishing", "cooking", "equipment", "combat"]
const TIERS := ["deckhand", "smuggler", "corsair", "dread_captain"]
const MAX_COUNT := 2147483647
const INTERACTION_SCRIPTS := {"portal":"res://scripts/cave_portal.gd", "fish":"res://scripts/fishing_spot.gd", "cook":"res://scripts/cooking_station.gd"}
const SAFE_BASE_REWARDS := ["Feathers", "Arrow Shafts", "Bowstring", "Bronze Ore", "Bronze Ingot", "Bronze Arrowheads", "Iron Ore", "Iron Ingot", "Bronze Arrows", "Iron Arrows", "Low Grade Fish Food", "Medium Grade Fish Food", "High Grade Fish Food"]
var _scene_node_kinds: Dictionary = {}

func load_data(path: String = "res://data/dead_man_orders.json") -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "errors": ["Orders definitions file is unavailable."], "config": {}}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {"ok": false, "errors": ["Orders definitions must be an object."], "config": {}}
	var errors := validate(parsed)
	return {"ok": errors.is_empty(), "errors": errors, "config": parsed if errors.is_empty() else {}}

func validate(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if config.get("version") != 1:
		errors.append("Orders definitions require version 1.")
	if not config.get("enabled") is bool:
		errors.append("Orders definitions require an explicit enabled flag.")
	for field: String in ["tiers", "anchors", "acquisition"]:
		if not config.get(field) is Dictionary:
			errors.append(field + " must be an object.")
	for field: String in ["templates", "base_rewards", "deferred"]:
		if not config.get(field) is Array:
			errors.append(field + " must be an array.")
	if not errors.is_empty():
		return errors
	if not config.get("family_weights",{}) is Dictionary:
		errors.append("Family weights must be an object.")
		return errors
	for kind: Variant in config.get("family_weights",{}):
		if kind not in KINDS or not _number(config.family_weights[kind],0.0,1000000.0):
			errors.append("Invalid directive family weight: "+str(kind))
	var tiers: Dictionary = config.tiers
	var enabled: bool = config.enabled
	for tier_id: String in TIERS:
		if not tiers.get(tier_id) is Dictionary:
			errors.append("Missing Orders tier: " + tier_id)
			continue
		var tier: Dictionary = tiers[tier_id]
		if not _text(tier.get("name")) or not _text(tier.get("item_name")) or not _integer(tier.get("item_id"), 1, MAX_COUNT):
			errors.append(tier_id + ": tier needs a catalog item and name.")
		elif enabled:
			var item := GameData.get_item(int(tier.item_id))
			if item.is_empty() or String(item.get("name", "")) != String(tier.item_name) or bool(item.get("generic_loot", true)):
				errors.append(tier_id + ": sealed item must exist and be excluded from generic loot.")
		var ranges := [["min_directives", "max_directives", 2, 7], ["skill_min", "skill_max", 0, 100]]
		if enabled:
			ranges.append(["gold_min", "gold_max", 0, MAX_COUNT])
		for pair: Array in ranges:
			if not _integer(tier.get(pair[0]), int(pair[2]), int(pair[3])) or not _integer(tier.get(pair[1]), int(pair[2]), int(pair[3])) or float(tier.get(pair[0], 0)) > float(tier.get(pair[1], 0)):
				errors.append(tier_id + ": invalid " + String(pair[0]) + "/" + String(pair[1]) + ".")
		if not _integer(tier.get("slots"), 1, 3) or not _integer(tier.get("max_gates"), 0, 3) or not _number(tier.get("gate_chance"), 0.0, 1.0) or (enabled and not _integer(tier.get("reward_rolls"), 1, 8)):
			errors.append(tier_id + ": invalid slots, gates or reward rolls.")
		elif _integer(tier.get("min_directives"),2,7) and int(tier.slots) > int(tier.min_directives):
			errors.append(tier_id + ": available slots exceed minimum directive count.")
		if tier_id == "deckhand" and (tier.get("max_gates") != 0 or tier.get("gate_chance") != 0 or tier.get("skill_min") != 0 or tier.get("skill_max") != 0):
			errors.append("Deckhand Orders must remain ungated.")
	for key: String in tiers:
		if key not in TIERS:
			errors.append("Unknown Orders tier: " + key)
	for chance: String in ["fishing_chance", "monster_chance"]:
		if not _number(config.acquisition.get(chance), 0.0, 1.0):
			errors.append("Invalid acquisition probability: " + chance)
	for value: Variant in config.deferred:
		if not value is Dictionary or value.get("enabled") != false or not _text(value.get("reason")):
			errors.append("Deferred content must remain disabled with an explicit reason.")
	if not errors.is_empty():
		return errors
	if not enabled:
		if not config.anchors.is_empty() or not config.templates.is_empty() or not config.base_rewards.is_empty() or config.acquisition.get("fishing_chance") != 0 or config.acquisition.get("monster_chance") != 0:
			errors.append("Disabled framework must not bind live content, rewards or acquisition probabilities.")
		return errors
	var anchors: Dictionary = config.anchors
	for id: String in anchors:
		if not anchors[id] is Dictionary:
			errors.append("Invalid anchor: " + id)
			continue
		var anchor: Dictionary = anchors[id]
		if not _text(anchor.get("label")) or not _text(anchor.get("hint")) or String(anchor.get("interaction_kind", "")) not in ["portal", "fish", "cook"] or not _tier_refs(anchor.get("tiers")):
			errors.append(id + ": invalid anchor interaction, text or tiers.")
		if not _scene_has_node(String(anchor.get("region_id", "")), String(anchor.get("node_path", "")), String(anchor.get("interaction_kind", ""))):
			errors.append(id + ": anchor node is absent or incompatible with its interaction kind.")
	var ids := {}
	for value: Variant in config.templates:
		if not value is Dictionary:
			errors.append("Template must be an object.")
			continue
		var row: Dictionary = value
		var id := String(row.get("id", ""))
		if id.is_empty() or ids.has(id):
			errors.append("Missing or duplicate template ID: " + id)
		ids[id] = true
		if not row.get("enabled",true) is bool:
			errors.append(id + ": enabled must be a boolean.")
			continue
		if row.get("enabled",true) == false:
			continue
		var anchor_id := String(row.get("anchor_id", ""))
		if not anchors.get(anchor_id) is Dictionary:
			errors.append(id + ": unknown anchor.")
			continue
		if String(row.get("kind", "")) not in KINDS or not _tier_refs(row.get("tiers")) or not _text(row.get("text")) or not _number(row.get("weight"), 0.000001, 1000000.0):
			errors.append(id + ": invalid kind, tiers, text or weight.")
			continue
		var anchor: Dictionary = anchors.get(anchor_id, {})
		for tier_id: String in row.tiers:
			if tier_id not in anchor.get("tiers", []):
				errors.append(id + ": tier cannot reach this anchor.")
		if row.has("skill") and String(row.skill) not in SkillProgression.SKILL_IDS:
			errors.append(id + ": unknown actual game skill.")
		if row.has("level") and (not row.has("skill") or not _integer(row.level, 1, 100)):
			errors.append(id + ": level requires an actual skill and range 1–100.")
		if row.has("skill") and not row.has("level"):
			errors.append(id + ": skill requires an explicit level.")
		if _integer(row.get("level"),1,100):
			for tier_id: String in row.tiers:
				var tier: Dictionary = tiers[tier_id]
				if int(tier.max_gates) == 0 or not _number(row.level,float(tier.skill_min),float(tier.skill_max)):
					errors.append(id + ": requirement exceeds its tier's gate rules.")
		if row.has("item_name") and GameData.get_item_by_name(String(row.item_name)).is_empty():
			errors.append(id + ": unknown actual catalog item.")
		if row.kind == "cipher" and not _text(row.get("answer")):
			errors.append(id + ": cipher needs an authored answer.")
		if row.kind in ["fishing", "cooking"]:
			var skill := "fishing" if row.kind == "fishing" else "cooking"
			var interaction := "fish" if row.kind == "fishing" else "cook"
			var item := GameData.get_item_by_name(String(row.get("item_name", "")))
			if row.get("skill") != skill or not _integer(row.get("level"), 1, 100) or anchor.get("interaction_kind") != interaction or item.is_empty() or String(item.get("fish_species", "")) != String(row.get("target_id", "")):
				errors.append(id + ": activity gate must reference a real species, skill and station.")
		if row.kind in ["equipment", "combat"]:
			errors.append(id + ": equipment and combat templates await verified content support.")
	if not errors.is_empty():
		return errors
	for tier_id: String in TIERS:
		var viable := false
		for pool: Dictionary in Selection.pools(config,tier_id).values():
			if int(pool.ordinary_count) >= int(tiers[tier_id].max_directives):
				viable = true
				break
		if not viable:
			errors.append(tier_id + ": insufficient distinct ordinary directives after excluding the final cache and disabled families.")
	if config.base_rewards.is_empty():
		errors.append("Orders require an existing base reward pool.")
	for value: Variant in config.base_rewards:
		if not value is Dictionary:
			errors.append("Base reward must be an object.")
			continue
		var row: Dictionary = value
		var item := GameData.get_item_by_name(String(row.get("item_name", "")))
		# Explicit safe supplies only: no boss routes, pending policies, mega gear or artifacts.
		var policy: Dictionary = Acquisition.policy().get("item_policies", {}).get(String(item.get("name", "")), {})
		if String(item.get("name", "")) not in SAFE_BASE_REWARDS or item.is_empty() or bool(item.get("legacy_placeholder", false)) or bool(item.get("is_artifact", false)) or int(item.get("tier", 100)) > 3 or String(item.get("type", "")) not in ["Crafting", "Ammunition", "Fishing Bait"] or String(policy.get("drop_route", "")) in ["bosses", "pending", "none"]:
			errors.append("Restricted or unknown base reward: " + String(row.get("item_name", "")))
		if not _integer(row.get("min"), 1, MAX_COUNT) or not _integer(row.get("max"), 1, MAX_COUNT) or float(row.get("min", 0)) > float(row.get("max", 0)) or not _number(row.get("weight"), 0.000001, 1000000.0):
			errors.append("Invalid reward quantity or weight.")
	return errors

func _scene_has_node(region_id: String, node_path: String, kind: String) -> bool:
	if not Protocol.REGIONS.has(region_id) or node_path.is_empty() or not INTERACTION_SCRIPTS.has(kind):
		return false
	if not _scene_node_kinds.has(region_id):
		var scene := load(String(Protocol.REGIONS[region_id])) as PackedScene
		if scene == null:
			return false
		_scene_node_kinds[region_id] = _node_kinds(scene.get_state())
	return kind in _scene_node_kinds[region_id].get(node_path.trim_prefix("./"), [])

func _node_kinds(state: SceneState, depth: int = 0) -> Dictionary:
	if state == null or depth > 16:
		return {}
	var result := _node_kinds(state.get_base_scene_state(), depth + 1)
	for index in state.get_node_count():
		var path := String(state.get_node_path(index)).trim_prefix("./")
		var instance := state.get_node_instance(index)
		if instance != null:
			var nested := _node_kinds(instance.get_state(), depth + 1)
			for nested_path: String in nested:
				var full_path := path if nested_path == "." else (nested_path if path == "." else path + "/" + nested_path)
				result[full_path] = nested[nested_path]
		var script: Script = null
		var has_script := false
		for property in state.get_node_property_count(index):
			if String(state.get_node_property_name(index, property)) == "script":
				has_script = true
				var value: Variant = state.get_node_property_value(index, property)
				if value is Script:
					script = value
				break
		if has_script:
			var kinds: Array[String] = []
			for kind: String in INTERACTION_SCRIPTS:
				if _script_matches_kind(script, kind):
					kinds.append(kind)
			result[path] = kinds
		elif not result.has(path):
			result[path] = [] # Unresolved metadata fails closed instead of guessing a class.
	return result

func _script_matches_kind(script: Script, kind: String) -> bool:
	if not INTERACTION_SCRIPTS.has(kind):
		return false
	for _depth in range(64):
		if script == null:
			return false
		if script.resource_path == INTERACTION_SCRIPTS[kind]:
			return true
		script = script.get_base_script()
	return false

func _tier_refs(value: Variant) -> bool:
	if not value is Array or value.is_empty():
		return false
	for tier_id: Variant in value:
		if not tier_id is String or tier_id not in TIERS:
			return false
	return true

func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

func _number(value: Variant, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= low and float(value) <= high

func _integer(value: Variant, low: int, high: int) -> bool:
	return _number(value, low, high) and floor(float(value)) == float(value)
