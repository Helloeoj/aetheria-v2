extends RefCounted
## Pure authoritative rules. Callers supply trusted world/action context, never wire data.
const Book := preload("res://scripts/orders/order_book.gd")
const Definitions := preload("res://scripts/orders/orders_definitions.gd")
const Selection := preload("res://scripts/orders/orders_selection.gd")
const Handlers := preload("res://scripts/orders/orders_directives.gd")
var config: Dictionary = {}
var random := RandomNumberGenerator.new()
var errors: Array[String] = []
var _selection_pools: Dictionary = {}

func configure(definitions: Dictionary, rng: RandomNumberGenerator = null) -> Dictionary:
	errors = Definitions.new().validate(definitions)
	config = definitions.duplicate(true) if errors.is_empty() else {}
	_selection_pools.clear()
	if enabled():
		for tier: String in Book.TIERS:
			_selection_pools[tier] = Selection.pools(config,tier)
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
	if tier not in Book.TIERS or not Book.inventory_valid(player):
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
	var opened_item := Book.opened_name(tier)
	var names_after := player.backpack.size()-int(int(player.backpack[item_name]) == 1)+1
	if GameData.get_item_by_name(opened_item).is_empty() or names_after > 4096:
		return _result(false,"capacity","Make room for the opened Order. Your sealed packet is unchanged.")
	var generated := generate(tier,player.entity_id,expected_generation+1)
	if not generated.ok:
		return generated
	if not player.remove_item(item_name,1):
		return _result(false,"inventory","The sealed order is unavailable.")
	InventorySystem.add_to_backpack(player,opened_item,1)
	book.generations[tier] = expected_generation+1
	book.orders[tier] = generated.order
	return _result(true,"opened","The opened Order is in your backpack. Click it to read its instructions.")

func generate(tier: String, owner_id: String, generation: int) -> Dictionary:
	if not enabled() or tier not in config.get("tiers",{}) or owner_id.is_empty() or generation < 1:
		return _result(false,"unconfigured","No validated order content is ready for this tier.")
	var settings: Dictionary = config.tiers[tier]
	var count := random.randi_range(int(settings.min_directives),int(settings.max_directives))
	var cache_ids: Array = []
	var gated_caches: Array = []
	for anchor_id: String in _selection_pools.get(tier,{}):
		var pool: Dictionary = _selection_pools[tier][anchor_id]
		if int(pool.ordinary_count) >= count:
			cache_ids.append(anchor_id)
			if int(pool.gate_count) > 0: gated_caches.append(anchor_id)
	var wants_gate := int(settings.max_gates) > 0 and random.randf() < float(settings.gate_chance)
	var requested_gates := random.randi_range(1,mini(count,int(settings.max_gates))) if wants_gate else 0
	if wants_gate and not gated_caches.is_empty(): cache_ids = gated_caches
	_shuffle(cache_ids)
	for cache_id: String in cache_ids:
		var pool: Dictionary = _selection_pools[tier][cache_id]
		var ordinary: Array = pool.ordinary.duplicate()
		var gates: Array = pool.gates.duplicate()
		var gate_count := mini(requested_gates,int(pool.gate_count))
		var picked: Array = []
		for index in range(gate_count):
			picked.append(_take_directive(gates,String(picked.back().kind) if not picked.is_empty() else ""))
		for index in range(count-gate_count):
			picked.append(_take_directive(ordinary,String(picked.back().kind) if not picked.is_empty() else ""))
		picked = Selection.reveal_order(picked,random)
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
		if directive.state != "available" or not Handlers.is_interaction(directive.kind):
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
	if not Handlers.is_event(kind) or not Book.inventory_valid(player):
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
	var book: Dictionary = player.dead_man_orders
	if int(book.completed[order.tier]) >= Book.MAX_COUNT:
		return _result(false,"capacity","The completion record needs recovery. The cache remains unclaimed.")
	if player.gold > Book.MAX_COUNT-int(rewards.gold):
		return _result(false,"capacity","There is not enough currency capacity. The cache remains unclaimed.")
	var new_names := 0
	var new_collection_ids := 0
	for entry: Dictionary in rewards.items:
		if GameData.get_item_by_name(entry.item_name).is_empty() or not InventorySystem.can_add_to_backpack(player,entry.item_name,int(entry.count)):
			return _result(false,"capacity","Make room for the complete reward. The cache remains unclaimed.")
		new_names += int(not player.backpack.has(entry.item_name))
		var item := GameData.get_item_by_name(entry.item_name)
		if item.get("orders_exclusive",false) == true:
			var item_id := str(int(item.id))
			new_collection_ids += int(not book.collection.has(item_id))
			if int(book.collection.get(item_id,0)) > Book.MAX_COUNT-int(entry.count):
				return _result(false,"capacity","The collection record needs recovery. The cache remains unclaimed.")
	if book.collection.size()+new_collection_ids > 4096:
		return _result(false,"capacity","The collection record needs recovery. The cache remains unclaimed.")
	if player.backpack.size()+new_names-1 > 4096:
		return _result(false,"capacity","Make room for the complete reward. The cache remains unclaimed.")
	for entry: Dictionary in rewards.items:
		InventorySystem.add_to_backpack(player,entry.item_name,int(entry.count))
		var item := GameData.get_item_by_name(entry.item_name)
		if item.get("orders_exclusive",false) == true:
			var item_id := str(int(item.id))
			book.collection[item_id] = int(book.collection.get(item_id,0))+int(entry.count)
	player.gold += int(rewards.gold)
	player.remove_item(Book.opened_name(order.tier),1)
	book.completed[order.tier] = int(book.completed[order.tier])+1
	order.state = "claimed"
	return _result(true,"claimed","The treasure has been claimed.")

func abandon(player: PlayerState, order_id: String) -> Dictionary:
	var order := _owned(player,order_id)
	if order.is_empty() or order.state not in ["active","cache_revealed","suspended"]:
		return _result(false,"order","That order is no longer active.")
	player.remove_item(Book.opened_name(order.tier),1)
	order.state = "abandoned"
	return _result(true,"abandoned","Order abandoned. Its sealed item is not restored.")

func _owned(player: PlayerState, order_id: String) -> Dictionary:
	if not Book.inventory_valid(player):
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
	return Handlers.meets_requirements(player,directive)

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

func _take_directive(pool: Array, previous_kind: String) -> Dictionary:
	var groups := {}
	for row: Dictionary in pool:
		if not groups.has(row.kind): groups[row.kind] = []
		groups[row.kind].append(row)
	var families: Array = []
	for kind: String in groups:
		if groups.size() > 1 and kind == previous_kind: continue
		families.append({"kind":kind,"weight":Selection.family_weight(config,kind)})
	var family := _take_weighted(families)
	var selected := _take_weighted(groups[family.kind])
	var key := Selection.objective_key(selected)
	for index in range(pool.size()-1,-1,-1):
		if Selection.objective_key(pool[index]) == key: pool.remove_at(index)
	return selected

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
