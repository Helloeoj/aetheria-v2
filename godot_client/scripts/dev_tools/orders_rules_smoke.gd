extends Node

var failures := 0
var checks := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("[Orders rules FAIL] ", label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if not ResourceLoader.exists("res://scripts/orders/order_book.gd") or not ResourceLoader.exists("res://scripts/orders/orders_service.gd"):
		check(false, "Orders lifecycle exists before testing generation and claim safety")
		_finish()
		return
	var Book = load("res://scripts/orders/order_book.gd")
	check(Book.validate_book(Book.empty_book()), "An empty order book is valid")
	check(not Book.validate_book({"version":1,"generations":{},"orders":{}}), "Missing tier generations cannot silently reset progress")
	var Definitions = load("res://scripts/orders/orders_definitions.gd").new()
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/dev_tools/fixtures/orders_config.json"))
	var loaded := {"ok":Definitions.validate(config).is_empty(),"config":config}
	check(loaded.ok, "Authored definitions load")
	if not loaded.ok:
		_finish()
		return
	var Service = load("res://scripts/orders/orders_service.gd")
	var service = Service.new()
	var random := RandomNumberGenerator.new()
	random.seed = 5678
	service.configure(loaded.config, random)
	var p := PlayerState.new("Orders test")
	p.entity_id = "order-owner"
	p.add_item("Sealed Deckhand's Order", 3)
	var opened: Dictionary = service.open(p,"deckhand",0)
	check(opened.ok, "Owned sealed order opens")
	check(int(p.backpack.get("Sealed Deckhand's Order",0)) == 2, "Activation consumes exactly one item")
	var original: Dictionary = p.dead_man_orders.duplicate(true)
	check(not service.open(p,"deckhand",0).ok and p.dead_man_orders == original, "Duplicate activation cannot reroll or consume another order")
	var order: Dictionary = p.dead_man_orders.orders.deckhand
	check(Book.validate_book(p.dead_man_orders,p.entity_id), "Generated order is valid private save data")
	var view: Dictionary = Book.public_book(p.dead_man_orders)
	check(not view.orders.deckhand.has("rewards") and not view.orders.deckhand.has("cache"), "Active view hides cache and rewards")
	check(view.orders.deckhand.directives.size() == 2, "Only the two initial directives are revealed")
	var completed := 0
	while order.state == "active" and completed < 8:
		var available: Array = order.directives.filter(func(d: Dictionary) -> bool: return d.state == "available")
		check(not available.is_empty(), "A live order has an available directive")
		if available.is_empty(): break
		var d: Dictionary = available.back()
		var bad := {"region_id":"wrong","anchor_id":d.anchor_id,"in_range":true}
		check(not service.interact(p,order.id,d.id,d.anchor_id,bad,d.answer).ok, "Wrong region cannot complete a directive")
		var context := {"region_id":loaded.config.anchors[d.anchor_id].region_id,"anchor_id":d.anchor_id,"in_range":true}
		check(service.interact(p,order.id,d.id,d.anchor_id,context,d.answer).ok, "Available directives complete in reverse choice order")
		completed += 1
	check(order.state == "cache_revealed", "All directives reveal the cache")
	check(Book.public_book(p.dead_man_orders).orders.deckhand.has("cache"), "Cache appears only after completion")
	var context := {"region_id":loaded.config.anchors[order.cache].region_id,"anchor_id":order.cache,"in_range":true}
	var saved_gold := p.gold
	p.gold = 2147483647
	check(not service.claim(p,order.id,order.cache,context).ok and order.state == "cache_revealed", "Gold overflow leaves a cache unclaimed")
	p.gold = saved_gold
	check(service.claim(p,order.id,order.cache,context).ok, "Owner claims a completed cache")
	var after: Dictionary = p.backpack.duplicate()
	var after_gold := p.gold
	check(not service.claim(p,order.id,order.cache,context).ok and p.backpack == after and p.gold == after_gold, "Repeated claim cannot duplicate rewards")
	check(not service.open(p,"deckhand",0).ok, "A stale activation stays stale after claim")
	check(service.open(p,"deckhand",1).ok, "A new lifecycle generation can open the next order")
	var active_id: String = p.dead_man_orders.orders.deckhand.id
	check(service.abandon(p,active_id).ok, "Abandonment creates a terminal state")
	check(not service.claim(p,active_id,order.cache,context).ok, "Abandoned orders cannot be claimed")
	var changed := original.duplicate(true)
	changed.orders.deckhand.owner = "another-character"
	check(not Book.validate_book(changed,p.entity_id), "A private order belongs to its character")
	_check_actions(Service,config)
	var simulations := 0
	for tier: String in ["deckhand","smuggler","corsair","dread_captain"]:
		for index in range(10000):
			var generated: Dictionary = service.generate(tier,p.entity_id,index+1)
			if not generated.ok:
				check(false, "Generation always finds a valid supported order: " + tier)
				break
			var sample: Dictionary = generated.order
			var settings: Dictionary = loaded.config.tiers[tier]
			if sample.directives.size() < int(settings.min_directives) or sample.directives.size() > int(settings.max_directives):
				check(false,"Generated directive counts follow tier limits")
				break
			var exact := {}
			for directive: Dictionary in sample.directives:
				var key: String = directive.template_id+":"+directive.anchor_id
				if exact.has(key) or directive.anchor_id == sample.cache:
					check(false,"No duplicate directive/anchor or final cache target")
					break
				exact[key] = true
			simulations += 1
	check(simulations == 40000,"40,000 randomized orders generated across all tiers")
	_finish()

func _check_actions(Service: Script, config: Dictionary) -> void:
	var action_config := config.duplicate(true)
	action_config.tiers.smuggler.gate_chance = 1.0
	action_config.tiers.smuggler.max_gates = 1
	var service = Service.new()
	check(service.configure(action_config).ok,"Action-gated fixture validates")
	var p := PlayerState.new("Action owner")
	p.entity_id = "action-owner"
	p.add_item("Sealed Smuggler's Order")
	check(service.open(p,"smuggler",0).ok,"An aspirational gated order opens below its skill requirement")
	var order: Dictionary = p.dead_man_orders.orders.smuggler
	var gate: Dictionary = {}
	for directive: Dictionary in order.directives:
		if int(directive.level) > 0:
			gate = directive
	check(not gate.is_empty(),"The configured order-level gate is included")
	if gate.is_empty(): return
	var context := {"anchor_id":gate.anchor_id,"region_id":config.anchors[gate.anchor_id].region_id,"in_range":true}
	check(not service.on_event(p,gate.kind,gate.target_id,context),"Sealed or under-level actions cannot complete a gate")
	while gate.state == "sealed":
		for directive: Dictionary in order.directives:
			if directive.state == "available" and int(directive.level) == 0:
				var interaction := {"anchor_id":directive.anchor_id,"region_id":config.anchors[directive.anchor_id].region_id,"in_range":true}
				service.interact(p,order.id,directive.id,directive.anchor_id,interaction,directive.answer)
				break
	check(not service.on_event(p,gate.kind,gate.target_id,context),"An available action still checks its real skill level")
	p.set_skill_level(gate.skill,100)
	var experience := p.get_skill_experience(gate.skill)
	check(not service.on_event(p,gate.kind,"wrong-target",context),"A different successful action does not satisfy the directive")
	check(service.on_event(p,gate.kind,gate.target_id,context) and gate.state == "completed","A validated successful action completes a gate at the XP cap")
	check(p.get_skill_experience(gate.skill) == experience,"Order progress does not invent skill XP")
	check(not service.on_event(p,gate.kind,gate.target_id,context),"A completed single gate cannot be replayed")

func _finish() -> void:
	print("[Orders rules] %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
