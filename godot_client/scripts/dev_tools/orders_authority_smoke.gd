extends Node
var checks := 0
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("[Orders authority FAIL] ",label)

func _run() -> void:
	var Region = load("res://network/authoritative_region.gd")
	var region = Region.new()
	region.configure("outskirts",null)
	check(region.get("orders") != null,"Authoritative region owns the Orders service")
	if region.get("orders") == null:
		_finish()
		return
	var alice := PlayerState.new("Alice")
	alice.entity_id = "orders-alice"
	var bob := PlayerState.new("Bob")
	bob.entity_id = "orders-bob"
	region.add_player(alice.entity_id,alice)
	region.add_player(bob.entity_id,bob)
	alice.add_item("Sealed Deckhand's Order",2)
	check(not region.submit(alice.entity_id,{"type":"order_open","tier":"deckhand","generation":0}).ok,"Unconfigured live framework does not consume sealed items")
	check(alice.backpack.get("Sealed Deckhand's Order") == 2,"Disabled activation leaves inventory intact")
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/dev_tools/fixtures/orders_config.json"))
	check(region.orders.configure(config).ok,"A validated fixture can enable the integration in tests")
	check(not region.submit(alice.entity_id,{"type":"order_open","tier":"deckhand","generation":0,"reward":999}).ok,"Wire schema rejects client reward injection")
	check(not region.submit(alice.entity_id,{"type":"order_open","tier":"deckhand","generation":0.5}).ok,"Activation generations must be whole integers")
	check(region.submit(alice.entity_id,{"type":"order_open","tier":"deckhand","generation":0}).ok,"Server opens an owned configured order")
	check(not region.submit(alice.entity_id,{"type":"order_open","tier":"deckhand","generation":0}).ok,"Server rejects replayed activation")
	var order: Dictionary = alice.dead_man_orders.orders.deckhand
	check(not region.submit(bob.entity_id,{"type":"order_abandon","order_id":order.id}).ok,"Another character cannot abandon this order")
	var directive: Dictionary = order.directives[0]
	check(not region.submit(alice.entity_id,{"type":"order_interact","order_id":order.id,"directive_id":directive.id,"anchor_id":directive.anchor_id}).ok,"A missing world target cannot be completed by a wire claim")
	check(directive.state == "available","Failed interaction leaves progress intact")
	region.frozen[alice.entity_id] = true
	check(not region.submit(alice.entity_id,{"type":"order_abandon","order_id":order.id}).ok,"Persistence-paused characters cannot mutate orders")
	region.frozen.erase(alice.entity_id)
	check(region.submit(alice.entity_id,{"type":"order_abandon","order_id":order.id}).ok,"Owner can abandon through server command")
	check(order.state == "abandoned" and alice.backpack.get("Sealed Deckhand's Order") == 1,"Abandonment never refunds or rerolls a sealed order")
	var codec = load("res://network/character_codec.gd")
	var saved: Dictionary = codec.encode(alice,"outskirts")
	var restored: Dictionary = codec.decode(JSON.parse_string(JSON.stringify(saved)),alice.name,alice.entity_id)
	if not restored.ok:
		printerr("Orders restore code: ",restored.get("code",""))
	check(restored.ok and restored.player.dead_man_orders.orders.deckhand.id == order.id and restored.player.dead_man_orders.orders.deckhand.state == "abandoned" and int(restored.player.dead_man_orders.generations.deckhand) == 1,"Order identity/progress survives a save and JSON boundary")
	check(not region.submit(alice.entity_id,{"type":"order_claim","order_id":order.id,"anchor_id":order.cache}).ok,"Terminal abandoned state cannot claim a cache")
	var corrupt: Dictionary = alice.dead_man_orders.duplicate(true)
	corrupt.orders.deckhand.erase("generation")
	check(not load("res://scripts/orders/order_book.gd").validate_book(corrupt,alice.entity_id),"Malformed order generations fail closed without script errors")
	region.remove_player(alice.entity_id)
	region.remove_player(bob.entity_id)
	_finish()

func _finish() -> void:
	print("[Orders authority] %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
