extends Node

class RegionGeometry extends Node2D:
	var map_origin := Vector2.ZERO
	var map_width := 1536.0
	var map_height := 1024.0
	func _move_actor_with_map_collision(_id: String, displacement: Vector2) -> Vector2:
		return Vector2.ZERO if displacement.x > 0.0 else displacement
	func _query_map_terrain_collision(_from: Vector2, to: Vector2) -> Dictionary:
		return {"fraction": 0.5} if to.x > 12.0 else {}

var failures: Array[String] = []
func _ready() -> void:
	call_deferred("_run")
func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
func _run() -> void:
	var path := "res://network/authoritative_region.gd"
	check(ResourceLoader.exists(path), "Authoritative gameplay region must exist")
	if not failures.is_empty():
		get_tree().quit(1)
		return
	var script := load(path)
	var region = script.new()
	var geometry := RegionGeometry.new()
	add_child(geometry)
	var bench := CraftingStation.new()
	bench.setup("enchanting", "Authority test bench", Vector2(10,10))
	bench.name = "Bench"
	geometry.add_child(bench)
	var tannery := CraftingStation.new()
	tannery.setup("leatherworking","Authority tannery",Vector2(10,10))
	tannery.name = "Tannery"
	geometry.add_child(tannery)
	var store := CraftingStation.new()
	store.setup("bait_store","Authority bait store",Vector2(10,10))
	store.name = "BaitStore"
	geometry.add_child(store)
	var stove := CookingStation.new()
	stove.name = "Stove"
	stove.position = Vector2(320,704) - stove.approach_offset
	geometry.add_child(stove)
	var spot := FishingSpot.new()
	spot.name = "Shore"
	spot.position = Vector2(320,704) - spot.shore_offset
	geometry.add_child(spot)
	region.configure("test-region", geometry)
	check(region.world.monsters.is_empty(), "Region startup does not invent encounters")
	preload("res://scripts/dev_tools/region_combat_fixture.gd").add_monsters(region)
	var a := PlayerState.new("Alice")
	var b := PlayerState.new("Bob")
	region.add_player("char-alice", a)
	region.add_player("char-bob", b)
	check(region.players.size() == 2, "Two characters inhabit one shared region")
	check(region.world.combat.actors.has("char-bob"), "Second character has stable character actor ID")
	check(region.world.monsters.size() > 0, "Explicit combat fixture owns test monsters")
	check(not region.submit("char-alice", {"type":"grant_xp", "amount":100000}).ok, "Forged XP commands rejected")
	check(not region.submit("char-alice", {"type":"move", "direction":[1,0], "speed":999}).ok, "Unexpected stat fields rejected")
	check(not region.submit("char-alice", {"type":"attack", "target_id":"char-bob"}).ok, "PvP rejected")
	var initial := a.get_position()
	check(region.submit("char-alice", {"type":"move", "direction":[0,999]}).ok, "Movement intent accepted")
	region.advance(0.25)
	check(a.get_position().distance_to(initial) <= 1.001, "Server normalizes input and caps movement to four tiles per second")
	var expired := a.get_position()
	region.advance(0.5)
	check(a.get_position().is_equal_approx(expired), "Held movement expires without fresh input")
	region.submit("char-alice", {"type":"move", "direction":[1,0]})
	region.advance(0.1)
	check(is_equal_approx(a.x, initial.x), "Collision callback prevents movement")
	check(not region.submit("char-alice", {"type":"walk", "x":99,"y":10}).ok, "Out of bounds destination rejected")
	check(not region.submit("char-alice", {"type":"craft", "station_id":"forged","recipe_id":"empower_fire_orb", "quantity":1}).ok, "Forged station rejected")
	a.add_item("Beginner Rod", 1)
	check(region.submit("char-alice", _wire({"type":"drop","item_name":"Beginner Rod","quantity":1})).ok, "Owned item drops")
	check(region.snapshot("char-alice").drops.is_empty(), "Voluntary drop remains hidden until the source inventory save commits")
	check(region.has_method("mutation_checkpoint") and region.has_method("commit_mutations") and region.has_method("discard_mutations"),"Region exposes durable ground-item mutation checkpoints")
	if region.has_method("commit_mutations"):
		region.commit_mutations(a.entity_id,region.mutation_checkpoint(a.entity_id))
	var drops: Array = region.snapshot("char-alice").drops
	check(drops.size() == 1, "Ground drop shared by region")
	if not drops.is_empty():
		var drop_id: String = drops[0].drop_id
		check(region.submit("char-alice", {"type":"pickup","drop_id":drop_id}).ok, "First claimant receives item")
		check(not region.submit("char-bob", {"type":"pickup","drop_id":drop_id}).ok, "Second claimant cannot duplicate item")
	var snapshot: Dictionary = region.snapshot("char-bob")
	for actor: Dictionary in snapshot.actors:
		check(not actor.has("backpack") and not actor.has("skill_experience"), "Public actors exclude private saves")
	_check_shared_combat(region, a, b)
	_check_purchase(region,a)
	_check_wire_slots(region,a)
	_check_activities(region, a)
	if region.has_method("commit_mutations"):
		_check_mutation_staging(region,a,b)
	_check_late_mutation_ack(region)
	region.frozen["char-alice"] = true
	var frozen_hp := a.current_hp
	var frozen_position := a.get_position()
	check(not region.submit("char-alice", {"type":"drop","item_name":"Beginner Rod"}).ok, "Quarantined characters reject gameplay")
	region.advance(0.5)
	check(a.current_hp == frozen_hp and a.get_position() == frozen_position, "Quarantined characters remain untouched")
	region.frozen.erase("char-alice")
	region.remove_player("char-alice")
	region.remove_player("char-bob")
	check(not region.world.combat.actors.has("char-bob"), "Disconnect removes character actor")
	geometry.queue_free()
	await _check_actual_map_collision()
	print("Region authority smoke: %d failures" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_shared_combat(region: RefCounted, a: PlayerState, b: PlayerState) -> void:
	var mob: MonsterState = region.world.monsters[0]
	var actor: CombatActor = region.world.combat.actors[mob.entity_id]
	actor.x = 10
	actor.y = 10
	actor.spawn_x = 10
	actor.spawn_y = 10
	for id: String in [a.entity_id,b.entity_id]:
		var player: PlayerState = region.players[id]
		player.x = 10
		player.y = 10
		region.world.combat.actors[id].x = 10
		region.world.combat.actors[id].y = 10
		# Fix combat roll inputs so the assertion isolates actor ownership, not luck.
		region.world.combat.actors[id].melee_attack_roll = 10000000.0
		region.world.combat.actors[id].melee_max_damage = 1
	region.world.combat.random.seed = 123456
	var original_hp := actor.hp
	check(region.submit(a.entity_id, {"type":"attack","target_id":mob.entity_id}).ok, "Alice attacks shared monster")
	for _index in range(300):
		region.advance(1.0/60.0)
	check(a.get_skill_experience("attack") > 0, "Alice receives her own hit XP")
	check(b.get_skill_experience("attack") == 0, "Alice's hits never award Bob XP")
	check(actor.hp < original_hp, "Shared monster loses authoritative HP")
	check(region.submit(b.entity_id, {"type":"attack","target_id":mob.entity_id}).ok, "Bob attacks same monster")
	for _index in range(300):
		region.advance(1.0/60.0)
	check(b.get_skill_experience("attack") > 0, "Bob receives his own hit XP")
	var alice_gold := a.gold
	var bob_gold := b.gold
	actor.hp = 1
	region.world.combat.actors[b.entity_id].melee_attack_roll = 10000000.0
	region.world.combat.actors[b.entity_id].melee_max_damage = 1
	region.world.combat.actors[b.entity_id].attack_cooldown_seconds = 0
	region.world.combat.random.seed = 123456
	region.submit(a.entity_id,{"type":"target","target_id":""})
	region.advance(0.02)
	check(not actor.is_alive, "Shared monster death resolves once")
	check(a.gold == alice_gold and b.gold > bob_gold, "Death gold belongs to actual killer")
	for drop: Dictionary in region.snapshot(b.entity_id).drops:
		check(drop.owner_id == b.entity_id, "Monster loot carries killer character ownership")
	for id: String in [a.entity_id,b.entity_id]:
		region.submit(id, {"type":"target","target_id":""})
		region.players[id].in_combat = false
		region.world.combat.actors[id].current_target_id = ""
	actor.aggro_attacker_ids.clear()
	actor.current_target_id = ""
	region.advance(0.02)
	check(not a.in_combat and not b.in_combat, "Dead monsters release player combat locks")

func _check_activities(region: RefCounted, a: PlayerState) -> void:
	var craft_id := ""
	var fish_id := ""
	var cook_id := ""
	for station: Dictionary in region.snapshot(a.entity_id).stations:
		match station.kind:
			"craft": craft_id = station.station_id
			"fish": fish_id = station.station_id
			"cook": cook_id = station.station_id
	check(not craft_id.is_empty() and not fish_id.is_empty() and not cook_id.is_empty(), "Only authored server station nodes are discovered")
	a.x = 20
	a.y = 20
	check(not region.submit(a.entity_id,{"type":"craft","station_id":craft_id,"recipe_id":"empower_fire_orb","quantity":1}).ok, "Real station still requires actual proximity")
	a.x = 10
	a.y = 10
	region.world.combat.actors[a.entity_id].x = 10
	region.world.combat.actors[a.entity_id].y = 10
	a.add_item("Low Grade Fish Food", 2)
	check(region.submit(a.entity_id,{"type":"fish_start","station_id":fish_id,"rod":"Beginner Rod","bait":"Low Grade Fish Food"}).ok,"Owned fishing gear starts authoritative session")
	check(region.snapshot(a.entity_id).activity.state == FishingSession.State.POWER, "Fishing begins with server power clock")
	var fish_view: Dictionary = _wire({"type":"snapshot","activity":region.snapshot(a.entity_id).activity}).activity
	check(fish_view.has("elapsed") and fish_view.has("fight_time") and fish_view.has("fish_pull") and fish_view.fish_id == 0, "Original fishing presentation receives server clocks without revealing an early catch")
	check(not region.submit(a.entity_id,{"type":"fish_start","station_id":fish_id}).ok, "Recasting cannot reset an active server cast")
	check(not region.submit(a.entity_id,{"type":"fish_input","action":"catch","xp":9999}).ok, "Fishing cannot submit rewards")
	region.advance(0.2)
	check(region.snapshot(a.entity_id).activity.power > 0, "Server advances fishing power")
	check(region.submit(a.entity_id,{"type":"fish_input","action":"act"}).ok, "Fishing action commits cast")
	check(int(a.backpack.get("Low Grade Fish Food",0)) == 1, "Cast consumes one owned bait")
	region.submit(a.entity_id,{"type":"fish_stop"})
	a.add_item("Raw Reedkip", 1)
	check(region.submit(a.entity_id,_wire({"type":"cook_start","station_id":cook_id,"item_name":"Raw Reedkip","quantity":1})).ok, "Approved stove starts cooking")
	var cook_view: Dictionary = _wire({"type":"snapshot","activity":region.snapshot(a.entity_id).activity}).activity
	check(cook_view.has("feedback_elapsed") and cook_view.last_result is Dictionary, "Original pan feedback survives the server wire format")
	check(not region.submit(a.entity_id,{"type":"cook_flip"}).ok, "Early flip cannot manufacture cooked rewards")
	check(not region.submit(a.entity_id,{"type":"cook_flip","elapsed":999}).ok, "Cooking cannot forge timestamps")
	region.submit(a.entity_id,{"type":"cook_cancel"})

func _check_actual_map_collision() -> void:
	var viewport := SubViewport.new()
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var map := (load("res://scenes/EastOutskirtsLayered.tscn") as PackedScene).instantiate()
	var geometry: Node = map.get_node("Combat")
	geometry.set_meta("online_server_geometry",true)
	viewport.add_child(map)
	geometry.set_physics_process(false)
	geometry.set_process_input(false)
	geometry.set_process_unhandled_input(false)
	geometry.get_node("UI").process_mode = Node.PROCESS_MODE_DISABLED
	if geometry.cooking_controller != null:
		geometry.cooking_controller.set_process(false)
	if geometry.actor_sprites.has("player"):
		geometry.actor_sprites["player"].queue_free()
		geometry.actor_sprites.erase("player")
	var region = load("res://network/authoritative_region.gd").new()
	region.configure("actual-map",geometry)
	check(region.world.monsters.is_empty(), "Actual map startup has no automatic goblins")
	preload("res://scripts/dev_tools/region_combat_fixture.gd").add_monsters(region)
	await get_tree().physics_frame
	await get_tree().process_frame
	var player := PlayerState.new("MapCollisionRegression")
	region.add_player("map-regression",player)
	var start := player.get_position()
	check(start.is_equal_approx(geometry.player.get_position()),"Invalid legacy default uses authored expanded-map spawn")
	var shape := RectangleShape2D.new()
	shape.size = Vector2(24,24)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0,geometry.to_global(geometry._screen_position(start.x,start.y)))
	query.collision_mask = 1
	check(geometry.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(), "Actual map spawn fits full actor collision body outside unbuilt terrain")
	for monster: MonsterState in region.world.monsters:
		query.transform = Transform2D(0,geometry.to_global(geometry._screen_position(monster.x,monster.y)))
		check(geometry.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(), "Actual map server monsters spawn outside terrain")
	for _index in range(15):
		region.submit(player.entity_id,{"type":"move","direction":[1,0]})
		var previous := player.get_position()
		region.advance(1.0/30.0)
		check(player.get_position().distance_to(previous) <= 4.0/30.0 + 0.001,"Actual map collision never exceeds server speed, including overlap recovery")
		await get_tree().physics_frame
	check(player.get_position().distance_to(start) <= 2.001,"Actual map half-second move obeys four tiles per second")
	region.remove_player(player.entity_id)
	viewport.queue_free()
	await get_tree().process_frame

