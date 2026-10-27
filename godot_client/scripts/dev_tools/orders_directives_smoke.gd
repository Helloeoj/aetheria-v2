extends Node
const Book := preload("res://scripts/orders/order_book.gd")
const Service := preload("res://scripts/orders/orders_service.gd")
const Definitions := preload("res://scripts/orders/orders_definitions.gd")
class Geometry extends Node2D:
	var map_origin := Vector2.ZERO
	var map_height := 640
	var world := WorldState.new()
var checks := 0
var failures := 0
var config: Dictionary

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("[Orders directives FAIL] ",label)

func _run() -> void:
	config = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/dev_tools/fixtures/orders_config.json"))
	var service := Service.new()
	check(service.configure(config).ok,"Original authored fixture remains valid")
	var p := PlayerState.new("Directive owner")
	p.entity_id = "directive-owner"
	p.add_item("Sealed Deckhand's Order")
	service.open(p,"deckhand",0)
	var order: Dictionary = p.dead_man_orders.orders.deckhand
	var first: Dictionary = order.directives[0]
	first.kind = "cipher"
	first.answer = "fixture answer"
	var context := {"anchor_id":first.anchor_id,"region_id":config.anchors[first.anchor_id].region_id,"in_range":true}
	check(not service.on_event(p,"cipher",first.target_id,context) and first.state == "available","Generic action events cannot bypass a cipher's actual interaction and answer")
	check(not service.interact(p,order.id,first.id,first.anchor_id,context,"wrong").ok,"Wrong cipher answer cannot complete it")
	check(service.interact(p,order.id,first.id,first.anchor_id,context,"  FIXTURE ANSWER  ").ok,"Authored cipher answer uses the existing normalized comparison")
	check(ResourceLoader.exists("res://scripts/orders/orders_directives.gd"),"Shared reusable directive handlers exist")
	if not ResourceLoader.exists("res://scripts/orders/orders_directives.gd"):
		_finish()
		return
	var Handlers = load("res://scripts/orders/orders_directives.gd")
	check(Handlers.is_event("mining") and Handlers.is_event("crafting") and Handlers.is_event("combat"),"Implemented native actions have trusted-event handlers")
	check(not Handlers.is_event("equipment") and not Handlers.is_interaction("contact") and not Handlers.is_event("cursed"),"Interaction and unavailable handlers cannot be reached as arbitrary action completions")
	_equipment(service,p)
	_definitions(Handlers)
	_native_actions()
	_finish()

func _equipment(service: RefCounted, p: PlayerState) -> void:
	p.add_item("Sealed Smuggler's Order")
	service.open(p,"smuggler",0)
	var order: Dictionary = p.dead_man_orders.orders.smuggler
	var d: Dictionary = order.directives[0]
	d.kind = "equipment"
	d.skill = ""
	d.level = 0
	d.item_name = "Steel Dagger"
	var context := {"anchor_id":d.anchor_id,"region_id":config.anchors[d.anchor_id].region_id,"in_range":true}
	p.add_item("Steel Dagger")
	check(not service.interact(p,order.id,d.id,d.anchor_id,context).ok,"Carried equipment does not count as worn")
	p.set_skill_level("attack",20)
	p.equipment.head = GameData.get_item_by_name("Steel Dagger")
	check(not service.interact(p,order.id,d.id,d.anchor_id,context).ok,"Correct item in an incorrect equipment slot cannot satisfy the task")
	p.equipment.head = {}
	p.equipment.weapon = GameData.get_item_by_name("Bronze Dagger")
	d.item_name = "Bronze Dagger"
	check(not service.interact(p,order.id,d.id,d.anchor_id,context).ok,"Zero-level equipment cannot masquerade as a progression gate")
	d.item_name = "Steel Dagger"
	p.equipment.weapon = GameData.get_item_by_name("Steel Dagger")
	p.set_skill_level("attack",1)
	check(not service.interact(p,order.id,d.id,d.anchor_id,context).ok,"Current real equip restrictions are checked at interaction time")
	p.set_skill_level("attack",20)
	var public_order: Dictionary = Book.public_book(p.dead_man_orders).orders.smuggler
	check(public_order.directives[0].requirements.get("equipment_levels",{}).get("attack") == 20,"Public instructions show the actual existing equipment requirement")
	check(service.interact(p,order.id,d.id,d.anchor_id,context).ok,"Correct eligible item worn in its real slot completes the equipment directive")

