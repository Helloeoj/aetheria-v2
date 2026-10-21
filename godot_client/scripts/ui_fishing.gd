class_name FishingPanel
extends Control
## Aetheria lake artwork and pixel-styled tackle, driven by the world session.
const PANEL_SIZE := Vector2(1050, 620)
const WATER := Rect2(300, 102, 720, 366)
const INK := FantasyUI.INK
const GOLD := FantasyUI.GOLD
const MUTED := FantasyUI.MUTED
const LAKE_ART_PATH := "res://Assets/UI/Fishing/aetheria_fishing_lake.png"
var game: Node
var session: FishingSession
var spot: FishingSpot
var origin := Vector2.ZERO
var steering := 0.0
var keyboard_steering := 0.0
var clock := 0.0
var action_button: Button
var rod_picker: OptionButton
var bait_picker: OptionButton
var status: Label
var gear_label: Label
var last_reward := false
var pale_slots: Array[Button] = []
var empty_pale_button: Button
var _last_pale: Array[String] = []
var _lake_texture: Texture2D
var _panel_frame: StyleBox
var _meter_frame: StyleBoxFlat

func configure(game_ref: Node) -> void:
	game = game_ref
	theme = FantasyUI.make_theme()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_panel_frame = FantasyUI.frame_style()
	_meter_frame = FantasyUI.box(INK, Color("4a5d70"))
	if ResourceLoader.exists(LAKE_ART_PATH):
		_lake_texture = load(LAKE_ART_PATH)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	rod_picker = OptionButton.new()
	for item_name: String in FishingSession.RODS:
		rod_picker.add_item(item_name)
	rod_picker.item_selected.connect(func(index: int) -> void: session.rod = FishingSession.RODS[index])
	add_child(rod_picker)
	bait_picker = OptionButton.new()
	for item_name: String in FishingSession.BAITS:
		bait_picker.add_item(item_name.trim_suffix(" Fish Food") + " Food")
	bait_picker.item_selected.connect(func(index: int) -> void: session.bait = FishingSession.BAITS[index])
	add_child(bait_picker)
	gear_label = _label(Vector2(26, 229), Vector2(250, 54), 12, MUTED)
	gear_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for slot in range(PlayerState.FISHING_PALE_SIZE):
		var button := Button.new()
		button.name = "FishingPaleSlot%d" % slot
		button.custom_minimum_size = Vector2(64, 64)
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_constant_override("icon_max_width", 44)
		button.pressed.connect(_show_pale_actions.bind(slot))
		button.gui_input.connect(_pale_slot_input.bind(slot))
		pale_slots.append(button)
		add_child(button)
	empty_pale_button = Button.new()
	empty_pale_button.name = "EmptyFishingPale"
	empty_pale_button.text = "Empty Fishing Pale to inventory"
	empty_pale_button.add_theme_font_size_override("font_size", 13)
	empty_pale_button.pressed.connect(empty_pale)
	add_child(empty_pale_button)
	status = _label(Vector2(312, 535), Vector2(446, 42), 15, FantasyUI.IVORY)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_button = Button.new()
	action_button.custom_minimum_size = Vector2(230, 44)
	action_button.pressed.connect(_act)
	add_child(action_button)
	var close_button := Button.new()
	close_button.name = "LeaveFishing"
	close_button.text = "Leave [Esc]"
	close_button.pressed.connect(close)
	add_child(close_button)
	var skills_button := Button.new()
	skills_button.name = "EditFishingSkills"
	skills_button.text = "Skills [K]"
	skills_button.icon = FantasyUI.icon("skills")
	skills_button.add_theme_constant_override("icon_max_width", 18)
	skills_button.pressed.connect(game.toggle_skill_debug_panel)
	add_child(skills_button)
	_layout()