func _wire(command: Dictionary) -> Dictionary:
	# Exercise the same JSON protocol boundary as the UDP client and host.
	var protocol := preload("res://network/world_protocol.gd")
	var outgoing := command.duplicate(true)
	outgoing["v"] = protocol.VERSION
	var received: Dictionary = protocol.unpack(protocol.pack(outgoing))
	received.erase("v")
	return received

func _check_purchase(region: RefCounted, player: PlayerState) -> void:
	var store_id := ""
	var wrong_id := ""
	for station: Dictionary in region.snapshot(player.entity_id).stations:
		if station.get("station","") == "bait_store":
			store_id = station.station_id
		elif station.kind == "craft":
			wrong_id = station.station_id
	var item: Dictionary = GameData.get_item_by_name("Beginner Rod")
	var saved_price: Variant = item.get("buy_price",null)
	item["buy_price"] = 25
	player.gold = 200
	var before := int(player.backpack.get("Beginner Rod",0))
	check(not region.submit(player.entity_id,_wire({"type":"purchase","station_id":wrong_id,"item_name":"Beginner Rod","quantity":2})).ok,"Purchases require the actual bait store station")
	player.x = 20
	check(not region.submit(player.entity_id,_wire({"type":"purchase","station_id":store_id,"item_name":"Beginner Rod","quantity":2})).ok,"Purchases require real server station proximity")
	player.x = 10
	check(region.submit(player.entity_id,_wire({"type":"purchase","station_id":store_id,"item_name":"Beginner Rod","quantity":2})).ok,"Network serialized purchase uses approved shop rules")
	check(player.gold == 150 and int(player.backpack.get("Beginner Rod",0)) == before + 2,"Purchase atomically transfers exact catalog price and quantity")
	check(not region.submit(player.entity_id,_wire({"type":"purchase","station_id":store_id,"item_name":"Demon Rod","quantity":1})).ok,"Restricted items remain unavailable at the online shop")
	check(not region.submit(player.entity_id,{"type":"purchase","station_id":store_id,"item_name":"Beginner Rod","quantity":1,"price":0}).ok,"Client cannot supply shop prices")
	if saved_price == null:
		item.erase("buy_price")
	else:
		item["buy_price"] = saved_price

