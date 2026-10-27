class_name ItemMenu
extends Control

const Smithing = preload("res://scripts/smithing_catalog.gd")
const Crafting = preload("res://scripts/crafting_service.gd")
var game: Node
var db: Dictionary = {}
var visible_input := ""
var status_text := "Type item ID and press ENTER to give+equip that item."
var page_index := 0
var page_size := 20
var item_ids: Array[int] = []
var display_ids: Array[int] = []
var view_picker: OptionButton
var quantity: SpinBox

func configure(game_ref: Node, item_db: Dictionary) -> void:
	game = game_ref
	db = item_db
	preload("res://scripts/crafting_menu_layer.gd").mount(self, game.ui_root)
	item_ids.clear()
	for key: Variant in db.keys():
		item_ids.append(int(key))
	item_ids.sort()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	view_picker = OptionButton.new()
	view_picker.position = Vector2(500, 125)
	view_picker.size = Vector2(230, 34)
	view_picker.focus_mode = Control.FOCUS_NONE
	view_picker.add_item("Smithing items")
	view_picker.add_item("All items")
	view_picker.item_selected.connect(_refresh_filter)
	add_child(view_picker)
	quantity = SpinBox.new()
	quantity.position = Vector2(760, 125)
	quantity.size = Vector2(200, 34)
	quantity.min_value = 1
	quantity.max_value = 100
	quantity.value = 1
	quantity.prefix = "Quantity: "
	quantity.get_line_edit().text_submitted.connect(func(_text: String) -> void: quantity.get_line_edit().release_focus())
	add_child(quantity)
	gui_input.connect(_on_gui_input)
	_refresh_filter()
	visible = false

func toggle() -> void:
	visible = not visible
	status_text = "Click an item or type its ID and press ENTER."
	visible_input = ""
	page_index = 0
	queue_redraw()

func _refresh_filter(_selected: int = 0) -> void:
	display_ids = Smithing.item_ids(db) if view_picker.selected == 0 else item_ids.duplicate()
	page_index = 0
	queue_redraw()

func _on_gui_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var rows := Rect2(60, 203, FantasyUI.viewport_size(self).x - 120, page_size * 18)
	if not rows.has_point(event.position): return
	quantity.get_line_edit().release_focus()
	var row := int((event.position.y - rows.position.y) / 18)
	var index := page_index * page_size + row
	if index < display_ids.size():
		_give_item(db[display_ids[index]])
		queue_redraw()
	accept_event()

func _input(event: InputEvent) -> void:
	# Closing must also work while the native quantity editor has keyboard focus.
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_F6]:
		hide()
		get_viewport().set_input_as_handled()

func _give_item(item: Dictionary) -> void:
	if Network.online():
		status_text = "Developer item grants are available offline only."
		return
	if item.get("material") == "Starforged":
		status_text = "Starforged equipment is drop-only; its Ore and Ingot are retired."
		return
	if view_picker.selected == 0 and Smithing.category(item).is_empty():
		status_text = "This item is outside the Smithing list."
		return
	var name_key := GameData.canonical_item_name(str(item.get("name", "")))
	if name_key.is_empty(): return
	var count := clampi(int(quantity.value), 1, 100)
	var available := Crafting._available(game.player.backpack, name_key)
	if available < 0 or available > Crafting.MAX_COUNT - count:
		status_text = "That quantity would exceed a supported inventory stack."
		return
	if item.get("slot") != null and not _equipment_headroom(item, name_key, available + count):
		status_text = "There is no room to return the currently equipped item."
		return
	if item.get("slot") == null:
		game.player.add_item(name_key, count)
		status_text = "Added %d %s." % [count, name_key]
	else:
		if count > 1: game.player.add_item(name_key, count - 1)
		status_text = game.player.give_and_equip(item)
		game.inventory_menu._refresh_combat_view()

