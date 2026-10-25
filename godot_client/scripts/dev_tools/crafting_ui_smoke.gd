extends Node

var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("[Crafting UI FAIL] " + label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	check(FileAccess.file_exists("res://scripts/shop_service.gd"), "Bait store transactions exist")
	check(FileAccess.file_exists("res://scripts/ui_crafting.gd"), "Crafting interaction panel exists")
	check(FileAccess.file_exists("res://scripts/crafting_station.gd"), "Physical crafting stations exist")
	if failures > 0:
		get_tree().quit(1)
		return
	var shop_script: Script = load("res://scripts/shop_service.gd")
	var player := PlayerState.new("Crafting UI test")
	player.gold = 100000
	var before := player.gold
	check(not shop_script.purchase(player, "Demon Rod", 1).ok, "Demon Rod is never sold")
	check(player.gold == before and player.backpack.is_empty(), "Denied purchase spends nothing")
	check(not shop_script.purchase(player, "Beginner Rod", -1).ok, "Negative shop quantities rejected")
	var item: Dictionary = GameData.get_item_by_name("Beginner Rod")
	var saved_price: Variant = item.get("buy_price", null)
	item["buy_price"] = 25
	check(shop_script.purchase(player, "Beginner Rod", 2).ok, "Priced store rod can be purchased")
	check(player.gold == before - 50 and int(player.backpack.get("Beginner Rod", 0)) == 2, "Purchase conserves gold and quantity")
	if saved_price == null:
		item.erase("buy_price")
	else:
		item["buy_price"] = saved_price
	var scene: Node = (load("res://scenes/EastOutskirtsLayered.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var game: Node = scene.get_node("Combat")
	game.set_physics_process(false)
	check(game.crafting_panel != null, "Real scene owns crafting UI")
	var stations: Array[Node] = get_tree().get_nodes_in_group("crafting_station")
	check(stations.size() >= 6, "World provides furnace, anvil, hide, cloth, wood and bait stations")
	var anvil: Node
	for station: Node in stations:
		if station.station_id == "anvil":
			anvil = station
	check(anvil != null, "Anvil exists")
	if anvil != null:
		while game.grid_adapter != null and not game.grid_adapter.completed:
			await get_tree().physics_frame
		var point: Vector2 = anvil.simulation_position
		if game.world.grid != null:
			var route: PackedVector2Array = game.world.grid.path(game.player.get_position(), point, 2.5)
			check(not route.is_empty(), "Anvil has a reachable grid approach")
			if not route.is_empty():
				point = route[-1]
		var actor: CombatActor = game.combat.actors[game.player.entity_id]
		actor.x = point.x
		actor.y = point.y
		game.player.x = point.x
		game.player.y = point.y
		game._update_sprite_position(actor.entity_id)
		game.player.add_item("Bronze Ingot", 3)
		game.request_crafting(anvil)
		check(game.crafting_panel.visible, "Nearby anvil opens panel")
		var button: Button
		for candidate: Node in game.crafting_panel.find_children("*", "Button", true, false):
			if candidate.get_meta("recipe_id", "") == "bronze_longsword":
				button = candidate
		check(button != null, "Approved recipe has a real button")
		if button != null:
			button.pressed.emit()
			check(int(game.player.backpack.get("Bronze Longsword", 0)) == 1, "UI crafts longsword through service")
			check(int(game.player.backpack.get("Bronze Ingot", 0)) == 0, "UI spends exactly three ingots")
		game.crafting_panel.close()
		game.player.x += 50
		actor.x = game.player.x
		game._update_sprite_position(actor.entity_id)
		game.request_crafting(anvil)
		check(not game.crafting_panel.visible, "Distant station rejects interaction")
	game.player.backpack.clear()
	game.player.backpack["Runite Dagger"] = 1
	var canonical: Dictionary = GameData.get_item_by_name("Runite Dagger")
	InventorySystem.inventory_slots(game.player)
	check(int(game.player.backpack.get(String(canonical.name), 0)) == 1, "Legacy backpack names migrate without loss")
	scene.queue_free()
	await get_tree().process_frame
	print("[Crafting UI] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
