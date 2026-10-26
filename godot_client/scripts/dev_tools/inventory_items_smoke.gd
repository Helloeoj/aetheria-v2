extends SceneTree
## Exercise real ground pickup and inventory controls, including every non-equippable item.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()
	create_timer(30.0).timeout.connect(func() -> void:
		printerr("[Inventory items FAIL] Test did not finish")
		quit(1))

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("[Inventory items FAIL] ", label)

func _find_button(menu: Control, text: String) -> Button:
	for widget: Node in menu.find_children("*", "Button", true, false):
		if widget.text == text:
			return widget
	return null

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene := (load("res://scenes/EastOutskirtsLayered.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var game: Node = scene.get_node("Combat")
	game.set_physics_process(false)
	var menu: Control = game.inventory_menu
	var data := root.get_node("GameData")
	game.player.backpack.clear()
	menu.selected_item_name = ""
	var feathers: Dictionary = data.get_item_by_name("Feathers")
	check(not feathers.is_empty() and feathers.get("slot") == null, "Feathers exist as a non-equippable crafting item")
	var sprite: ActorSprite = game.actor_sprites[game.player.entity_id]
	check(game._spawn_ground_drop("Feathers", 5, sprite.position), "Spawn the same five-feather ground drop")
	var drop: GroundItemDrop = game.ground_drops.back()
	check(game._collect_ground_drop(drop), "Pick up Feathers through the real game path")
	check(int(game.player.backpack.get("Feathers", 0)) == 5 and drop not in game.ground_drops, "Pickup transfers all five feathers into the backpack once")
	menu.visible = true
	menu.select_page(0)
	var button := _find_button(menu, "Not equippable")
	check(button != null and button.disabled, "Feathers inventory details finish building with disabled equipment action")
	for item: Dictionary in data.items:
		if item.get("slot") != null:
			continue
		game.player.backpack.clear()
		game.player.add_item(String(item.name), 1)
		menu._inspect_item(String(item.name))
		if item.has("order_tier"):
			var action := "Read order" if item.get("order_opened",false) == true else "Open order"
			check(_find_button(menu,action) != null,"%s offers its inventory Order action" % item.name)
			continue
		button = _find_button(menu, "Not equippable")
		check(button != null and button.disabled, "%s details support an empty equipment slot" % item.name)
	game.player.backpack.clear()
	game.player.add_item("Bronze Dagger", 1)
	menu._inspect_item("Bronze Dagger")
	button = _find_button(menu, "Equip item")
	check(button != null and not button.disabled, "Weapons remain equippable")
	check(menu._item_bonus_text(data.get_item_by_name("Bronze Dagger")).contains("Melee strength: +6"), "Melee weapon details show strength bonus")
	game.player.backpack.clear()
	game.player.add_item("Feathers", 5)
	menu._inspect_item("Feathers")
	check(game.drop_inventory_item("Feathers", 2), "Feathers can be dropped again while the inventory is open")
	check(int(game.player.backpack.get("Feathers", 0)) == 3, "Dropping removes only the requested feathers")
	check(game._collect_ground_drop(game.ground_drops.back()), "Dropped feathers can be picked up again")
	check(int(game.player.backpack.get("Feathers", 0)) == 5, "Repeated pickup preserves quantity")
	print("[Inventory items] %d checks, %d failures" % [checks, failures.size()])
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