func _check_wire_slots(region: RefCounted, player: PlayerState) -> void:
	player.store_fishing_catch("Raw Reedkip")
	var slot := player.fishing_pale.find("Raw Reedkip")
	check(region.submit(player.entity_id,_wire({"type":"pale_move","slot":slot})).ok,"JSON whole-number pale slot is accepted")
	var tannery_id := ""
	for station: Dictionary in region.snapshot(player.entity_id).stations:
		if station.get("station","") == "leatherworking":
			tannery_id = station.station_id
	player.add_item("Starter Hide",2)
	check(region.submit(player.entity_id,_wire({"type":"craft","station_id":tannery_id,"recipe_id":"tan_starter_hide","quantity":2})).ok,"JSON whole-number craft quantity reaches the existing recipe rules")
	check(int(player.backpack.get("Tanned Leather",0)) == 2,"Network crafting consumes recipe inputs and credits correct output quantity")
	var before := player.backpack.duplicate(true)
	for bad: Variant in [1.5,-1.0,2147483648.0,INF,NAN,true,"1"]:
		check(not region.submit(player.entity_id,{"type":"drop","item_name":"Beginner Rod","quantity":bad}).ok,"Fractional, nonfinite and unsupported quantities rejected")
	check(not region.submit(player.entity_id,{"type":"pale_move","slot":0.5}).ok,"Fractional pale slots rejected")
	check(player.backpack == before,"Malformed numeric commands never mutate inventory")

