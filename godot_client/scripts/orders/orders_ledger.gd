extends RefCounted
## Builds a read-only journal view. Every action goes through the shared controller.
const TIERS := ["deckhand", "smuggler", "corsair", "dread_captain"]
const TITLES := {"deckhand": "Deckhand", "smuggler": "Smuggler", "corsair": "Corsair", "dread_captain": "Dread Captain"}
var _answers := {}

func build(menu: Control) -> void:
	var column: VBoxContainer = menu._column(menu.body)
	column.add_child(menu._label("Captain's Ledger", 20, FantasyUI.GOLD))
	column.add_child(menu._label("Your exclusive reward collection and current hunts. Orders can also be read directly from your backpack.", 13, FantasyUI.MUTED, true))
	var scroll: ScrollContainer = menu._scroll("OrdersScroll")
	column.add_child(scroll)
	var contents: VBoxContainer = menu._column(scroll, 12)
	var controller: Object = menu._orders_controller()
	var view: Dictionary = controller.view() if controller != null else {}
	if view.get("enabled", true) == false:
		contents.add_child(menu._label(String(view.get("message", "Orders await validated content.")), 14, FantasyUI.GOLD, true))
	_build_collection(menu,contents,view)
	contents.add_child(menu._label("Current Orders",19,FantasyUI.GOLD))
	var orders: Dictionary = view.get("orders", {})
	for tier: String in TIERS:
		var title := String(TITLES[tier])
		var sealed_name := "Sealed %s's Order" % title
		var sealed := int(menu._player().backpack.get(sealed_name, 0))
		var opened := int(menu._player().backpack.get(title+"'s Order",0))
		var order: Dictionary = orders.get(tier, {})
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", menu._card_style(false))
		contents.add_child(card)
		var section: VBoxContainer = menu._column(card, 7)
		section.add_child(menu._label(title, 18, FantasyUI.GOLD))
		section.add_child(menu._label("Sealed: %d · Opened: %d · Total: %d" % [sealed,opened,sealed+opened], 12, FantasyUI.TEAL))
		section.add_child(menu._label("Completed: %d" % int(view.get("completed",{}).get(tier,0)),12,FantasyUI.TEAL))
		if order.is_empty():
			section.add_child(menu._label("No active orders", 13, FantasyUI.MUTED, true))
		else:
			if opened == 1 and order.get("state","") in ["active","cache_revealed","suspended"]:
				section.add_child(menu._action_button("Read order",menu._read_order.bind(tier)))
			_build_order(menu, section, controller, order)
		if sealed > 0 and controller != null:
			var open: Button = menu._action_button("Open %s order" % title, menu._open_sealed_order.bind(sealed_name))
			open.disabled = view.get("enabled", true) == false
			section.add_child(open)

func _build_collection(menu: Control, contents: VBoxContainer, view: Dictionary) -> void:
	contents.add_child(menu._label("Collection log",19,FantasyUI.GOLD))
	contents.add_child(menu._label("Records rewards earned from Dead Man's Orders. Buying, picking up or receiving an item does not fill this log.",12,FantasyUI.MUTED,true))
	var counts: Dictionary = view.get("collection",{})
	var entries := {}
	for item: Dictionary in GameData.items:
		if item.get("orders_exclusive",false) == true:
			entries[str(int(item.id))] = String(item.name)
	# Retain earned history even when a reward is later retired from the catalog.
	for id: String in counts:
		if not entries.has(id):
			var item := GameData.get_item(int(id))
			entries[id] = String(item.get("name","Retired reward #"+id))
	if entries.is_empty():
		contents.add_child(menu._label("No exclusive rewards have been added yet. Your collection will appear here when those items are implemented.",13,FantasyUI.MUTED,true))
		return
	var obtained := 0
	for id: String in entries:
		obtained += int(int(counts.get(id,0)) > 0)
	contents.add_child(menu._label("Collected: %d / %d" % [obtained,entries.size()],13,FantasyUI.TEAL))
	for id: String in entries:
		var count := int(counts.get(id,0))
		contents.add_child(menu._label("%s · Obtained: %d%s" % [entries[id],count," · Not yet obtained" if count == 0 else ""],14,FantasyUI.IVORY if count > 0 else FantasyUI.MUTED,true))

