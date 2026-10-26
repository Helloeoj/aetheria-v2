extends Node
## Real inventory, lifecycle and save boundaries; no live account or world content.
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("[Orders inventory FAIL] ", label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var Book = load("res://scripts/orders/order_book.gd")
	var Service = load("res://scripts/orders/orders_service.gd")
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/dev_tools/fixtures/orders_config.json"))
	config.base_rewards = [{"item_name":"Feathers","min":2,"max":2,"weight":1}]
	config.tiers.deckhand.reward_rolls = 1
	var service = Service.new()
	check(service.configure(config).ok, "Existing authored fixture remains valid")
	var p := PlayerState.new("Physical Orders")
	p.entity_id = "physical-owner"
	p.add_item("Sealed Deckhand's Order", 3)
	var slots := InventorySystem.inventory_slots(p)
	check(slots.size() == 3 and slots[0].quantity == 1, "Sealed copies occupy separate individual inventory slots")
	check(not InventorySystem.is_stackable("Sealed Dread Captain's Order"), "All four sealed tiers are nonstacking")
	check(not GameData.get_item_by_name("Deckhand's Order").is_empty(), "Opened Orders have physical catalog definitions")
	if GameData.get_item_by_name("Deckhand's Order").is_empty():
		_finish()
		return
	check(service.open(p,"deckhand",0).ok, "Opening transforms an owned packet")
	var order: Dictionary = p.dead_man_orders.orders.deckhand
	var order_id: String = order.id
	check(p.backpack.get("Deckhand's Order") == 1 and p.backpack.get("Sealed Deckhand's Order") == 2, "One sealed packet becomes one carried opened Order")
	check(InventorySystem.inventory_slots(p).size() == 3, "Opening preserves physical inventory slot use")
	var carried: Array = InventorySystem.inventory_slots(p).filter(func(s: Dictionary) -> bool: return s.name == "Deckhand's Order")
	check(carried.size() == 1 and carried[0].get("order_id") == order_id, "Opened inventory slot identifies its persistent instance")
	var saved := CharacterCodec.encode(p,"outskirts")
	var restored := CharacterCodec.decode(JSON.parse_string(JSON.stringify(saved)),p.name,p.entity_id)
	check(restored.ok and restored.player.backpack.get("Deckhand's Order") == 1 and restored.player.dead_man_orders.orders.deckhand.id == order_id, "Opened physical item and tasks survive reconnect without reroll")
	var projected := CharacterCodec.decode_public(CharacterCodec.public_state(saved),p.name,p.entity_id)
	check(projected.ok and projected.player.backpack.get("Deckhand's Order") == 1, "Acknowledged public inventory loads without receiving private task data")
	if projected.ok:
		var visible: Array = InventorySystem.inventory_slots(projected.player).filter(func(s: Dictionary) -> bool: return s.name == "Deckhand's Order")
		check(visible.size() == 1 and visible[0].get("order_id") == order_id, "Online inventory slots retain the acknowledged instance identity")
	var missing := saved.duplicate(true)
	missing.inventory = missing.inventory.filter(func(row: Dictionary) -> bool: return int(row.item_id) != 9005)
	check(not CharacterCodec.decode(missing,p.name,p.entity_id).ok, "Current saves cannot silently recreate a missing physical Order")
	var duplicate := saved.duplicate(true)
	for row: Dictionary in duplicate.inventory:
		if int(row.item_id) == 9005:
			row.count = 2
	check(not CharacterCodec.decode(duplicate,p.name,p.entity_id).ok, "Current saves reject duplicate opened copies for a single instance")
	var legacy := missing.duplicate(true)
	legacy.version = 3
	legacy.dead_man_orders.version = 1
	legacy.dead_man_orders.erase("collection")
	legacy.dead_man_orders.erase("completed")
	var migrated := CharacterCodec.decode(legacy,p.name,p.entity_id)
	check(migrated.ok and migrated.player.backpack.get("Deckhand's Order") == 1 and migrated.player.dead_man_orders.orders.deckhand.id == order_id, "Legacy framework progress migrates once into a physical Order")
	if migrated.ok:
		var again := CharacterCodec.decode(CharacterCodec.encode(migrated.player,"outskirts"),p.name,p.entity_id)
		check(again.ok and again.player.backpack.get("Deckhand's Order") == 1, "Reloading a migrated save never adds another copy")
	var foreign := legacy.duplicate(true)
	foreign.dead_man_orders.orders.deckhand.owner = "someone-else"
	check(not CharacterCodec.decode(foreign,p.name,p.entity_id).ok, "Migration never restores another character's Order")
	p.backpack.erase("Deckhand's Order")
	var d: Dictionary = order.directives[0]
	var context := {"anchor_id":d.anchor_id,"region_id":config.anchors[d.anchor_id].region_id,"in_range":true}
	check(not service.interact(p,order.id,d.id,d.anchor_id,context,d.answer).ok, "A journal entry without its carried Order cannot progress")
	check(CharacterCodec.encode(p,"outskirts").is_empty(), "Missing physical ownership fails authoritative persistence")
	p.add_item("Deckhand's Order")
	var region = load("res://network/authoritative_region.gd").new()
	region.configure("outskirts",null)
	region.add_player(p.entity_id,p)
	check(not region.submit(p.entity_id,{"type":"drop","item_name":"Deckhand's Order","quantity":1}).ok and p.backpack.get("Deckhand's Order") == 1, "Forged online drop cannot transfer an opened Order")
	region.remove_player(p.entity_id)
	# Retain real catalog identity; this test-only flag isolates the exclusive-claim boundary.
	var feathers: Dictionary = GameData.get_item_by_name("Feathers")
	var had_flag := feathers.has("orders_exclusive")
	var old_flag: Variant = feathers.get("orders_exclusive")
	feathers.orders_exclusive = true
	p.add_item("Feathers",4)
	check(p.dead_man_orders.collection.is_empty(), "Ordinary inventory gains never fill the Orders collection log")
	_complete(service,p,order,config)
	context = {"anchor_id":order.cache,"region_id":config.anchors[order.cache].region_id,"in_range":true}
	var before := p.backpack.duplicate()
	p.gold = 2147483647
	check(not service.claim(p,order.id,order.cache,context).ok and p.backpack == before and p.dead_man_orders.collection.is_empty(), "Failed reward preflight preserves item and collection log")
	p.gold = 0
	check(service.claim(p,order.id,order.cache,context).ok, "Owner can claim with the physical Order present")
	check(not p.backpack.has("Deckhand's Order") and p.dead_man_orders.completed.deckhand == 1, "Claim consumes the physical item and increments the tier completion total")
	var item_id := str(int(feathers.id))
	check(p.dead_man_orders.collection.get(item_id) == 2, "Exclusive log counts only the two directly claimed rewards")
	check(not service.claim(p,order.id,order.cache,context).ok and p.dead_man_orders.collection.get(item_id) == 2 and p.dead_man_orders.completed.deckhand == 1, "Duplicate claim cannot increment collection or completion counts")
	var earned := CharacterCodec.decode(JSON.parse_string(JSON.stringify(CharacterCodec.encode(p,"outskirts"))),p.name,p.entity_id)
	check(earned.ok and earned.player.dead_man_orders.collection.get(item_id) == 2 and earned.player.dead_man_orders.completed.deckhand == 1, "Collection and tier completion totals persist across reconnect")
	if had_flag:
		feathers.orders_exclusive = old_flag
	else:
		feathers.erase("orders_exclusive")
	check(service.open(p,"deckhand",1).ok, "Next packet gets a fresh instance after claim")
	check(p.dead_man_orders.orders.deckhand.id != order_id, "A newly opened packet has its own identity")
	check(service.abandon(p,p.dead_man_orders.orders.deckhand.id).ok and not p.backpack.has("Deckhand's Order"), "Confirmed abandonment removes its physical Order")
	check(p.dead_man_orders.completed.deckhand == 1 and p.dead_man_orders.collection.get(item_id) == 2, "Abandonment preserves historical earned collection counts")
	check(service.open(p,"deckhand",2).ok,"Another ordinary reward hunt opens")
	order = p.dead_man_orders.orders.deckhand
	_complete(service,p,order,config)
	context = {"anchor_id":order.cache,"region_id":config.anchors[order.cache].region_id,"in_range":true}
	check(service.claim(p,order.id,order.cache,context).ok and p.dead_man_orders.collection.get(item_id) == 2,"Nonexclusive cache supplies do not advance the exclusive collection log")
	p.add_item("Sealed Deckhand's Order")
	service.open(p,"deckhand",3)
	order = p.dead_man_orders.orders.deckhand
	_complete(service,p,order,config)
	var shafts := GameData.get_item_by_name("Arrow Shafts")
	feathers.orders_exclusive = true
	shafts.orders_exclusive = true
	order.rewards.items = [{"item_name":"Feathers","count":1},{"item_name":"Arrow Shafts","count":1}]
	p.dead_man_orders.collection.clear()
	for index in range(4095):
		p.dead_man_orders.collection[str(100000+index)] = 1
	context = {"anchor_id":order.cache,"region_id":config.anchors[order.cache].region_id,"in_range":true}
	before = p.backpack.duplicate()
	check(not service.claim(p,order.id,order.cache,context).ok and p.dead_man_orders.collection.size() == 4095 and p.backpack == before,"Combined new collection entries are preflighted before any reward is delivered")
	feathers.erase("orders_exclusive")
	shafts.erase("orders_exclusive")
	var invalid_book: Dictionary = p.dead_man_orders.duplicate(true)
	invalid_book.collection[item_id] = -1
	check(not Book.validate_book(invalid_book,p.entity_id), "Malformed collection counts fail closed")
	_finish()

func _complete(service: RefCounted, p: PlayerState, order: Dictionary, config: Dictionary) -> void:
	while order.state == "active":
		var d: Dictionary = order.directives.filter(func(row: Dictionary) -> bool: return row.state == "available")[0]
		var context := {"anchor_id":d.anchor_id,"region_id":config.anchors[d.anchor_id].region_id,"in_range":true}
		var result: Dictionary = service.interact(p,order.id,d.id,d.anchor_id,context,d.answer)
		if not result.ok:
			check(false,"Fixture directive completes through the real service")
			break

func _finish() -> void:
	print("[Orders inventory] %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
