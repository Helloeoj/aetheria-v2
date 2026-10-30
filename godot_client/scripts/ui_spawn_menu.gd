class_name SpawnMenu
extends Control

var game: Node
var db: Dictionary = {}
var input_text := ""
var status_text := "Type monster ID and press Enter to spawn."
var page_index := 0
const PAGE_SIZE := 10

func configure(game_ref: Node, monster_db: Dictionary) -> void:
	game = game_ref
	db = monster_db
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func toggle() -> void:
	visible = not visible
	status_text = "Type monster ID and press Enter to spawn."
	input_text = ""
	page_index = 0
	queue_redraw()

func on_key_press(event: InputEventKey) -> bool:
	if not visible:
		return false
	if event.keycode == KEY_ESCAPE or event.keycode == KEY_F5:
		visible = false
		return true
	if event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
		var last_page := maxi(0, ceili(float(db.size()) / PAGE_SIZE) - 1)
		page_index = clampi(page_index + (1 if event.keycode == KEY_PAGEDOWN else -1), 0, last_page)
		queue_redraw()
		return true
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		if not input_text.is_valid_int():
			status_text = "Invalid ID (must be integer)."
		else:
			var monster_id := int(input_text)
			if not db.has(monster_id):
				status_text = "Unknown monster ID %d." % monster_id
			elif game.spawn_monster_by_id(monster_id):
				status_text = "Spawned monster %d within 3 tiles." % monster_id
			else:
				status_text = "No free walkable tile within 3 tiles. Move to a clearer spot."
		input_text = ""
		queue_redraw()
		return true
	if event.keycode == KEY_BACKSPACE:
		input_text = input_text.left(maxi(0, input_text.length() - 1))
		queue_redraw()
		return true
	if event.unicode >= 48 and event.unicode <= 57:
		input_text += String.chr(event.unicode)
		queue_redraw()
		return true
	return false

func _draw() -> void:
	if not visible:
		return
	var panel := Rect2(80, 300, 680, 360)
	draw_rect(panel, Color(0.18, 0.20, 0.22))
	draw_string(ThemeDB.fallback_font, Vector2(100, 340), "DEV SPAWN MENU (F5 to close)", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.75, 0.0))
	draw_string(ThemeDB.fallback_font, Vector2(100, 390), "Monster ID:  " + (input_text if not input_text.is_empty() else "_"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(100, 620), status_text, HORIZONTAL_ALIGNMENT_LEFT, 620, 12, Color.LIGHT_GRAY)
	draw_string(ThemeDB.fallback_font, Vector2(100, 440), "PageUp / PageDown: browse monsters", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.LIGHT_GRAY)
	draw_string(ThemeDB.fallback_font, Vector2(100, 465), "F7: visual sprite viewer + spawn", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.LIGHT_GRAY)
	var page_count := maxi(1, ceili(float(db.size()) / PAGE_SIZE))
	draw_string(ThemeDB.fallback_font, Vector2(460, 390), "Monsters (%d / %d):" % [page_index + 1, page_count], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	var ids: Array[int] = []
	for key: Variant in db.keys():
		ids.append(int(key))
	ids.sort()
	var row := 0
	for index in range(page_index * PAGE_SIZE, mini(ids.size(), (page_index + 1) * PAGE_SIZE)):
		var monster_id: int = ids[index]
		var monster: Dictionary = db[monster_id]
		draw_string(ThemeDB.fallback_font, Vector2(460, 420 + row * 18), "[%d] %s" % [monster_id, String(monster.get("name", "Monster"))], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.LIGHT_GRAY)
		row += 1