func _label(at: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = at
	label.size = dimensions
	label.set_meta("base_position", at)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func _layout() -> void:
	if game == null:
		return
	size = game.ui_root.size
	origin = (size - PANEL_SIZE) * 0.5
	for label: Label in [status, gear_label]:
		label.position = origin + Vector2(label.get_meta("base_position"))
	rod_picker.position = origin + Vector2(26, 122)
	rod_picker.size = Vector2(250, 38)
	bait_picker.position = origin + Vector2(26, 184)
	bait_picker.size = Vector2(250, 38)
	for slot in range(pale_slots.size()):
		pale_slots[slot].position = origin + Vector2(49 + (slot % 3) * 70, 310 + floori(slot / 3.0) * 70)
		pale_slots[slot].size = Vector2(64, 64)
	empty_pale_button.position = origin + Vector2(26, 524)
	empty_pale_button.size = Vector2(250, 38)
	action_button.position = origin + Vector2(790, 534)
	action_button.size = Vector2(230, 38)
	var leave := get_node("LeaveFishing") as Button
	leave.position = origin + Vector2(875, 20)
	leave.size = Vector2(145, 36)
	var skills_button := get_node("EditFishingSkills") as Button
	skills_button.position = origin + Vector2(710, 20)
	skills_button.size = Vector2(150, 36)

func open(at_spot: FishingSpot) -> void:
	spot = at_spot
	session = FishingSession.new(game.player)
	last_reward = false
	steering = 0.0
	keyboard_steering = 0.0
	rod_picker.select(maxi(0, FishingSession.RODS.find(session.rod)))
	bait_picker.select(maxi(0, FishingSession.BAITS.find(session.bait)))
	for index in range(FishingSession.RODS.size()):
		rod_picker.set_item_disabled(index, not session.available(FishingSession.RODS[index]))
	for index in range(FishingSession.BAITS.size()):
		bait_picker.set_item_disabled(index, not session.available(FishingSession.BAITS[index]))
	show()
	_layout()
	_refresh_pale()

func close() -> void:
	# Switching to skill tools must release any native selector popup as well.
	rod_picker.get_popup().hide()
	bait_picker.get_popup().hide()
	game.context_menu.dismiss()
	if session != null:
		session.close()
	if is_instance_valid(spot):
		spot.fishing_session = null
	hide()
	keyboard_steering = 0.0
	game._reset_held_movement()
	game._refresh_character_ui()

func _refresh_pale() -> void:
	if _last_pale == game.player.fishing_pale:
		return
	_last_pale.assign(game.player.fishing_pale)
	for slot in range(pale_slots.size()):
		var fish_name: String = game.player.fishing_pale[slot]
		var button := pale_slots[slot]
		# The inventory-state item image is shared with the backpack, including
		# future authored art; the pale has no separate fish artwork or stack.
		button.icon = ItemVisualLibrary.texture(fish_name) if not fish_name.is_empty() else null
		button.disabled = fish_name.is_empty()
		button.tooltip_text = "Empty slot" if fish_name.is_empty() else fish_name + "\nClick to move to inventory or drop to ground."
	empty_pale_button.disabled = game.player.fishing_pale_count() == 0
	queue_redraw()

func _pale_slot_input(event: InputEvent, slot: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		pale_slots[slot].accept_event()
		_show_pale_actions(slot)

func _show_pale_actions(slot: int) -> void:
	if slot < 0 or slot >= game.player.fishing_pale.size():
		return
	var fish_name: String = game.player.fishing_pale[slot]
	if fish_name.is_empty():
		return
	keyboard_steering = 0.0
	var entries: Array[Dictionary] = [
		{"label": "Move to inventory", "action": move_pale_catch.bind(slot, fish_name)},
		{"label": "Drop to ground", "action": drop_pale_catch.bind(slot, fish_name)}
	]
	var anchor := pale_slots[slot].get_global_transform_with_canvas() * Vector2(64, 0)
	game.context_menu.show_options(fish_name, entries, anchor)

func move_pale_catch(slot: int, expected_name: String) -> void:
	if slot < 0 or slot >= game.player.fishing_pale.size() or game.player.fishing_pale[slot] != expected_name:
		return
	if game.player.move_fishing_catch_to_inventory(slot):
		session.message = "Moved %s to inventory." % expected_name
		_refresh_pale()
		game.inventory_menu.refresh_view()

func drop_pale_catch(slot: int, expected_name: String) -> void:
	if game.drop_fishing_pale_item(slot, expected_name):
		session.message = "Dropped %s on the ground." % expected_name
		_refresh_pale()
	else:
		session.message = "Could not drop that fish. It is still in your Fishing Pale."

func empty_pale() -> void:
	game.context_menu.dismiss()
	var moved: int = game.player.empty_fishing_pale_to_inventory()
	if moved > 0:
		session.message = "Moved %d fish from Fishing Pale to inventory." % moved
		_refresh_pale()
		game.inventory_menu.refresh_view()

func _act() -> void:
	if session == null:
		return
	last_reward = false if not session.active_cast() else last_reward
	session.act()
	get_viewport().gui_release_focus()

func handle_key(event: InputEventKey) -> void:
	if event.keycode == KEY_ESCAPE and event.pressed:
		close()
	elif event.keycode in [KEY_SPACE, KEY_ENTER] and event.pressed and not event.echo:
		_act()
	elif event.keycode in [KEY_A, KEY_LEFT, KEY_D, KEY_RIGHT]:
		if event.pressed:
			keyboard_steering = -1.0 if event.keycode in [KEY_A, KEY_LEFT] else 1.0
		else:
			keyboard_steering = 0.0

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var at: Vector2 = event.position - origin
		if WATER.has_point(at):
			steering = clampf((at.x - WATER.get_center().x) / (WATER.size.x * 0.45), -1.0, 1.0)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if WATER.has_point(event.position - origin):
			_act()
	accept_event()

func _process(delta: float) -> void:
	if not visible or session == null:
		return
	clock += delta
	_layout()
	if game.player.current_hp <= 0 or game.player.current_hp < session.start_hp or game.player.get_position().distance_to(session.start_position) > 0.2:
		close()
		game.show_fishing_notice("Fishing interrupted by damage or movement.")
		return
	session.advance(delta, keyboard_steering if keyboard_steering != 0.0 else steering)
	spot.fishing_session = session
	if session.state == FishingSession.State.CAUGHT and not last_reward:
		last_reward = true
		game.skill_training_session.record_event({"type": "skill_experience_gained", "skill": "fishing", "experience_gained": session.reward_xp})
		game._refresh_character_ui()
	status.text = session.message
	_refresh_pale()
	var locked := session.active_cast()
	rod_picker.disabled = locked
	bait_picker.disabled = locked
	var bait_grade := int(GameData.get_item_by_name(session.bait).get("tier", 1))
	var rod_data := GameData.get_item_by_name(session.rod)
	var feet := session.projected_cast_distance() if session.state in [FishingSession.State.READY, FishingSession.State.POWER] else session.distance
	gear_label.text = "Fishing %d  /  Food left: %d\nRange now %.1f / %d ft\nControl %.2f  /  Resist %.1f%%" % [game.player.get_skill_level("fishing"), int(game.player.backpack.get(session.bait, 0)), session.effective_max_cast_distance(), int(rod_data.get("cast_distance", 60)), session.input_strength(), (1.0 - 1.0 / session.skill_pull_tolerance()) * 100]
	rod_picker.tooltip_text = "%s\nRequires Fishing %d\nRange now %.1f ft; full %d ft at Fishing %d\n%.2f input strength; %.2f boundary width" % [session.rod, int(rod_data.get("fishing_level", 1)), session.effective_max_cast_distance(), int(rod_data.get("cast_distance", 60)), session.cast_mastery_level(), session.input_strength(), session.boundary()]
	bait_picker.tooltip_text = "Only fish requiring grade %d bait can bite. Other grades are excluded. Fishing level and minimum distance also apply.\nAt %.1f ft: %d eligible species. Long casts favor rarer fish within this grade." % [bait_grade, feet, session.catch_pool(feet).size()]
	match session.state:
		FishingSession.State.POWER: action_button.text = "Set power [Space]"
		FishingSession.State.BITE: action_button.text = "HOOK! [Space]"
		FishingSession.State.FIGHT: action_button.text = "Pull with mouse / A D"
		FishingSession.State.CASTING, FishingSession.State.WAITING: action_button.text = "Watch the bobber..."
		_: action_button.text = "Cast again [Space]" if session.state != FishingSession.State.READY else "Cast [Space]"
	action_button.disabled = session.state in [FishingSession.State.CASTING, FishingSession.State.WAITING, FishingSession.State.FIGHT]
	queue_redraw()

func _text(at: Vector2, text: String, font_size: int = 16, color: Color = Color("eee6ce")) -> void:
	var font := FantasyUI.display_font() if font_size >= 18 else get_theme_default_font()
	draw_string(font, origin + at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw() -> void:
	if session == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.04, 0.07, 0.86))
	draw_style_box(_frame(), Rect2(origin, PANEL_SIZE))
	_text(Vector2(26, 47), "Aetheria / Fishing", 28, GOLD)
	_text(Vector2(26, 76), spot.spot_name + "   /   A quiet moment by the water", 14, MUTED)
	draw_line(origin + Vector2(26, 88), origin + Vector2(1024, 88), Color("66533f"), 1)
	draw_line(origin + Vector2(287, 102), origin + Vector2(287, 566), Color("4a5d70"), 1)
	_text(Vector2(26, 112), "FISHING POLE", 12, GOLD)
	_text(Vector2(26, 181), "FISH FOOD (BAIT)", 12, GOLD)
	draw_texture_rect(FantasyUI.icon("bag"), Rect2(origin + Vector2(26, 287), Vector2(18, 18)), false)
	_text(Vector2(51, 303), "Fishing Pale  %d / %d" % [game.player.fishing_pale_count(), PlayerState.FISHING_PALE_SIZE], 18, GOLD)
	var lake := WATER.position + origin
	_draw_lake(lake)
	var active := session.state in [FishingSession.State.CASTING, FishingSession.State.WAITING, FishingSession.State.BITE, FishingSession.State.FIGHT]
	var water_depth := session.bobber_water_depth()
	var bobber := lake + Vector2(360 + session.lateral * 285, lerpf(328, 135, water_depth))
	var rod_base := lake + Vector2(630, 360)
	var rod_tip := lake + Vector2(480 + steering * 46, 148)
	if active:
		if session.state == FishingSession.State.CASTING:
			bobber = rod_tip.lerp(bobber, clampf(session.elapsed / 0.65, 0.0, 1.0))
		bobber.y += roundf(sin(clock * 4) * 2)
		_draw_fishing_line(rod_tip, bobber)
	_draw_rod(rod_base, rod_tip)
	if session.state == FishingSession.State.FIGHT:
		for side: float in [-1.0, 1.0]:
			var x := 360 + side * session.boundary() * 285
			var top := lake + Vector2(x, 120)
			var bottom := lake + Vector2(x, 352)
			draw_line(top, bottom, Color(0.06, 0.09, 0.12, 0.85), 6)
			draw_line(top, bottom, Color("f18c7f"), 2)
			draw_rect(Rect2(top - Vector2(4, 1), Vector2(8, 3)), Color("f18c7f"))
			draw_rect(Rect2(bottom - Vector2(4, 1), Vector2(8, 3)), Color("f18c7f"))
		_draw_lake_banner("Keep the bobber inside the red lines", "Fish strength %.2f / pull %.2f" % [float(session.fish.get("fish_strength", 0.65)), absf(session.effective_fish_pull())])
	elif session.state == FishingSession.State.POWER:
		_draw_lake_banner("Set your cast", "Click / Space to stop the meter. 95-100% power reaches your full range.")
	elif session.state == FishingSession.State.BITE:
		_draw_lake_banner("A fish is biting!", "Click the water or press Space to hook it.")
	if active:
		_draw_bobber(bobber)
	if session.state == FishingSession.State.BITE:
		var badge := bobber + Vector2(0, -36)
		draw_rect(Rect2(badge - Vector2(16, 20), Vector2(32, 36)), INK)
		draw_rect(Rect2(badge - Vector2(13, 17), Vector2(26, 30)), GOLD)
		draw_string(FantasyUI.display_font(), badge + Vector2(-5, 7), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, INK)
	_draw_meter()
	draw_style_box(_meter_frame, Rect2(origin + Vector2(300, 530), Vector2(470, 48)))
	draw_line(origin + Vector2(26, 578), origin + Vector2(1024, 578), Color("4a5d70"), 1)
	_text(Vector2(26, 600), "Click water / Space: cast & hook   |   Mouse left or right / A D: pull   |   Esc: leave", 13, MUTED)

func _draw_lake(lake: Vector2) -> void:
	draw_rect(Rect2(lake - Vector2(3, 3), WATER.size + Vector2(6, 6)), Color("66533f"))
	if _lake_texture != null:
		draw_texture_rect(_lake_texture, Rect2(lake, WATER.size), false)
	else:
		draw_rect(Rect2(lake, WATER.size), Color("234c63"))
	# Sparse stepped glints animate above the environment without scanline rows.
	for index in range(16):
		var x := 32.0 + fmod(float(index) * 127.0 + floorf(sin(clock * 0.7 + index) * 4.0), 652.0)
		var y := 134.0 + fmod(float(index) * 43.0, 198.0)
		var alpha := 0.06 + maxf(0.0, sin(clock * 1.2 + index)) * 0.12
		draw_rect(Rect2((lake + Vector2(x, y)).round(), Vector2(6 + (index % 3) * 2, 1)), Color(0.77, 0.93, 0.94, alpha))

func _draw_lake_banner(title: String, detail: String) -> void:
	var at := WATER.position + Vector2(12, 12)
	draw_rect(Rect2(origin + at, Vector2(696, 48)), Color(0.06, 0.08, 0.12, 0.90))
	draw_rect(Rect2(origin + at, Vector2(3, 48)), GOLD)
	_text(at + Vector2(14, 21), title, 18, FantasyUI.IVORY)
	_text(at + Vector2(14, 39), detail, 12, MUTED)

func _draw_fishing_line(tip: Vector2, bobber: Vector2) -> void:
	var points := PackedVector2Array()
	var control := tip.lerp(bobber, 0.5) + Vector2(0, 2 if session.state == FishingSession.State.FIGHT else 12)
	for index in range(13):
		var t := index / 12.0
		points.append((tip * pow(1.0 - t, 2) + control * (2.0 * (1.0 - t) * t) + bobber * t * t).round())
	draw_polyline(points, Color(0.06, 0.10, 0.14, 0.65), 3)
	draw_polyline(points, Color("e5e4c6"), 1)

func _draw_rod(base: Vector2, tip: Vector2) -> void:
	var colors := [Color("bfa06b"), Color("789c91"), Color("c5ac72"), Color("8582ad"), Color("ad5a58")]
	var shaft: Color = colors[maxi(0, FishingSession.RODS.find(session.rod))]
	var control := base.lerp(tip, 0.5) + Vector2(-12, -4)
	var points: Array[Vector2] = []
	for index in range(17):
		var t := index / 16.0
		points.append((base * pow(1.0 - t, 2) + control * (2.0 * (1.0 - t) * t) + tip * t * t).snapped(Vector2(2, 2)))
	for index in range(16):
		var width := 3.0 if index > 10 else 5.0
		draw_line(points[index] + Vector2(2, 1), points[index + 1] + Vector2(2, 1), Color("111d28"), width + 4)
		draw_line(points[index], points[index + 1], shaft.darkened(0.25), width + 2)
		draw_line(points[index] - Vector2(1, 0), points[index + 1] - Vector2(1, 0), shaft, width)
	for index in [4, 8, 12, 15]:
		draw_rect(Rect2(points[index] - Vector2(3, 2), Vector2(7, 4)), Color("e3d2a0"))
	draw_line(base, points[4], Color("171e27"), 14)
	draw_line(base - Vector2(2, 0), points[4] - Vector2(2, 0), Color("65513f"), 8)
	for index in range(1, 8):
		var wrap := base.lerp(points[4], index / 8.0).round()
		draw_line(wrap - Vector2(4, -1), wrap + Vector2(3, -4), Color("b59b6c"), 2)
	var reel := points[3] + Vector2(10, 3)
	draw_rect(Rect2(reel - Vector2(10, 12), Vector2(22, 24)), Color("10151f"))
	draw_rect(Rect2(reel - Vector2(7, 9), Vector2(16, 18)), GOLD.darkened(0.3))
	draw_rect(Rect2(reel - Vector2(4, 6), Vector2(10, 12)), Color("d9e3cd"))
	draw_rect(Rect2(reel - Vector2(4, 1), Vector2(10, 3)), Color("778e87"))
	draw_line(reel + Vector2(9, 0), reel + Vector2(17, 5), GOLD, 3)
	draw_rect(Rect2(reel + Vector2(15, 2), Vector2(5, 9)), Color("352e2c"))

func _draw_bobber(at: Vector2) -> void:
	at = at.round()
	var ripple := 9.0 + roundf(sin(clock * 3) * 2)
	var foam := Color(0.82, 0.95, 0.91, 0.8)
	for side: float in [-1.0, 1.0]:
		draw_line(at + Vector2(side * 5, 5), at + Vector2(side * ripple, 5), foam, 1)
		draw_line(at + Vector2(side * ripple, 3), at + Vector2(side * (ripple + 3), 3), foam, 1)
	draw_rect(Rect2(at + Vector2(-5, -5), Vector2(10, 11)), Color("10151f"))
	draw_rect(Rect2(at + Vector2(-3, -7), Vector2(6, 15)), Color("10151f"))
	draw_rect(Rect2(at + Vector2(-3, -5), Vector2(6, 5)), Color("ed8175"))
	draw_rect(Rect2(at + Vector2(-3, 0), Vector2(6, 5)), Color("f0e7c9"))
	draw_rect(Rect2(at + Vector2(-1, -4), Vector2(2, 3)), Color("ffd3a5"))

func _draw_meter() -> void:
	draw_style_box(_meter_frame, Rect2(origin + Vector2(300, 480), Vector2(720, 44)))
	var fraction := clampf(session.remaining / maxf(1.0, session.distance), 0.0, 1.0)
	_text(Vector2(312, 500), "POWER  %d%%" % roundi(session.power * 100) if session.state == FishingSession.State.POWER else "LINE  %d ft" % ceili(session.remaining), 13, GOLD)
	var at := origin + Vector2(450, 489)
	draw_rect(Rect2(at - Vector2(2, 2), Vector2(294, 18)), Color("576573"))
	draw_rect(Rect2(at, Vector2(290, 14)), INK)
	var meter := session.power if session.state == FishingSession.State.POWER else fraction
	var fill := FantasyUI.TEAL if session.state != FishingSession.State.POWER or meter >= FishingSession.PERFECT_CAST_POWER else GOLD
	draw_rect(Rect2(at, Vector2(floorf(290 * meter), 14)), fill.darkened(0.25))
	draw_rect(Rect2(at, Vector2(floorf(290 * meter), 4)), fill)
	if session.state == FishingSession.State.POWER:
		var perfect_x := at.x + 290 * FishingSession.PERFECT_CAST_POWER
		draw_rect(Rect2(Vector2(perfect_x, at.y), Vector2(290 * (1.0 - FishingSession.PERFECT_CAST_POWER), 14)), Color(0.49, 0.77, 0.73, 0.65))
		for tick in range(11):
			var x := at.x + float(tick) * 29.0
			draw_line(Vector2(x, at.y - 2), Vector2(x, at.y + 16), Color(0.91, 0.92, 0.82, 0.5))
		draw_rect(Rect2(at + Vector2(floorf(290 * meter) - 1, -3), Vector2(3, 20)), FantasyUI.IVORY)
		_text(Vector2(450, 520), "0%", 10, MUTED)
		_text(Vector2(583, 520), "50%", 10, MUTED)
		_text(Vector2(712, 520), "100%", 10, MUTED)
		_text(Vector2(764, 518), "95-100%: full range", 11, MUTED)
		_text(Vector2(764, 500), "CAST  %d ft" % roundi(session.projected_cast_distance()), 13, GOLD)
	else:
		_text(Vector2(764, 500), "ESCAPE  %d%%" % roundi(session.strain * 100), 13, Color("ed9b8d"))
		draw_rect(Rect2(origin + Vector2(764, 510), Vector2(150, 4)), INK)
		draw_rect(Rect2(origin + Vector2(764, 510), Vector2(floorf(150 * session.strain), 4)), Color("ed9b8d"))

func _frame() -> StyleBox:
	return _panel_frame
