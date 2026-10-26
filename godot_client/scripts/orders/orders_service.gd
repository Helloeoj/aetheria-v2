extends RefCounted
## Pure authoritative rules. Callers supply trusted world/action context, never wire data.
const Book := preload("res://scripts/orders/order_book.gd")
const Definitions := preload("res://scripts/orders/orders_definitions.gd")
var config: Dictionary = {}
var random := RandomNumberGenerator.new()
var errors: Array[String] = []

func configure(definitions: Dictionary, rng: RandomNumberGenerator = null) -> Dictionary:
	errors = Definitions.new().validate(definitions)
	config = definitions.duplicate(true) if errors.is_empty() else {}
	if rng != null:
		random = rng
	else:
		random.randomize()
	return {"ok":errors.is_empty(),"errors":errors.duplicate()}

func enabled() -> bool:
	return bool(config.get("enabled",false)) and errors.is_empty()

func open(player: PlayerState, tier: String, expected_generation: int) -> Dictionary:
	if not enabled():
		return _result(false,"unconfigured","Dead Man's Orders await configured directives, locations and rewards.")
	if tier not in Book.TIERS or not Book.validate_book(player.dead_man_orders,player.entity_id):
		return _result(false,"invalid","The order or saved progress is unavailable.")
	var book: Dictionary = player.dead_man_orders
	if int(book.generations[tier]) != expected_generation or expected_generation >= Book.MAX_COUNT:
		return _result(false,"stale","This order action has already changed. Refresh the ledger.")
	var current: Dictionary = book.orders.get(tier,{})
	if not current.is_empty() and current.state not in ["claimed","abandoned"]:
		return _result(false,"active","Finish or abandon the active order of this tier first.")
	var item_name: String = config.tiers[tier].item_name
	if int(player.backpack.get(item_name,0)) <= 0:
		return _result(false,"inventory","You need an owned sealed order.")
	var generated := generate(tier,player.entity_id,expected_generation+1)
	if not generated.ok:
		return generated
	if not player.remove_item(item_name,1):
		return _result(false,"inventory","The sealed order is unavailable.")
	book.generations[tier] = expected_generation+1
	book.orders[tier] = generated.order
	return _result(true,"opened","The order is recorded in your Captain's Ledger.")

func generate(tier: String, owner_id: String, generation: int) -> Dictionary:
	if not enabled() or tier not in config.get("tiers",{}) or owner_id.is_empty() or generation < 1:
		return _result(false,"unconfigured","No validated order content is ready for this tier.")
	var settings: Dictionary = config.tiers[tier]
	var count := random.randi_range(int(settings.min_directives),int(settings.max_directives))
	var cache_ids: Array = []
	for anchor_id: String in config.anchors:
		if tier in config.anchors[anchor_id].tiers:
			cache_ids.append(anchor_id)
	_shuffle(cache_ids)
	var wants_gate := int(settings.max_gates) > 0 and random.randf() < float(settings.gate_chance)
	var gate_count := random.randi_range(1,mini(count,int(settings.max_gates))) if wants_gate else 0
	for cache_id: String in cache_ids:
		var ordinary: Array = []
		var gates: Array = []
		for template: Dictionary in config.templates:
			if tier not in template.tiers or template.anchor_id == cache_id or not bool(template.get("enabled",true)):
				continue
			if template.kind == "equipment" or int(template.get("level",0)) > 0:
				gates.append(template)
			else:
				ordinary.append(template)
		if gates.size() < gate_count or ordinary.size() < count-gate_count:
			continue
		var picked: Array = []
		for index in range(gate_count):
			picked.append(_take_weighted(gates))
		for index in range(count-gate_count):
			picked.append(_take_weighted(ordinary))
		_shuffle(picked)
		var directives: Array = []
		for index in range(picked.size()):
			var row: Dictionary = picked[index]
			directives.append({"id":_id(),"template_id":row.id,"kind":row.kind,"anchor_id":row.anchor_id,
				"target_id":String(row.get("target_id","")),"skill":String(row.get("skill","")),
				"level":int(row.get("level",0)),"item_name":String(row.get("item_name","")),
				"text":row.text,"answer":String(row.get("answer","")),
				"state":"available" if index < int(settings.slots) else "sealed"})
		var cache: Dictionary = config.anchors[cache_id]
		var order := {"id":_id(),"owner":owner_id,"tier":tier,"generation":generation,
			"config_version":int(config.version),"state":"active","slots":int(settings.slots),
			"directives":directives,"cache":cache_id,
			"cache_info":{"label":cache.label,"region_id":cache.region_id,"hint":cache.hint},
			"rewards":_roll_rewards(settings)}
		var candidate := Book.empty_book()
		candidate.generations[tier] = generation
		candidate.orders[tier] = order
		if Book.validate_book(candidate,owner_id):
			return {"ok":true,"order":order}
	return _result(false,"content","The configured templates cannot form a valid order. Your sealed item is unchanged.")

func interact(player: PlayerState, order_id: String, directive_id: String, anchor_id: String, context: Dictionary, answer: String = "") -> Dictionary:
	var order := _owned(player,order_id)
	if order.is_empty() or order.state != "active":
		return _result(false,"order","That order is not active.")
	for directive: Dictionary in order.directives:
		if directive.id != directive_id:
			continue
		if directive.state != "available" or directive.kind not in ["riddle","search","cipher","equipment"]:
			return _result(false,"directive","That directive is not available for this interaction.")
		if directive.anchor_id != anchor_id or not _context_valid(anchor_id,context) or not _requirements(player,directive):
			return _result(false,"requirements","Check the location, distance and directive requirements.")
		if directive.kind == "cipher" and answer.strip_edges().to_lower() != String(directive.answer).strip_edges().to_lower():
			return _result(false,"answer","The decoded answer does not match.")
		_complete(order,directive)
		return _result(true,"completed","Directive completed.")
	return _result(false,"directive","That directive does not belong to this order.")