func _check_mutation_staging(region: RefCounted, a: PlayerState, b: PlayerState) -> void:
	region.commit_mutations(a.entity_id,region.mutation_checkpoint(a.entity_id))
	region.commit_mutations(b.entity_id,region.mutation_checkpoint(b.entity_id))
	region.drops.clear()
	a.add_item("Beginner Rod",3)
	var count := int(a.backpack.get("Beginner Rod",0))
	region.submit(a.entity_id,_wire({"type":"drop","item_name":"Beginner Rod","quantity":1}))
	var first: int = region.mutation_checkpoint(a.entity_id)
	region.submit(a.entity_id,_wire({"type":"drop","item_name":"Beginner Rod","quantity":1}))
	var second: int = region.mutation_checkpoint(a.entity_id)
	check(second > first,"Each ground mutation has a monotonic save checkpoint")
	check(region.snapshot(b.entity_id).drops.is_empty(),"Other players cannot see or claim uncommitted outgoing drops")
	region.commit_mutations(a.entity_id,first)
	check(region.snapshot(b.entity_id).drops.size() == 1,"Save ack publishes only outgoing drops included in that checkpoint")
	region.commit_mutations(a.entity_id,first)
	check(region.snapshot(b.entity_id).drops.size() == 1,"Repeated durable acknowledgement cannot duplicate a ground item")
	region.discard_mutations(a.entity_id)
	check(region.snapshot(b.entity_id).drops.size() == 1,"Terminal lease loss discards unpublished outputs")
	check(int(a.backpack.get("Beginner Rod",0)) == count - 2,"Discard does not restore uncertain character inventory")
	var drop: Dictionary = region.snapshot(b.entity_id).drops[0]
	b.x = float(drop.x)
	b.y = float(drop.y)
	check(region.submit(b.entity_id,{"type":"pickup","drop_id":drop.drop_id}).ok,"First pickup reserves the committed ground item")
	check(not region.submit(a.entity_id,{"type":"pickup","drop_id":drop.drop_id}).ok,"Concurrent claimant cannot take a reserved pickup")
	region.discard_mutations(b.entity_id)
	check(region.snapshot(a.entity_id).drops.is_empty(),"Uncertain pickup discard never republishes a possibly committed item")
	region.commit_mutations(a.entity_id,second)
	check(region.snapshot(a.entity_id).drops.is_empty(),"Late acknowledgements cannot resurrect discarded outgoing items")
	check(a.store_fishing_catch("Raw Reedkip"),"Pale fixture holds an owned raw fish")
	var slot := a.fishing_pale.find("Raw Reedkip")
	check(region.submit(a.entity_id,_wire({"type":"pale_drop","slot":slot})).ok,"Pale drop accepts JSON slot and stages its output")
	check(region.snapshot(b.entity_id).drops.is_empty(),"Pale drops also wait for source save acknowledgement")
	region.commit_mutations(a.entity_id,region.mutation_checkpoint(a.entity_id))
	check(region.snapshot(b.entity_id).drops.size() == 1,"Durable pale removal publishes one ground fish")
	region.drops.clear()

