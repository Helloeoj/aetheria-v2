extends RefCounted
## Durable reservation/earned-work ledger. Save recovery never trusts item/XP payloads.
const Rules = preload("res://scripts/smithing_rules.gd")
const Crafting = preload("res://scripts/crafting_service.gd")

static func record(player: PlayerState) -> Dictionary:
	if not player.pending_smithing_record.is_empty(): return player.pending_smithing_record.duplicate(true)
	var session: RefCounted = player.active_smithing_session.get_ref() if player.active_smithing_session != null else null
	if session == null: session = player.pending_smithing_session
	if session == null or not session.is_active(): return {}
	return {"recipe_id":session.recipe_id, "quantity":session.batch,
		"earned":session.state in [SmithingSession.State.QUENCHING, SmithingSession.State.CLAIM_PENDING],
		"temperature":session.temperature, "overheated_seconds":session.overheated_seconds}

static func validate(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true
	if value.size() != 5 or not value.get("recipe_id") is String or not value.get("earned") is bool: return false
	var recipe := Crafting._find_recipe(value.recipe_id)
	if not recipe.get("enabled", false) or recipe.get("station") not in ["furnace", "anvil"]: return false
	var quantity: Variant = value.get("quantity")
	if not (quantity is int or quantity is float) or not is_finite(float(quantity)) or float(quantity) != floor(float(quantity)) or float(quantity) < 1 or float(quantity) > (10 if recipe.station == "furnace" else 1): return false
	for key: String in ["temperature", "overheated_seconds"]:
		var number: Variant = value.get(key)
		if not (number is int or number is float) or not is_finite(float(number)) or float(number) < 0: return false
	return float(value.temperature) <= 1.0 and float(value.overheated_seconds) <= 3600.0

static func retry(player: PlayerState) -> bool:
	var data := player.pending_smithing_record
	if data.is_empty(): return true
	if not validate(data): return false
	var recipe := Crafting._find_recipe(data.recipe_id)
	var inputs := Crafting._quantities(recipe.inputs, int(data.quantity))
	var outputs := Crafting._quantities(recipe.outputs, int(data.quantity))
	if not inputs.ok or not outputs.ok: return false
	var item := GameData.get_item_by_name(str(outputs.items.keys()[0]))
	var heat := Rules.heat_profile(int(item.tier), player.get_skill_level("smithing"))
	var burnt := false
	if not data.earned and recipe.station == "furnace" and float(data.temperature) > float(heat.high) and not heat.immune:
		# Recovery resolves natural cooling and the outstanding burn timer;
		# reconnecting cannot turn an abandoned doomed batch into a refund.
		var cooling := float(Rules.settings().cooling_per_second)
		var cooling_seconds := (float(data.temperature) - float(heat.high)) / cooling if cooling > 0 else INF
		burnt = float(data.overheated_seconds) + cooling_seconds >= float(heat.grace)
	var items: Dictionary = outputs.items if data.earned else ({} if burnt else inputs.items)
	var next := player.backpack.duplicate(true)
	for name_key: String in items:
		var current := Crafting._available(next, name_key)
		if current < 0 or current > 2147483647 - int(items[name_key]) or (not next.has(name_key) and next.size() >= 4096): return false
		next[name_key] = int(next.get(name_key, 0)) + int(items[name_key])
	player.backpack = next
	if data.earned:
		var bars := int(data.quantity)
		if recipe.station == "anvil":
			bars = 0
			for name_key: String in inputs.items:
				if name_key.ends_with(" Ingot"): bars += int(inputs.items[name_key])
		player.add_skill_experience("smithing", bars * Rules.xp_per_bar(int(item.tier)))
	player.pending_smithing_record = {}
	return true