func on_event(player: PlayerState, kind: String, target_id: String, context: Dictionary) -> bool:
	# Capture one match only: newly revealed directives cannot consume this event again.
	if not Book.validate_book(player.dead_man_orders,player.entity_id):
		return false
	for tier: String in Book.TIERS:
		var order: Dictionary = player.dead_man_orders.orders.get(tier,{})
		if order.is_empty() or order.state != "active":
			continue
		for directive: Dictionary in order.directives:
			if directive.state != "available" or directive.kind != kind or directive.target_id != target_id:
				continue
			if not _context_valid(directive.anchor_id,context) or not _requirements(player,directive):
				continue
			_complete(order,directive)
			return true
	return false

func claim(player: PlayerState, order_id: String, anchor_id: String, context: Dictionary) -> Dictionary:
	var order := _owned(player,order_id)
	if order.is_empty() or order.state != "cache_revealed" or order.cache != anchor_id or not _context_valid(anchor_id,context):
		return _result(false,"cache","This cache is not ready or you are not at its location.")
	var rewards: Dictionary = order.rewards
	if player.gold > Book.MAX_COUNT-int(rewards.gold):
		return _result(false,"capacity","There is not enough currency capacity. The cache remains unclaimed.")
	var new_names := 0
	for entry: Dictionary in rewards.items:
		if GameData.get_item_by_name(entry.item_name).is_empty() or not InventorySystem.can_add_to_backpack(player,entry.item_name,int(entry.count)):
			return _result(false,"capacity","Make room for the complete reward. The cache remains unclaimed.")
		new_names += int(not player.backpack.has(entry.item_name))
	if player.backpack.size()+new_names > 4096:
		return _result(false,"capacity","Make room for the complete reward. The cache remains unclaimed.")
	for entry: Dictionary in rewards.items:
		InventorySystem.add_to_backpack(player,entry.item_name,int(entry.count))
	player.gold += int(rewards.gold)
	order.state = "claimed"
	return _result(true,"claimed","The treasure has been claimed.")

func abandon(player: PlayerState, order_id: String) -> Dictionary:
	var order := _owned(player,order_id)
	if order.is_empty() or order.state not in ["active","cache_revealed","suspended"]:
		return _result(false,"order","That order is no longer active.")
	order.state = "abandoned"
	return _result(true,"abandoned","Order abandoned. Its sealed item is not restored.")

func _owned(player: PlayerState, order_id: String) -> Dictionary:
	if not Book.validate_book(player.dead_man_orders,player.entity_id):
		return {}
	for order: Dictionary in player.dead_man_orders.orders.values():
		if order.id == order_id and order.owner == player.entity_id:
			return order
	return {}

func _context_valid(anchor_id: String, context: Dictionary) -> bool:
	if not enabled() or not config.anchors.has(anchor_id):
		return false
	return context.get("in_range") == true and context.get("anchor_id") == anchor_id and context.get("region_id") == config.anchors[anchor_id].region_id

func _requirements(player: PlayerState, directive: Dictionary) -> bool:
	if not String(directive.skill).is_empty() and player.get_skill_level(directive.skill) < int(directive.level):
		return false
	if directive.kind == "equipment":
		var item := GameData.get_item_by_name(directive.item_name)
		if item.is_empty() or EquipmentProgression.requirements(item).is_empty() or not EquipmentProgression.can_equip(player,item):
			return false
		for worn: Dictionary in player.equipment.values():
			if worn.get("id") == item.get("id"):
				return true
		return false
	return true

func _complete(order: Dictionary, directive: Dictionary) -> void:
	directive.state = "completed"
	var available := 0
	var completed := 0
	for row: Dictionary in order.directives:
		available += int(row.state == "available")
		completed += int(row.state == "completed")
	for row: Dictionary in order.directives:
		if available >= int(order.slots):
			break
		if row.state == "sealed":
			row.state = "available"
			available += 1
	if completed == order.directives.size():
		order.state = "cache_revealed"

func _roll_rewards(tier: Dictionary) -> Dictionary:
	var items := {}
	for index in range(int(tier.reward_rolls)):
		var pool: Array = config.base_rewards.duplicate()
		var selected := _take_weighted(pool)
		var count := random.randi_range(int(selected.min),int(selected.max))
		items[selected.item_name] = int(items.get(selected.item_name,0))+count
	var entries: Array = []
	for name: String in items:
		entries.append({"item_name":name,"count":int(items[name])})
	return {"gold":random.randi_range(int(tier.gold_min),int(tier.gold_max)),"items":entries}

func _take_weighted(pool: Array) -> Dictionary:
	var total := 0.0
	for row: Dictionary in pool:
		total += float(row.get("weight",1.0))
	var choice := random.randf()*total
	for index in range(pool.size()):
		choice -= float(pool[index].get("weight",1.0))
		if choice <= 0.0 or index == pool.size()-1:
			var result: Dictionary = pool[index]
			pool.remove_at(index)
			return result
	return {}

func _shuffle(values: Array) -> void:
	for index in range(values.size()-1,0,-1):
		var other := random.randi_range(0,index)
		var previous: Variant = values[index]
		values[index] = values[other]
		values[other] = previous

func _id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

func _result(ok: bool, code: String = "ok", message: String = "") -> Dictionary:
	return {"ok":ok,"code":code,"message":message}