func _definitions(Handlers: Script) -> void:
	var row := {"id":"fixture_equipment","kind":"equipment","tiers":["smuggler"],"anchor_id":"outskirts_tavern","item_name":"Steel Dagger","text":"Fixture equipment instruction.","weight":1}
	var enabled := config.duplicate(true)
	enabled.templates.append(row)
	check(Definitions.new().validate(enabled).is_empty(),"A real obtainable level-restricted equipment binding can validate in test content")
	enabled.templates[-1].item_name = "Bronze Dagger"
	check(not Definitions.new().validate(enabled).is_empty(),"Enabled zero-level equipment templates fail validation")
	enabled = config.duplicate(true)
	row = row.duplicate(true)
	row.item_name = "Steel Dagger"
	row.tiers = ["deckhand"]
	enabled.templates.append(row)
	check(not Definitions.new().validate(enabled).is_empty(),"Equipment gates are never generated for Deckhand")
	for kind: String in ["equipment","mining"]:
		var malformed := {"kind":kind,"tiers":["smuggler"],"item_name":"Steel Dagger","level":{}}
		check(not Handlers.validate_template(malformed,{},config.tiers).is_empty(),"Malformed "+kind+" requirement types fail without script errors")
	var fight := {"id":"fixture_fight","kind":"combat","tiers":["smuggler"],"anchor_id":"outskirts_tavern","target_id":"Goblin Scout","text":"Fixture combat instruction.","weight":1}
	enabled = config.duplicate(true)
	enabled.templates.append(fight)
	check(not Definitions.new().validate(enabled).is_empty(),"Combat cannot target an undeclared enemy at an anchor")
	enabled.anchors.outskirts_tavern.combat_targets = ["Goblin Scout"]
	check(Definitions.new().validate(enabled).is_empty(),"An explicit existing ordinary monster binding can validate in test content")
	enabled.templates[-1].target_id = "Golem Titan"
	enabled.anchors.outskirts_tavern.combat_targets = ["Golem Titan"]
	check(not Definitions.new().validate(enabled).is_empty(),"Cursed/guardian support cannot be bypassed through ordinary boss bindings")
	var mining := {"id":"fixture_mine","kind":"mining","tiers":["smuggler"],"skill":"mining","level":20,"target_id":"Bronze Ore","item_name":"Bronze Ore"}
	check(not Handlers.validate_template(mining,{"interaction_kind":"mine"},config.tiers).is_empty(),"Production Mining's missing approved pickaxe is kept as a real prerequisite")
	var craft := {"id":"fixture_craft","kind":"crafting","tiers":["smuggler"],"target_id":"tan_starter_hide","item_name":"Tanned Leather"}
	check(Handlers.validate_template(craft,{"interaction_kind":"craft","station":"leatherworking"},config.tiers).is_empty(),"A real enabled recipe and correct station need no fabricated crafting skill")
	check(not Handlers.validate_template(craft,{"interaction_kind":"craft","station":"furnace"},config.tiers).is_empty(),"The same recipe at an unrelated station is not a valid directive")
	craft.skill = "cooking"
	craft.level = 20
	check(not Handlers.validate_template(craft,{"interaction_kind":"craft","station":"leatherworking"},config.tiers).is_empty(),"Crafting cannot borrow an unrelated skill's level requirement")
	for kind: String in ["contact","cursed"]:
		check(not Handlers.validate_template({"kind":kind},{},config.tiers).is_empty(),"Unavailable "+kind+" content remains explicitly disabled")