func _equipment_headroom(item: Dictionary, name_key: String, granted_stack: int) -> bool:
	if not EquipmentProgression.can_equip(game.player, item): return true
	var slot := str(item.get("slot", ""))
	var slots: Array[String] = [slot]
	var returns := {}
	if slot == "weapon" and EquipmentUtils.is_two_handed(item): slots.append("shield")
	if slot == "shield" and EquipmentUtils.is_two_handed(game.player.equipment.get("weapon", {})): return true
	if slot == "ring":
		if game.player.equipment.ring1.is_empty() or game.player.equipment.ring2.is_empty(): return true
		slots = ["ring1"]
	if slot == "quiver" and not game.player.quiver_item.is_empty():
		var old_name := str(game.player.quiver_item.get("name", ""))
		var old_count := int(game.player.quiver_amount)
		if old_count < 0: return false
		if old_name == name_key: return old_count <= Crafting.MAX_COUNT - granted_stack
		returns[GameData.canonical_item_name(old_name)] = old_count
	for old_slot: String in slots:
		var worn: Dictionary = game.player.equipment.get(old_slot, {})
		if worn.is_empty(): continue
		var old_name := GameData.canonical_item_name(str(worn.get("name", "")))
		returns[old_name] = int(returns.get(old_name, 0)) + 1
	for old_name: String in returns:
		# The existing equip path returns weapon/armor before consuming its
		# replacement. Reserve temporary headroom even for the same item.
		var current := granted_stack if old_name == name_key else Crafting._available(game.player.backpack, old_name)
		if current < 0 or current > Crafting.MAX_COUNT - int(returns[old_name]): return false
	return true

func on_key_press(event: InputEventKey) -> bool:
	if not visible or not event.pressed or event.echo:
		return false
	if event.keycode == KEY_ESCAPE or event.keycode == KEY_F6:
		visible = false
		return true
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		if not visible_input.is_valid_int():
			status_text = "Invalid ID (must be integer)."
		else:
			var item_id := int(visible_input)
			var item: Dictionary = db.get(item_id, {})
			if item.is_empty():
				status_text = "No item with ID %d" % item_id
			else:
				_give_item(item)
			visible_input = ""
		queue_redraw()
		return true
	if event.keycode == KEY_PAGEUP:
		page_index = maxi(0, page_index - 1)
		queue_redraw()
		return true
	if event.keycode == KEY_PAGEDOWN:
		var max_page := maxi(0, (display_ids.size() - 1) / page_size)
		page_index = mini(max_page, page_index + 1)
		queue_redraw()
		return true
	if event.keycode == KEY_BACKSPACE:
		visible_input = visible_input.left(maxi(0, visible_input.length() - 1))
		queue_redraw()
		return true
	if event.unicode >= 48 and event.unicode <= 57:
		visible_input += String.chr(event.unicode)
		queue_redraw()
		return true
	return false

func _draw() -> void:
	if not visible:
		return
	var viewport := FantasyUI.viewport_size(self)
	var panel := Rect2(40, 40, viewport.x - 80, viewport.y - 80)
	draw_rect(panel, Color(0.18, 0.20, 0.22))
	draw_rect(panel, Color.WHITE, false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(60, 80), "ITEM DEV MENU (F6 to close)", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(60, 110), "Click a row or type its ID + ENTER. Gear equips when requirements are met; locked gear stays in your backpack.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.LIGHT_GRAY)
	draw_string(ThemeDB.fallback_font, Vector2(60, 150), "Item ID:  " + (visible_input if not visible_input.is_empty() else "_"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(60, viewport.y - 80), status_text, HORIZONTAL_ALIGNMENT_LEFT, viewport.x - 120, 12, Color.LIGHT_GRAY)
	var page_count := maxi(1, ceili(float(display_ids.size()) / float(page_size)))
	draw_string(ThemeDB.fallback_font, Vector2(60, 190), "Items (PageUp/PageDown to scroll) — Page %d/%d" % [page_index + 1, page_count], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	var start := page_index * page_size
	for row in range(page_size):
		var index := start + row
		if index >= display_ids.size():
			break
		var item: Dictionary = db[display_ids[index]]
		var requirement := EquipmentProgression.requirement_text(item)
		var unmet := EquipmentProgression.unmet_requirement_text(game.player, item)
		var line := "[%d] %s - %s" % [display_ids[index], String(item.get("name", "Item")), requirement]
		if not unmet.is_empty():
			line += " [Locked]"
		var icon := ItemVisualLibrary.texture(str(item.get("name", "")))
		if icon != null: draw_texture_rect(icon, Rect2(60, 204 + row * 18, 16, 16), false)
		draw_string(ThemeDB.fallback_font, Vector2(84, 220 + row * 18), line, HORIZONTAL_ALIGNMENT_LEFT, viewport.x - 144, 12, Color.GOLD if not unmet.is_empty() else Color.LIGHT_GRAY)