func _build_order(menu: Control, section: VBoxContainer, controller: Object, order: Dictionary) -> void:
	var actions_ready: bool = controller != null and controller.view().get("enabled",true) != false
	var order_id := String(order.get("id", ""))
	var state := String(order.get("state", "active"))
	var statuses := {"active": "Active", "cache_revealed": "Cache revealed", "claimed": "Claimed", "abandoned": "Abandoned", "suspended": "Suspended"}
	section.add_child(menu._label("Status: " + String(statuses.get(state, "Unavailable")), 13, FantasyUI.TEAL))
	section.add_child(menu._label("%d / %d directives completed" % [int(order.get("completed", 0)), int(order.get("total", 0))], 14, FantasyUI.IVORY))
	var available := 0
	for directive: Dictionary in order.get("directives", []):
		if String(directive.get("state", "sealed")) == "available":
			available += 1
	section.add_child(menu._label("Available directives: %d · Sealed directives: %d" % [available, int(order.get("sealed", 0))], 12, FantasyUI.TEAL, true))
	for directive: Dictionary in order.get("directives", []):
		var directive_state := String(directive.get("state", "sealed"))
		if directive_state not in ["available", "completed"]:
			continue
		section.add_child(HSeparator.new())
		section.add_child(menu._label(("Completed: " if directive_state == "completed" else "") + String(directive.get("text", "")), 14, FantasyUI.IVORY, true))
		if directive_state == "completed":
			continue
		if state != "active":
			continue
		var kind := String(directive.get("kind", ""))
		var requirements: Dictionary = directive.get("requirements", {})
		var requirement_text := _requirement_text(requirements, kind)
		if not requirement_text.is_empty():
			section.add_child(menu._label(requirement_text, 12, FantasyUI.TEAL, true))
		if kind in ["riddle", "search", "equipment", "cipher"]:
			var directive_id := String(directive.get("id", ""))
			var answer: LineEdit
			if kind == "cipher":
				answer = LineEdit.new()
				answer.name = "CipherAnswer"
				answer.placeholder_text = "Enter the decoded answer"
				answer.max_length = 160
				answer.custom_minimum_size.y = 40
				var key := order_id + ":" + directive_id
				answer.text = String(_answers.get(key, ""))
				answer.text_changed.connect(func(value: String) -> void: _answers[key] = value)
				section.add_child(answer)
			var search: Button = menu._action_button("Search here", func() -> void:
				if controller != null:
					controller.search(order_id, directive_id, answer.text if is_instance_valid(answer) else ""))
			search.disabled = not actions_ready
			section.add_child(search)
		else:
			section.add_child(menu._label("Progress updates as you complete this activity in the world.", 12, FantasyUI.MUTED, true))
	var cache: Dictionary = order.get("cache", {})
	if not cache.is_empty() and state == "cache_revealed":
		section.add_child(HSeparator.new())
		section.add_child(menu._label(String(cache.get("label", "Revealed cache")), 16, FantasyUI.GOLD, true))
		section.add_child(menu._label(String(cache.get("hint", "")), 13, FantasyUI.IVORY, true))
		var claim: Button = menu._action_button("Search for cache here", func() -> void:
			if controller != null:
				controller.claim(order_id))
		claim.disabled = not actions_ready
		section.add_child(claim)
	if state == "claimed":
		section.add_child(menu._label("Cache claimed", 15, FantasyUI.TEAL))
		if order.has("rewards"):
			section.add_child(menu._label(_reward_text(order.rewards), 13, FantasyUI.IVORY, true))
	elif state != "abandoned":
		var abandon: Button = menu._action_button("Abandon order", _confirm_abandon.bind(menu, controller, order_id))
		abandon.disabled = controller == null
		section.add_child(abandon)

func _confirm_abandon(menu: Control, controller: Object, order_id: String) -> void:
	var previous := menu.get_node_or_null("AbandonOrderConfirmation")
	if previous != null:
		menu.remove_child(previous)
		previous.queue_free()
	var dialog := ConfirmationDialog.new()
	dialog.name = "AbandonOrderConfirmation"
	dialog.title = "Abandon order?"
	dialog.dialog_text = "Abandon this order and lose its current progress?"
	dialog.ok_button_text = "Abandon order"
	dialog.confirmed.connect(func() -> void:
		if is_instance_valid(controller):
			controller.abandon(order_id, true))
	menu.add_child(dialog)
	dialog.popup_centered(Vector2i(420, 150))

func _requirement_text(requirements: Dictionary, kind: String) -> String:
	var parts: PackedStringArray = []
	var skill := String(requirements.get("skill", ""))
	if not skill.is_empty():
		parts.append("Requires %s %d" % [skill.capitalize(), int(requirements.get("level", 1))])
	var equipment: Variant = requirements.get("equipment", "")
	var item_label := "Target item: " if kind in ["fishing", "cooking"] else "Equipment: "
	if equipment is Array:
		if not equipment.is_empty():
			parts.append(item_label + ", ".join(equipment))
	elif not str(equipment).is_empty():
		parts.append(item_label + str(equipment))
	return " · ".join(parts)

func _reward_text(rewards: Variant) -> String:
	if rewards is Dictionary:
		var parts: PackedStringArray = []
		if int(rewards.get("gold", 0)) > 0:
			parts.append("Gold: %d" % int(rewards.gold))
		for item: Dictionary in rewards.get("items", []):
			parts.append("%s × %d" % [String(item.get("item_name", "Item")), int(item.get("count", 0))])
		return "\n".join(parts)
	return str(rewards)
