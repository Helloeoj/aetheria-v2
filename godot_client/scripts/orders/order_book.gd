extends RefCounted
## Bounded private order instances. Public views never contain sealed content.
const TIERS := ["deckhand", "smuggler", "corsair", "dread_captain"]
const STATES := ["active", "cache_revealed", "claimed", "abandoned", "suspended"]
const Handlers := preload("res://scripts/orders/orders_directives.gd")
const KINDS := Handlers.KINDS
const MAX_COUNT := 2147483647
const LIVE_STATES := ["active", "cache_revealed", "suspended"]
const TITLES := {"deckhand":"Deckhand", "smuggler":"Smuggler", "corsair":"Corsair", "dread_captain":"Dread Captain"}

static func empty_book() -> Dictionary:
	return {"version":2,"generations":{"deckhand":0,"smuggler":0,"corsair":0,"dread_captain":0},"orders":{},
		"collection":{},"completed":{"deckhand":0,"smuggler":0,"corsair":0,"dread_captain":0}}

static func opened_name(tier: String) -> String:
	return String(TITLES.get(tier,"")) + "'s Order" if tier in TIERS else ""

static func migrate_legacy(value: Variant, owner_id: String) -> Dictionary:
	if not value is Dictionary or value.get("version") != 1 or value.size() != 3:
		return {}
	var migrated: Dictionary = value.duplicate(true)
	migrated.version = 2
	migrated.collection = {}
	migrated.completed = empty_book().completed
	return migrated if validate_book(migrated,owner_id) else {}

static func inventory_valid(player: Variant) -> bool:
	if not validate_book(player.dead_man_orders,player.entity_id):
		return false
	for tier: String in TIERS:
		var order: Dictionary = player.dead_man_orders.orders.get(tier,{})
		var expected := int(order.get("state","") in LIVE_STATES)
		if int(player.backpack.get(opened_name(tier),0)) != expected:
			return false
	return true

static func validate_book(value: Variant, owner_id: String = "") -> bool:
	if not value is Dictionary or value.size() != 5 or value.get("version") != 2:
		return false
	if not value.get("collection") is Dictionary or value.collection.size() > 4096 or not value.get("completed") is Dictionary or value.completed.size() != TIERS.size():
		return false
	for item_id: Variant in value.collection:
		if not item_id is String or not item_id.is_valid_int() or str(int(item_id)) != item_id or int(item_id) <= 0 or int(item_id) > MAX_COUNT or not integer(value.collection[item_id],1,MAX_COUNT):
			return false
	if not value.get("generations") is Dictionary or not value.get("orders") is Dictionary:
		return false
	if value.generations.size() != TIERS.size() or value.orders.size() > TIERS.size():
		return false
	for tier: String in TIERS:
		if not integer(value.generations.get(tier),0,MAX_COUNT) or not integer(value.completed.get(tier),0,MAX_COUNT):
			return false
	var ids := {}
	for tier: Variant in value.orders:
		if tier not in TIERS or not value.orders[tier] is Dictionary:
			return false
		var order: Dictionary = value.orders[tier]
		if not _order_valid(order, String(tier), int(value.generations[tier]), owner_id):
			return false
		if ids.has(order.id):
			return false
		ids[order.id] = true
	return true

static func _order_valid(order: Dictionary, tier: String, generation: int, owner_id: String) -> bool:
	for field: String in ["id","owner","tier","state","cache"]:
		if not text(order.get(field),128):
			return false
	if not integer(order.get("generation"),1,MAX_COUNT):
		return false
	if order.tier != tier or order.state not in STATES or int(order.generation) != generation or generation < 1:
		return false
	if not owner_id.is_empty() and order.owner != owner_id:
		return false
	if not integer(order.get("config_version"),1,MAX_COUNT) or not integer(order.get("slots"),1,3):
		return false
	if not order.get("directives") is Array or order.directives.size() < 2 or order.directives.size() > 7:
		return false
	var available := 0
	var completed := 0
	var ids := {}
	for directive: Variant in order.directives:
		if not directive is Dictionary:
			return false
		for field: String in ["id","template_id","anchor_id","kind"]:
			if not text(directive.get(field),128):
				return false
		if ids.has(directive.id) or directive.kind not in KINDS or directive.get("state") not in ["sealed","available","completed"]:
			return false
		ids[directive.id] = true
		if not text(directive.get("text"),2048):
			return false
		for field: String in ["target_id","skill","item_name","answer"]:
			if not text(directive.get(field),256,true):
				return false
		if not integer(directive.get("level"),0,SkillProgression.MAX_LEVEL):
			return false
		if not String(directive.skill).is_empty() and directive.skill not in SkillProgression.SKILL_IDS:
			return false
		available += int(directive.state == "available")
		completed += int(directive.state == "completed")
	if available > int(order.slots):
		return false
	if order.state == "active" and (available == 0 or completed == order.directives.size()):
		return false
	if order.state in ["cache_revealed","claimed"] and completed != order.directives.size():
		return false
	if not order.get("cache_info") is Dictionary:
		return false
	for field: String in ["region_id","label","hint"]:
		if not text(order.cache_info.get(field),2048):
			return false
	var rewards: Variant = order.get("rewards")
	if not rewards is Dictionary or not integer(rewards.get("gold"),0,MAX_COUNT) or not rewards.get("items") is Array or rewards.items.size() > 32:
		return false
	var reward_names := {}
	for entry: Variant in rewards.items:
		if not entry is Dictionary or not text(entry.get("item_name"),128) or not integer(entry.get("count"),1,MAX_COUNT):
			return false
		if reward_names.has(entry.item_name):
			return false
		reward_names[entry.item_name] = true
	return true

static func public_book(book: Dictionary) -> Dictionary:
	if not validate_book(book):
		return {"generations":{},"orders":{}}
	var result := {"generations":book.generations.duplicate(),"orders":{},"collection":book.collection.duplicate(),"completed":book.completed.duplicate()}
	for tier: String in book.orders:
		var order: Dictionary = book.orders[tier]
		var shown := {"id":order.id,"tier":tier,"state":order.state,"completed":0,
			"total":order.directives.size(),"sealed":0,"directives":[]}
		for directive: Dictionary in order.directives:
			if directive.state == "sealed":
				shown.sealed += 1
				continue
			shown.completed += int(directive.state == "completed")
			shown.directives.append({"id":directive.id,"kind":directive.kind,"text":directive.text,
				"state":directive.state,"requirements":{"skill":directive.skill,"level":directive.level,"equipment":directive.item_name,
				"equipment_levels":Handlers.equipment_levels(GameData.get_item_by_name(directive.item_name)) if directive.kind == "equipment" else {}}})
		if order.state in ["cache_revealed","claimed"]:
			shown["cache"] = order.cache_info.duplicate(true)
		if order.state == "claimed":
			shown["rewards"] = order.rewards.duplicate(true)
		result.orders[tier] = shown
	return result

static func integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum and floor(float(value)) == float(value)

static func text(value: Variant, maximum: int, allow_empty: bool = false) -> bool:
	return value is String and value.length() <= maximum and (allow_empty or not value.is_empty())
