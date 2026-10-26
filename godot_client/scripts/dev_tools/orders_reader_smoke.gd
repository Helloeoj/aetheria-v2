extends Node
## Exercise the real inventory click, service, reader and Ledger together.
class DelayedController extends "res://scripts/orders/orders_controller.gd":
	var delayed := false
	var pending: Dictionary = {}
	var pending_requests: Array[Dictionary] = []
	func _dispatch(command: Dictionary) -> void:
		if delayed:
			pending = command.duplicate(true)
			pending_requests.append(command.duplicate(true))
		else:
			super._dispatch(command)

class Fixture extends Node:
	var player := PlayerState.new("Order reader")
	var orders_controller := DelayedController.new()
	var inventory_menu := InventoryMenu.new()
	var context_menu := InteractionContextMenu.new()
	var spell_cast_requested := false

var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("[Orders reader FAIL] ",label)

func _ready() -> void:
	_run.call_deferred()

func _labels(root: Node) -> String:
	var value := ""
	for node: Node in root.find_children("*","Label",true,false):
		value += node.text + "\n"
	return value

func _button(root: Node, caption: String) -> Button:
	for node: Node in root.find_children("*","Button",true,false):
		if node.text == caption:
			return node
	return null

func _slot(menu: Node, item_name: String) -> Button:
	for node: Node in menu.find_children("*","Button",true,false):
		if node.get_meta("item_name","") == item_name:
			return node
	return null