func _native_actions() -> void:
	var geometry := Geometry.new()
	geometry.name = "FixtureGame"
	add_child(geometry)
	var rock := MiningDeposit.new()
	rock.name = "Ore"
	rock.deposit_id = "orders_fixture_ore"
	rock.position = Vector2(320,320)
	geometry.add_child(rock)
	var bench := CraftingStation.new()
	bench.name = "Bench"
	bench.setup("leatherworking","Fixture bench",Vector2(10,10))
	geometry.add_child(bench)
	var marker := CavePortal.new()
	marker.name = "Marker"
	marker.position = Vector2(320,320)
	marker.approach_offset = Vector2.ZERO
	geometry.add_child(marker)
	var region := AuthoritativeRegion.new()
	region.configure("outskirts",geometry)
	check(region.orders.configure(config).ok,"Native bridge fixture uses the real configured Orders service")
	for id: String in ["action-alice","action-bob"]:
		var player := PlayerState.new(id)
		region.add_player(id,player)
		player.x = 10
		player.y = 10
		region.world.combat.actors[id].x = 10
		region.world.combat.actors[id].y = 10
	var p: PlayerState = region.players["action-alice"]
	# Synthetic state binds existing handlers to real native nodes in this test scene.
	# No normal map, production config, item, recipe or tool definition is changed.
	var anchor: Dictionary = region.orders.config.anchors.outskirts_tavern
	anchor.node_path = "FixtureGame/Ore"
	anchor.interaction_kind = "mine"
	var tool_fixture := preload("res://scripts/dev_tools/mining_tool_fixture.gd").new()
	var mining_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mining.json"))
	mining_data.ores[0].success.p_at_unlock = 1.0
	mining_data.ores[0].success.p_at_mastery = 1.0
	tool_fixture.load_records(mining_data)
	region.mining._defs = tool_fixture
	p.set_skill_level("mining",100)
	var order := _seed(region,p,"mining","Bronze Ore","Bronze Ore","mining",20)
	var xp := p.get_skill_experience("mining")
	check(region.submit(p.entity_id,{"type":"mine_start","deposit_id":rock.deposit_id,"deposit_generation":0}).ok,"Real Mining session starts with the existing tool prerequisite double")
	for index in range(95): region.advance(1.0/30.0)
	check(p.backpack.get("Bronze Ore") == 1 and p.get_skill_experience("mining") == xp,"Actual Mining transaction grants its ore at the XP cap")
	check(_completed(order) == 1,"Only successful native extraction completes one matching Mining directive")
	if region.has_method("_on_mining_reward"):
		region._on_mining_reward(p.entity_id,{"type":"skill_experience_gained","skill":"mining","ore_item_id":235,"deposit_id":rock.deposit_id,"deposit_generation":1})
	check(_completed(order) == 1,"Replayed extraction notification cannot complete a newly revealed directive")
	anchor.node_path = "FixtureGame/Bench"
	anchor.interaction_kind = "craft"
	anchor.station = "leatherworking"
	order = _seed(region,p,"crafting","tan_starter_hide","Tanned Leather")
	p.add_item("Starter Hide",3)
	check(region.submit(p.entity_id,{"type":"craft","station_id":"FixtureGame/Bench","recipe_id":"tan_starter_hide","quantity":3}).ok,"Actual approved recipe executes at the native station")
	check(p.backpack.get("Tanned Leather") == 3 and _completed(order) == 1,"One successful batch completes one directive, not one per produced item")
	check(not region.submit(p.entity_id,{"type":"craft","station_id":"FixtureGame/Bench","recipe_id":"tan_starter_hide","quantity":1}).ok and _completed(order) == 1,"Missing ingredients cannot advance another crafting directive")
	check(not region.submit(p.entity_id,{"type":"order_event","kind":"crafting","target_id":"tan_starter_hide"}).ok,"Clients have no action-completion injection command")
	var restored := CharacterCodec.decode(JSON.parse_string(JSON.stringify(CharacterCodec.encode(p,"outskirts"))),p.name,p.entity_id)
	check(restored.ok and restored.player.dead_man_orders.orders.smuggler.directives[0].kind == "crafting","New action kinds persist through the existing save format")
	anchor.node_path = "FixtureGame/Marker"
	anchor.interaction_kind = "portal"
	anchor.combat_targets = ["Goblin Scout"]
	order = _seed(region,p,"combat","Goblin Scout","")
	var victim := _monster(region,"native-bob-kill","Goblin Scout",Vector2(10,10))
	_kill(region,"action-bob",victim)
	check(_completed(order) == 0,"Another character's real kill does not progress this player's Order")
	victim = _monster(region,"still-alive","Goblin Scout",Vector2(10,10))
	if region.has_method("_record_order_defeat"): region._record_order_defeat(p.entity_id,victim)
	check(_completed(order) == 0,"A living actor is never accepted as a combat defeat")
	region.world.remove_monster(victim.entity_id)
	victim = _monster(region,"native-alice-kill","Goblin Scout",Vector2(10,10))
	_kill(region,p.entity_id,victim)
	check(_completed(order) == 1,"Attributed native monster defeat completes one owned combat directive")
	region._handle_events([{"type":"entity_died","entity_id":victim.entity_id,"attacker_id":p.entity_id}])
	check(_completed(order) == 1,"Duplicate death notification cannot complete another directive")
	victim = _monster(region,"wrong-species","Goblin Worker",Vector2(10,10))
	_kill(region,p.entity_id,victim)
	check(_completed(order) == 1,"Unrelated monster defeats are excluded")
	victim = _monster(region,"outside-anchor","Goblin Scout",Vector2(16,16))
	var actor: CombatActor = region.world.combat.actors[victim.entity_id]
	actor.hp = 0
	actor.is_alive = false
	actor.death_reported = true
	region._handle_events([{"type":"entity_died","entity_id":victim.entity_id,"attacker_id":p.entity_id}])
	check(_completed(order) == 1,"A remotely defeated monster outside the declared anchor does not count")
	for id: String in region.players.keys(): region.remove_player(id)
	geometry.free()

