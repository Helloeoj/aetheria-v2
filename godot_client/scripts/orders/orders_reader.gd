extends RefCounted
## Inventory reading surface; it renders acknowledged state and never generates tasks.
const Book := preload("res://scripts/orders/order_book.gd")
var panel: PanelContainer
var tier := ""
var order_id := ""
var expected_generation := -1
var _scroll_position := 0

func is_open() -> bool:
	return is_instance_valid(panel) and panel.visible

func close() -> void:
	if is_instance_valid(panel):
		panel.hide()
	tier = ""
	order_id = ""
	expected_generation = -1
	_scroll_position = 0

func show_order(menu: Control, selected_tier: String, generation: int = -1) -> void:
	if selected_tier not in Book.TIERS:
		return
	tier = selected_tier
	expected_generation = generation
	order_id = ""
	_scroll_position = 0
	if not is_instance_valid(panel):
		panel = PanelContainer.new()
		panel.name = "OrderReader"
		panel.z_index = 20
		panel.add_theme_stylebox_override("panel",menu._card_style(true))
		menu.add_child(panel)
	panel.show()
	refresh(menu)

func refresh(menu: Control) -> void:
	if not is_open():
		return
	var previous := panel.find_child("OrderReaderScroll",true,false) as ScrollContainer
	if previous != null:
		_scroll_position = previous.scroll_vertical
	for child: Node in panel.get_children():
		panel.remove_child(child)
		child.queue_free()
	var viewport: Vector2 = menu.get_viewport_rect().size
	panel.size = Vector2(minf(690,viewport.x-32),minf(550,viewport.y-32))
	panel.position = (viewport-panel.size)*0.5
	var column: VBoxContainer = menu._column(panel,10)
	column.add_child(menu._label(Book.opened_name(tier),22,FantasyUI.GOLD,true))
	column.add_child(menu._label("Read from your backpack · Character-bound",12,FantasyUI.TEAL,true))
	var scroll := ScrollContainer.new()
	scroll.name = "OrderReaderScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var contents: VBoxContainer = menu._column(scroll,9)
	var controller: Object = menu._orders_controller()
	var view: Dictionary = controller.view() if controller != null else {}
	var order: Dictionary = view.get("orders",{}).get(tier,{})
	var held := int(menu._player().backpack.get(Book.opened_name(tier),0)) == 1
	var generation := int(view.get("generations",{}).get(tier,0))
	var activation_error: Dictionary = view.get("activation_errors",{}).get(tier,{})
	var acknowledged: bool = held and not order.is_empty() and order.get("state","") in Book.LIVE_STATES and generation == expected_generation
	if expected_generation >= 0 and not acknowledged and int(activation_error.get("generation",-1)) == expected_generation:
		contents.add_child(menu._label(String(activation_error.get("message","This Order could not be opened.")),15,FantasyUI.IVORY,true))
	elif expected_generation >= 0 and generation < expected_generation:
		contents.add_child(menu._label("Waiting for the server to open this Order…",15,FantasyUI.IVORY,true))
	elif expected_generation >= 0 and generation != expected_generation:
		contents.add_child(menu._label("This Order has changed. Close this sheet and read the item again.",15,FantasyUI.IVORY,true))
	elif not held or order.is_empty() or order.get("state","") not in Book.LIVE_STATES:
		contents.add_child(menu._label("This Order is no longer in your backpack. Check the Captain's Ledger for your collection and completed hunts.",15,FantasyUI.IVORY,true))
	elif not order_id.is_empty() and order.get("id","") != order_id:
		contents.add_child(menu._label("This is a different Order. Read its item again to view it.",15,FantasyUI.IVORY,true))
	else:
		order_id = String(order.id)
		if view.get("enabled",true) == false:
			contents.add_child(menu._label(String(view.get("message","Orders await validated content.")),13,FantasyUI.MUTED,true))
		menu._orders_ledger._build_order(menu,contents,controller,order)
	column.add_child(menu._action_button("Close",close))
	scroll.set_deferred("scroll_vertical",_scroll_position)