func _run() -> void:
	get_tree().root.size = Vector2i(1280,720)
	var game := Fixture.new()
	add_child(game)
	game.add_child(game.context_menu)
	game.add_child(game.inventory_menu)
	game.add_child(game.orders_controller)
	game.player.entity_id = "reader-owner"
	var menu := game.inventory_menu
	game.orders_controller.game = game
	game.orders_controller.region_id = "outskirts"
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/dev_tools/fixtures/orders_config.json"))
	check(game.orders_controller.service.configure(config).ok,"Reader test uses valid authored content")
	game.player.add_item("Sealed Deckhand's Order",2)
	menu.configure(game)
	menu.visible = true
	var sealed := _slot(menu,"Sealed Deckhand's Order")
	check(sealed != null,"Physical packet is visible in the actual inventory grid")
	if sealed != null:
		sealed.pressed.emit()
	var reader := menu.get_node_or_null("OrderReader")
	check(reader != null and reader.visible,"Clicking a sealed inventory item opens its readable Order sheet")
	check(menu.selected_page == 0,"Inventory click does not force the Captain's Ledger page")
	check(game.player.backpack.get("Deckhand's Order") == 1,"Reading a sealed packet transforms it into a carried opened Order")
	if reader == null or not game.player.dead_man_orders.orders.has("deckhand"):
		game.queue_free()
		_finish()
		return
	var order: Dictionary = game.player.dead_man_orders.orders.deckhand
	var original_id: String = order.id
	check(_labels(reader).contains(order.directives[0].text),"Inventory reader shows an available instruction")
	check(not _labels(reader).contains("SECRET_"),"Reader cannot expose private answers or sealed details")
	check(_button(reader,"Search here") != null,"World-search directives can be followed from the inventory reader")
	var close := _button(reader,"Close")
	check(close != null,"Order sheet has a close action")
	if close != null:
		close.pressed.emit()
	check(not reader.visible,"Closing the sheet returns to the inventory")
	var opened := _slot(menu,"Deckhand's Order")
	check(opened != null,"The opened Order remains a physical inventory slot")
	if opened != null:
		opened.pressed.emit()
	check(reader.visible and game.player.dead_man_orders.orders.deckhand.id == original_id and game.player.dead_man_orders.generations.deckhand == 1,"Clicking the opened item rereads the same instance without rerolling")
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_RIGHT
	if opened != null:
		menu._inventory_context_input(click,"Deckhand's Order",opened)
	check(_button(game.context_menu,"Read order") != null,"Opened Order context menu offers Read order")
	check(_button(game.context_menu,"Drop") == null,"Bound opened Order has no generic Drop action")
	game.context_menu.dismiss()
	_slot(menu,"Sealed Deckhand's Order").pressed.emit()
	check(not _labels(reader).contains("Waiting") and _labels(reader).contains("active order"),"Rejected activation explains why a second packet cannot open instead of waiting forever")
	_slot(menu,"Deckhand's Order").pressed.emit()
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	menu.on_key_press(key)
	check(menu.visible and not reader.visible,"Escape closes the Order sheet before the underlying inventory")
	menu.select_page(5)
	check(_labels(menu).contains("Collection log"),"Captain's Ledger is explicitly a collection log")
	check(_labels(menu).contains("Sealed: 1") and _labels(menu).contains("Opened: 1"),"Ledger shows actual sealed and opened counts by tier")
	check(_labels(menu).contains(order.directives[0].text),"Ledger also shows current instructions")
	check(_button(menu,"Read order") != null,"Ledger can reread the carried physical Order")
	var feathers: Dictionary = GameData.get_item_by_name("Feathers")
	feathers.orders_exclusive = true
	game.player.dead_man_orders.collection[str(int(feathers.id))] = 2
	game.player.dead_man_orders.completed.deckhand = 3
	menu.refresh_view()
	check(_labels(menu).contains("Feathers") and _labels(menu).contains("Obtained: 2"),"Ledger displays recorded exclusive reward quantity")
	check(_labels(menu).contains("Completed: 3"),"Tier completion total survives replacement of the most recent Order")
	check(not _labels(menu).contains("Beginner Rod"),"Ordinary equipment is excluded from the collection catalog")
	feathers.erase("orders_exclusive")
	# Delay an activation as an online acknowledgement would be delayed.
	game.player.add_item("Sealed Smuggler's Order")
	game.orders_controller.delayed = true
	menu.select_page(0)
	_slot(menu,"Sealed Smuggler's Order").pressed.emit()
	check(reader.visible and _labels(reader).contains("Waiting"),"Reader waits for authoritative activation instead of inventing tasks")
	check(not game.player.dead_man_orders.orders.has("smuggler"),"Pending activation does not create progress locally")
	_slot(menu,"Sealed Smuggler's Order").pressed.emit()
	game.orders_controller.delayed = false
	game.orders_controller._dispatch(game.orders_controller.pending_requests[0])
	check(_labels(reader).contains("Smuggler's Order") and not _labels(reader).contains("Waiting"),"Acknowledged activation refreshes the correct tier's reader")
	game.orders_controller._dispatch(game.orders_controller.pending_requests[1])
	check(_labels(reader).contains(game.player.dead_man_orders.orders.smuggler.directives[0].text),"A stale duplicate rejection cannot hide an acknowledged opened Order's instructions")
	check(menu.selected_page == 0,"Delayed acknowledgement keeps the player in inventory")
	var previous_mode := Network.mode
	Network.mode = Network.Mode.CLIENT
	game.player.orders_view = load("res://scripts/orders/order_book.gd").public_book(game.player.dead_man_orders)
	game.player.add_item("Sealed Corsair's Order")
	menu.refresh_view()
	_slot(menu,"Sealed Corsair's Order").pressed.emit()
	check(not _labels(reader).contains("Waiting") and _labels(reader).contains("connection is unavailable"),"Unsent online activation reports a connection failure without consuming its packet")
	check(game.player.backpack.get("Sealed Corsair's Order") == 1,"Failed send preserves the physical sealed Order")
	Network.mode = previous_mode
	game.player.orders_view.clear()
	menu._read_order("smuggler")
	await get_tree().process_frame
	await get_tree().process_frame
	check(reader.get_global_rect().size.x <= 1280 and reader.get_global_rect().size.y <= 720,"Order sheet fits the viewport")
	get_tree().root.size = Vector2i(800,450)
	await get_tree().process_frame
	await get_tree().process_frame
	check(reader.get_global_rect().end.x <= 800 and reader.get_global_rect().end.y <= 450,"Resizing the window keeps the Order sheet and Close action on screen")
	get_tree().root.size = Vector2i(1280,720)
	await get_tree().process_frame
	if "--orders-reader-capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("aetheria-orders-reader.png"))
		reader.hide()
		menu.select_page(5)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("aetheria-orders-collection.png"))
	game.queue_free()
	await get_tree().process_frame
	await _real_input(config)
	_finish()

func _real_input(config: Dictionary) -> void:
	var scene := (load("res://scenes/EastOutskirtsLayered.tscn") as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var actual: Node = scene.get_node("Combat")
	actual.set_physics_process(false)
	actual.orders_controller.service.configure(config)
	actual.player.backpack.clear()
	actual.player.add_item("Sealed Deckhand's Order")
	actual.inventory_menu.visible = true
	actual.inventory_menu.select_page(0)
	_slot(actual.inventory_menu,"Sealed Deckhand's Order").pressed.emit()
	var sheet: Control = actual.inventory_menu.get_node("OrderReader")
	check(sheet.visible,"Actual game opens the inventory Order sheet")
	check(not actual.drop_inventory_item("Deckhand's Order",1) and actual.player.backpack.get("Deckhand's Order") == 1,"Actual offline drop path preserves a bound opened Order")
	get_viewport().gui_release_focus()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	actual._input(escape)
	check(actual.inventory_menu.visible and not sheet.visible,"Actual game Escape closes the sheet before hiding inventory")
	scene.queue_free()
	await get_tree().process_frame

func _finish() -> void:
	print("[Orders reader] %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
