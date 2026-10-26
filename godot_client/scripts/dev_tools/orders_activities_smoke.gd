extends Node
## Trusted fixture exercises real activity/session success and real saved Order progress.
const Activities := preload("res://network/region_activities.gd")
const Service := preload("res://scripts/orders/orders_service.gd")
const Book := preload("res://scripts/orders/order_book.gd")

class TrustedRegion extends RefCounted:
	var players: Dictionary = {}
	var dirty: Dictionary = {}
	var world := WorldState.new()
	var orders := Service.new()
	func station_for(_player: PlayerState, station: String, kind: String) -> Dictionary:
		return {"station_id":station,"kind":kind}
	func record_order_action(id: String, kind: String, target_id: String, station: String) -> void:
		var anchor := "river_upper" if station == "Combat/RiverFishingSpot" else "tavern_stove"
		var region_id := "outskirts" if anchor == "river_upper" else "tavern"
		orders.on_event(players[id],kind,target_id,{"anchor_id":anchor,"region_id":region_id,"in_range":true})

var checks := 0
var failures := 0
var region := TrustedRegion.new()
var activities := Activities.new()
var player := PlayerState.new("Orders activity tester")

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("[Orders activities FAIL] ",label)

func _run() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/dev_tools/fixtures/orders_config.json"))
	check(region.orders.configure(config).ok,"Real Orders service accepts the synthetic fixture")
	player.entity_id = "orders-activity-tester"
	region.players[player.entity_id] = player
	activities.configure(region)
	player.set_skill_level("fishing",100)
	player.set_skill_level("cooking",100)
	var order := prepare_order("fishing")
	var session := fish("Raw Reedkip")
	var before := player.get_skill_experience("fishing")
	activities.advance(player.entity_id,0.02)
	check(session.state == FishingSession.State.CAUGHT and player.get_skill_experience("fishing") == before,"Real landed catch succeeds even when Fishing XP is capped")
	check(completed(order) == 1,"A landed catch completes one actual matching directive at the XP cap")
	activities.advance(player.entity_id,0.02)
	check(completed(order) == 1,"Repeated CAUGHT updates cannot complete a second directive")
	order = prepare_order("fishing")
	session = fish("Raw Marlo")
	activities.advance(player.entity_id,0.02)
	check(session.state == FishingSession.State.CAUGHT and completed(order) == 0,"Another fish species cannot satisfy a Reedkip directive")
	session = fish("Raw Reedkip")
	session.state = FishingSession.State.LOST
	activities.advance(player.entity_id,0.02)
	check(completed(order) == 0,"An escaped fish cannot complete an Order")
	player.fishing_pale.fill("Raw Reedkip")
	session = fish("Raw Reedkip")
	activities.advance(player.entity_id,0.02)
	check(session.state == FishingSession.State.FIGHT and completed(order) == 0,"A full pale prevents landing and Order credit")
	activities.fishing.clear()
	order = prepare_order("cooking")
	var cooking := cook()
	before = player.get_skill_experience("cooking")
	var flipped := activities.submit(player.entity_id,{"type":"cook_flip","encounter_id":1,"prompt_id":1,"action_id":1})
	check(flipped.ok and cooking.cooked_count == 1 and player.get_skill_experience("cooking") == before,"Real flip cooks successfully even when Cooking XP is capped")
	check(completed(order) == 1,"Successful real cooking resolution completes one matching directive")
	activities.submit(player.entity_id,{"type":"cook_flip","encounter_id":1,"prompt_id":1,"action_id":1})
	activities.advance(player.entity_id,0.01)
	check(completed(order) == 1,"Replayed flip and feedback updates cannot repeat Order credit")
	cooking.close()
	order = prepare_order("cooking")
	cooking = cook()
	cooking.flip_window = 0.01 # Controlled missed prompt; real timeout resolution grants burnt output.
	activities.advance(player.entity_id,0.02)
	check(cooking.burnt_count == 1 and completed(order) == 0,"A real burnt result never completes a cooking directive")
	cooking.close()
	cooking = cook()
	cooking.close("Cancelled by test")
	activities.advance(player.entity_id,0.02)
	check(completed(order) == 0,"Cancelled cooking cannot complete an Order")
	print("[Orders activities] %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)

func prepare_order(kind: String) -> Dictionary:
	player.dead_man_orders = Book.empty_book()
	var generated: Dictionary = region.orders.generate("smuggler",player.entity_id,1)
	var order: Dictionary = generated.order
	for index in range(order.directives.size()):
		var row: Dictionary = order.directives[index]
		row.kind = kind
		row.anchor_id = "river_upper" if kind == "fishing" else "tavern_stove"
		row.target_id = "Reedkip"
		row.skill = kind
		row.level = 20
		row.item_name = "Raw Reedkip" if kind == "fishing" else "Reedkip"
	player.dead_man_orders.generations.smuggler = 1
	player.dead_man_orders.orders.smuggler = order
	check(Book.validate_book(player.dead_man_orders,player.entity_id),"Controlled active action directives remain a valid persistent Book")
	return order

func fish(item_name: String) -> FishingSession:
	var session := FishingSession.new(player)
	session.fish = GameData.get_item_by_name(item_name)
	session.state = FishingSession.State.FIGHT
	session.remaining = 0
	activities.fishing[player.entity_id] = session
	activities.station_ids[player.entity_id] = "Combat/RiverFishingSpot"
	return session

func cook() -> CookingSession:
	var heat := CookingCampfire.new(player.get_position())
	heat.active = true
	var session := CookingSession.new(player,heat,region.world.combat)
	player.add_item("Raw Reedkip")
	check(session.start("Raw Reedkip").is_empty(),"Real cooking batch starts")
	activities.cooking[player.entity_id] = session
	activities.station_ids[player.entity_id] = "Combat/Stove"
	activities._cook_meta[player.entity_id] = {"encounter":1,"prompt":0,"phase":0,"action_ack":0}
	activities.advance(player.entity_id,10)
	check(session.state == CookingSession.State.FLIP_PENDING,"Real timed cooking reserves a fish and presents a flip prompt")
	return session

func completed(order: Dictionary) -> int:
	var count := 0
	for row: Dictionary in order.directives:
		count += int(row.state == "completed")
	return count
