extends Node
## Real native journal controls against an isolated controller intent boundary.
class IntentRecorder extends RefCounted:
	var state: Dictionary = {"generations": {"deckhand": 0}, "orders": {}}
	var calls: Array = []
	func view() -> Dictionary:
		return state.duplicate(true)
	func open_sealed(item_name: String) -> void:
		calls.append(["open", item_name])
	func search(order_id: String, directive_id: String, answer: String = "") -> void:
		calls.append(["search", order_id, directive_id, answer])
	func claim(order_id: String) -> void:
		calls.append(["claim", order_id])
	func abandon(order_id: String, confirmed: bool = false) -> void:
		calls.append(["abandon", order_id, confirmed])

class Fixture extends Node:
	var player := PlayerState.new("Ledger UI test")
	var orders_controller := IntentRecorder.new()
	var spell_cast_requested := false
	var context_menu := InteractionContextMenu.new()

var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("[Orders UI FAIL] ", label)

func button(menu: Node, caption: String) -> Button:
	for node: Node in menu.find_children("*", "Button", true, false):
		if node.text == caption and node.is_visible_in_tree():
			return node
	return null

func labels(menu: Node) -> String:
	var result := ""
	for node: Node in menu.find_children("*", "Label", true, false):
		result += node.text + "\n"
	return result

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	var game := Fixture.new()
	add_child(game)
	game.add_child(game.context_menu)
	var menu := InventoryMenu.new()
	game.add_child(menu)
	menu.configure(game)
	menu.visible = true
	menu.select_page(5)
	check(menu.selected_page == 5 and menu.tabs.get_tab_count() == 6, "ledger is selectable after the five preserved journal pages")
	check(labels(menu).contains("No active orders"), "empty ledger explains the absence of active orders")
	if menu.selected_page != 5:
		game.queue_free()
		await get_tree().process_frame
		print("[Orders UI] %d checks, %d failures" % [checks, failures])
		get_tree().quit(1)
		return
	var item_name := "Sealed Deckhand's Order"
	var item := {"id": 990001, "name": item_name, "type": "Orders", "order_tier": "deckhand", "stackable": true}
	GameData.items_by_name[item_name] = item
	game.player.add_item(item_name, 2)
	menu.select_page(0)
	menu._inspect_item(item_name)
	var open := button(menu, "Open order")
	check(open != null, "sealed inventory details offer Open order")
	if open != null:
		open.pressed.emit()
	check(game.orders_controller.calls == [["open", item_name]], "opening sends one intent without consuming the sealed item locally")
	check(game.player.backpack.get(item_name) == 2, "UI preserves inventory until controller authority responds")
	var source := Button.new()
	menu.add_child(source)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	menu._inventory_context_input(click, item_name, source)
	check(button(game.context_menu, "Open order") != null, "sealed inventory context menu offers Open order")
	game.context_menu.dismiss()
	game.orders_controller.calls.clear()
	game.orders_controller.state.orders = {"deckhand": {"id": "order-one", "tier": "deckhand", "state": "active", "sealed": 2, "completed": 1, "total": 3, "directives": [
		{"id": "cipher-one", "kind": "cipher", "text": "Read the marked words.", "state": "available"},
		{"id": "fish-one", "kind": "fishing", "text": "Land a river catch.", "state": "available", "requirements": {"skill": "fishing", "level": 1, "equipment": "Raw Minnow"}},
		{"id": "hidden-one", "kind": "search", "text": "HIDDEN SENTINEL", "state": "sealed"}
	]}}
	menu.select_page(5)
	check(not labels(menu).contains("HIDDEN SENTINEL"), "sealed directives remain hidden")
	check(labels(menu).contains("1 / 3") and labels(menu).contains("Sealed orders: 2"), "ledger presents progress and sealed inventory count")
	check(labels(menu).contains("Sealed directives: 2"), "ledger shows hidden directive count without its content")
	check(labels(menu).contains("Target item: Raw Minnow"), "activity target item is not presented as required equipment")
	var answer: LineEdit = menu.find_child("CipherAnswer", true, false)
	check(answer != null, "available cipher has native answer input")
	if answer != null:
		answer.text = "north wind"
	var search := button(menu, "Search here")
	check(search != null, "available cipher offers a nearby search intent")
	if search != null:
		search.pressed.emit()
	check(game.orders_controller.calls == [["search", "order-one", "cipher-one", "north wind"]], "cipher search sends the exact typed answer and directive identity")
	check(game.orders_controller.state.orders.deckhand.completed == 1, "UI cannot complete directives locally")
	check(button(menu, "Complete") == null, "activity directives have no fake completion action")
	game.orders_controller.calls.clear()
	var abandon := button(menu, "Abandon order")
	check(abandon != null, "active order exposes abandonment")
	if abandon != null:
		abandon.pressed.emit()
	var confirm: ConfirmationDialog = menu.find_child("AbandonOrderConfirmation", true, false)
	check(confirm != null and confirm.visible and game.orders_controller.calls.is_empty(), "abandonment requires explicit native confirmation")
	if confirm != null:
		confirm.canceled.emit()
		check(game.orders_controller.calls.is_empty(), "cancelling abandonment sends no intent")
		confirm.hide()
		abandon.pressed.emit()
		confirm = menu.find_child("AbandonOrderConfirmation", true, false)
		confirm.confirmed.emit()
		confirm.hide()
	check(game.orders_controller.calls == [["abandon", "order-one", true]], "confirmed abandonment sends a confirmed intent")
	game.orders_controller.calls.clear()
	var before := menu._state_signature()
	game.orders_controller.state.orders.deckhand.cache = {"label": "A tucked-away cache", "region_id": "valtheiris", "hint": "Near the tavern entrance."}
	game.orders_controller.state.orders.deckhand.state = "cache_revealed"
	check(menu._state_signature() != before, "journal refresh signature follows authoritative order updates")
	menu.refresh_view()
	check(labels(menu).contains("Near the tavern entrance."), "revealed cache displays its public hint")
	var cache_search := button(menu, "Search for cache here")
	check(cache_search != null, "revealed cache offers local search")
	if cache_search != null:
		cache_search.pressed.emit()
	check(game.orders_controller.calls == [["claim", "order-one"]], "cache action delegates nearby validation to controller")
	game.orders_controller.state.orders.deckhand.rewards = {"gold": 35, "items": [{"item_name": "Feathers", "count": 2}]}
	menu.refresh_view()
	check(not labels(menu).contains("Feathers"), "rewards stay hidden before cache claim is confirmed")
	game.orders_controller.state.orders.deckhand.state = "claimed"
	menu.refresh_view()
	check(labels(menu).contains("Gold: 35") and labels(menu).contains("Feathers × 2"), "claimed rewards use readable gold and item quantities")
	check(button(menu, "Search here") == null, "claimed receipt offers no remaining directive search")
	for lifecycle: String in ["abandoned", "suspended"]:
		game.orders_controller.state.orders.deckhand.state = lifecycle
		menu.refresh_view()
		check(labels(menu).contains("Status: " + lifecycle.capitalize()), "acknowledged %s order shows its lifecycle status" % lifecycle)
		check(button(menu, "Search here") == null and button(menu, "Search for cache here") == null, "%s order offers no live directive or cache actions" % lifecycle)
		check((button(menu, "Abandon order") != null) == (lifecycle == "suspended"), "only suspended unfinished order retains abandonment")
	game.orders_controller.state.enabled = false
	game.orders_controller.state.message = "Orders await validated content."
	menu.refresh_view()
	check(labels(menu).contains("Orders await validated content."), "disabled framework status is visible in the ledger")
	var open_tier := button(menu, "Open Deckhand order")
	check(open_tier != null and open_tier.disabled, "disabled framework cannot open sealed orders from ledger")
	menu.select_page(0)
	menu._inspect_item(item_name)
	open = button(menu, "Open order")
	check(open != null and open.disabled, "disabled framework cannot open sealed orders from inventory details")
	menu._inventory_context_input(click, item_name, source)
	open = button(game.context_menu, "Open order")
	check(open != null and open.disabled, "disabled framework cannot open sealed orders from inventory context menu")
	game.context_menu.dismiss()
	for page in range(5):
		menu.select_page(page)
		check(menu.selected_page == page and menu.body.get_child_count() > 0, "existing journal page %d remains available" % page)
	menu.select_page(5)
	await get_tree().process_frame
	await get_tree().process_frame
	check(menu.tabs.get_combined_minimum_size().x <= menu.panel.size.x - 52.0, "all six journal tabs fit the existing journal width")
	check(menu.body.size.y > 180.0, "ledger retains a usable scrollable reading area")
	if "--orders-ui-capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.save_png(OS.get_environment("TEMP").path_join("aetheria-orders-ledger.png"))
	game.queue_free()
	await get_tree().process_frame
	print("[Orders UI] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
