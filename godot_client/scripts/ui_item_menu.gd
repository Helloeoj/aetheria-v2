class_name ItemMenu
extends Control

var game: Node
var db: Dictionary = {}
var visible_input := ""
var status_text := "Type item ID and press ENTER to give+equip that item."
var page_index := 0
var page_size := 20
var item_ids: Array[int] = []

func configure(game_ref: Node, item_db: Dictionary) -> void:
	game = game_ref
	db = item_db
	item_ids.clear()
	for key: Variant in db.keys():
		item_ids.append(int(key))
	item_ids.sort()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func toggle() -> void:
	visible = not visible
	status_text = "Type item ID and press ENTER to give+equip that item."
	visible_input = ""
	page_index = 0
	queue_redraw()

func on_key_press(event: InputEventKey) -> bool:
	if not visible:
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
				status_text = game.player.give_and_equip(item)
				game.inventory_menu._refresh_combat_view()
			visible_input = ""
		queue_redraw()
		return true
	if event.keycode == KEY_PAGEUP:
		page_index = maxi(0, page_index - 1)
		queue_redraw()
		return true
	if event.keycode == KEY_PAGEDOWN:
		var max_page := maxi(0, (item_ids.size() - 1) / page_size)
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
	draw_string(ThemeDB.fallback_font, Vector2(60, 110), "Type item ID and press ENTER to give+equip. Locked gear stays in your backpack.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.LIGHT_GRAY)
	draw_string(ThemeDB.fallback_font, Vector2(60, 150), "Item ID:  " + (visible_input if not visible_input.is_empty() else "_"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(60, viewport.y - 80), status_text, HORIZONTAL_ALIGNMENT_LEFT, viewport.x - 120, 12, Color.LIGHT_GRAY)
	var page_count := maxi(1, ceili(float(item_ids.size()) / float(page_size)))
	draw_string(ThemeDB.fallback_font, Vector2(60, 190), "Items (PageUp/PageDown to scroll) — Page %d/%d" % [page_index + 1, page_count], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	var start := page_index * page_size
	for row in range(page_size):
		var index := start + row
		if index >= item_ids.size():
			break
		var item: Dictionary = db[item_ids[index]]
		var requirement := EquipmentProgression.requirement_text(item)
		var unmet := EquipmentProgression.unmet_requirement_text(game.player, item)
		var line := "[%d] %s - %s" % [item_ids[index], String(item.get("name", "Item")), requirement]
		if not unmet.is_empty():
			line += " [Locked]"
		draw_string(ThemeDB.fallback_font, Vector2(60, 220 + row * 18), line, HORIZONTAL_ALIGNMENT_LEFT, viewport.x - 120, 12, Color.GOLD if not unmet.is_empty() else Color.LIGHT_GRAY)