func _seed(region: RefCounted, p: PlayerState, kind: String, target: String, item: String, skill: String = "", level: int = 0) -> Dictionary:
	var order: Dictionary = region.orders.generate("smuggler",p.entity_id,1).order
	for row: Dictionary in order.directives:
		row.kind = kind
		row.target_id = target
		row.item_name = item
		row.anchor_id = "outskirts_tavern"
		row.skill = skill
		row.level = level
	p.dead_man_orders = Book.empty_book()
	p.dead_man_orders.generations.smuggler = 1
	p.dead_man_orders.orders.smuggler = order
	p.backpack["Smuggler's Order"] = 1
	check(Book.inventory_valid(p),"Native action fixture retains a valid owned physical Order")
	return order

func _completed(order: Dictionary) -> int:
	return order.directives.filter(func(row: Dictionary) -> bool: return row.state == "completed").size()

func _monster(region: RefCounted, id: String, target: String, point: Vector2) -> MonsterState:
	var monster := MonsterState.new(GameData.get_monster_by_name(target),point.x,point.y)
	var actor := CombatActor.new().configure({"entity_id":id,"name":target,"x":point.x,"y":point.y,"hp":1,"max_hp":1,"is_monster":true,"min_damage":0,"max_damage":0})
	region.world.register_monster_actor(monster,actor)
	return monster

func _kill(region: RefCounted, owner: String, monster: MonsterState) -> void:
	var actor: CombatActor = region.world.combat.actors[owner]
	actor.melee_attack_roll = 10000000.0
	actor.melee_max_damage = 1
	region.world.combat.random.seed = 123456
	region.submit(owner,{"type":"attack","target_id":monster.entity_id})
	for index in range(80):
		region.advance(1.0/30.0)
		if not monster.is_alive: break
	check(not monster.is_alive,"Native authoritative combat produces the death event")
	region.submit(owner,{"type":"target","target_id":""})

func _finish() -> void:
	print("[Orders directives] %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
