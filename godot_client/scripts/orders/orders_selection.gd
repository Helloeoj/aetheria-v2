extends RefCounted
## Shared eligibility rules for authored content validation and generation.

static func objective_key(row: Dictionary) -> String:
	return JSON.stringify([String(row.kind),String(row.anchor_id),String(row.get("target_id","")),
		String(row.get("skill","")),int(row.get("level",0)),String(row.get("item_name","")),
		String(row.get("answer","")).strip_edges().to_lower()])

static func family_weight(config: Dictionary, kind: String) -> float:
	return float(config.get("family_weights",{}).get(kind,1.0))

static func distinct_count(rows: Array) -> int:
	var keys := {}
	for row: Dictionary in rows:
		keys[objective_key(row)] = true
	return keys.size()

static func pools(config: Dictionary, tier: String) -> Dictionary:
	var result := {}
	for cache_id: String in config.anchors:
		if tier not in config.anchors[cache_id].tiers:
			continue
		var ordinary: Array = []
		var gates: Array = []
		for row: Dictionary in config.templates:
			# Disabled future templates need not have live world or tier bindings.
			if row.get("enabled",true) == false:
				continue
			if tier not in row.tiers or row.anchor_id == cache_id or family_weight(config,row.kind) <= 0:
				continue
			if row.kind == "equipment" or int(row.get("level",0)) > 0:
				gates.append(row)
			else:
				ordinary.append(row)
		result[cache_id] = {"ordinary":ordinary,"gates":gates,
			"ordinary_count":distinct_count(ordinary),"gate_count":distinct_count(gates)}
	return result

static func reveal_order(rows: Array, rng: RandomNumberGenerator) -> Array:
	var groups := {}
	for row: Dictionary in rows:
		if not groups.has(row.kind): groups[row.kind] = []
		groups[row.kind].append(row)
	var result: Array = []
	var previous := ""
	while result.size() < rows.size():
		var candidates: Array = []
		var largest := 0
		for kind: String in groups:
			if kind == previous or groups[kind].is_empty(): continue
			if groups[kind].size() > largest:
				largest = groups[kind].size()
				candidates.clear()
			if groups[kind].size() == largest: candidates.append(kind)
		if candidates.is_empty(): candidates.append(previous)
		var kind: String = candidates[rng.randi_range(0,candidates.size()-1)]
		var index := rng.randi_range(0,groups[kind].size()-1)
		result.append(groups[kind][index])
		groups[kind].remove_at(index)
		previous = kind
	return result