func _check_late_mutation_ack(region: RefCounted) -> void:
	var id := "replacement-session"
	var original := PlayerState.new("Original lease")
	original.add_item("Beginner Rod",1)
	region.add_player(id,original)
	region.submit(id,_wire({"type":"drop","item_name":"Beginner Rod","quantity":1}))
	var stale_checkpoint: int = region.mutation_checkpoint(id)
	region.discard_mutations(id)
	region.remove_player(id)
	var replacement := PlayerState.new("Replacement lease")
	replacement.add_item("Beginner Rod",1)
	region.add_player(id,replacement)
	region.submit(id,_wire({"type":"drop","item_name":"Beginner Rod","quantity":1}))
	var current_checkpoint: int = region.mutation_checkpoint(id)
	check(current_checkpoint > stale_checkpoint,"Rejoining the same character never resets ground mutation serials")
	region.commit_mutations(id,stale_checkpoint)
	check(region.snapshot(id).drops.is_empty(),"Old lease save acknowledgement cannot publish a replacement lease's drop")
	region.commit_mutations(id,current_checkpoint)
	check(region.snapshot(id).drops.size() == 1,"Replacement lease's own durable acknowledgement publishes its drop")
	var drop: Dictionary = region.snapshot(id).drops[0]
	replacement.x = drop.x
	replacement.y = drop.y
	check(region.submit(id,{"type":"pickup","drop_id":drop.drop_id}).ok,"Durable pickup fixture reserves a published item")
	var pickup_checkpoint: int = region.mutation_checkpoint(id)
	region.commit_mutations(id,pickup_checkpoint)
	region.commit_mutations(id,pickup_checkpoint)
	check(region.snapshot(id).drops.is_empty(),"Durable pickup acknowledgement is idempotent and never republishes ground loot")
	check(int(replacement.backpack.get("Beginner Rod",0)) == 1,"Reserved pickup credits inventory exactly once")
	region.remove_player(id)
