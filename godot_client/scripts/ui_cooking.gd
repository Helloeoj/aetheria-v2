class_name CookingPanel
extends Control
## Shared stove minigame; the session owns all gameplay and rewards.
const PanScript = preload("res://scripts/ui_cooking_pan.gd")
var game: Node
var controller: Node
var station: Node2D
var session: CookingSession
var raw_picker: OptionButton
var cook_one: Button
var cook_all: Button
var details: Label
var status: Label
var progress: ProgressBar
var level_label: Label
var frame: PanelContainer
var flip_action: Button
var timer_label: Label
var pan: Control

func configure(owner_game: Node, owner_controller: Node) -> void:
	game = owner_game
	controller = owner_controller
	theme = FantasyUI.make_theme()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.008, 0.005, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	frame = PanelContainer.new()
	frame.add_theme_stylebox_override("panel", FantasyUI.frame_style())
	add_child(frame)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 0)
	frame.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var heading := Label.new()
	heading.text = "Cooking"
	heading.add_theme_font_size_override("font_size", 30)
	var title_row := HBoxContainer.new()
	box.add_child(title_row)
	title_row.add_child(heading)
	level_label = Label.new()
	level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_row.add_child(level_label)
	var hint := Label.new()
	hint.text = "Heat the pan, then flip once. Click FLIP or press Space / Enter."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	raw_picker = OptionButton.new()
	raw_picker.name = "RawFishPicker"
	raw_picker.custom_minimum_size.y = 38
	raw_picker.item_selected.connect(func(_index: int) -> void: refresh())
	box.add_child(raw_picker)
	details = Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.custom_minimum_size = Vector2(640, 44)
	box.add_child(details)
	pan = PanScript.new()
	pan.custom_minimum_size.y = 126
	box.add_child(pan)
	timer_label = Label.new()
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_color_override("font_color", FantasyUI.GOLD)
	box.add_child(timer_label)
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 18
	progress.show_percentage = false
	box.add_child(progress)
	flip_action = _button("FLIP!  [Space / Enter]", controller.flip, box)
	flip_action.name = "FlipAction"
	flip_action.add_theme_font_size_override("font_size", 25)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.y = 44
	box.add_child(status)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	cook_one = _button("Cook 1", start_cooking.bind(false), buttons)
	cook_all = _button("Cook all", start_cooking.bind(true), buttons)
	_button("Close [Esc]", close, buttons)
	hide()

func _button(title: String, action: Callable, parent: Node) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(185, 44)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func open(target: Node2D) -> void:
	station = target
	session = CookingSession.new(game.player, station.heat, game.combat)
	session.message = "Choose raw fish to cook at the stove."
	raw_picker.clear()
	var recipes: Array[Dictionary] = []
	for item: Dictionary in GameData.items_by_id.values():
		if String(item.get("fish_state", "")) == "raw" and not CookingSession.recipe_for_item(String(item.name)).is_empty():
			recipes.append(item)
	recipes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.cooking_level) < int(b.cooking_level))
	var selected := -1
	for item: Dictionary in recipes:
		var index := raw_picker.item_count
		var count := int(game.player.backpack.get(String(item.name), 0))
		raw_picker.add_item("%s  —  %d in backpack  —  Cooking %d" % [String(item.name), count, int(item.cooking_level)])
		raw_picker.set_item_metadata(index, String(item.name))
		if selected < 0 and count > 0 and game.player.get_skill_level("cooking") >= int(item.cooking_level):
			selected = index
	if raw_picker.item_count > 0:
		raw_picker.select(maxi(0, selected))
	show()
	refresh()

func selected_raw() -> String:
	return String(raw_picker.get_item_metadata(raw_picker.selected)) if raw_picker.selected >= 0 else ""

func start_cooking(all_fish: bool) -> void:
	if not controller.can_use(station):
		close()
		return
	var raw := selected_raw()
	var quantity := int(game.player.backpack.get(raw, 0)) if all_fish else 1
	var error := session.start(raw, quantity)
	if not error.is_empty():
		session.message = error
	refresh()

func handle_key(event: InputEventKey) -> void:
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		close()
	elif event.keycode in [KEY_SPACE, KEY_ENTER]:
		controller.flip()

func refresh() -> void:
	size = game.ui_root.size
	frame.size = Vector2(840, 660)
	frame.position = (size - frame.size) * 0.5
	var raw := selected_raw()
	var recipe := CookingSession.recipe_for_item(raw)
	var level: int = game.player.get_skill_level("cooking")
	var quantity := int(game.player.backpack.get(raw, 0))
	var cooking := session != null and session.is_active()
	var pending := session != null and session.state == CookingSession.State.FLIP_PENDING
	level_label.text = "%s  ·  Cooking level %d" % [station.station_name, level] if is_instance_valid(station) else "Cooking"
	if not recipe.is_empty():
		var window := CookingSession.reaction_window(level, recipe)
		var window_text := "Untimed — mastered" if is_inf(window) else "%.2fs flip window" % window
		details.text = "%d in backpack  ·  Requires level %d  ·  Mastery level %d\n%s  ·  %d XP per success  ·  %.1fs in the pan" % [quantity, int(recipe.cooking_level), int(recipe.no_burn_level), window_text, int(recipe.cooking_xp), float(recipe.cooking_seconds)]
		cook_one.disabled = cooking or quantity == 0 or level < int(recipe.cooking_level)
	else:
		details.text = "No cooking recipe selected."
		cook_one.disabled = true
	cook_all.disabled = cook_one.disabled
	raw_picker.disabled = cooking
	flip_action.disabled = not pending
	timer_label.text = "Choose your food" if not cooking else "Heating... wait for FLIP!"
	progress.value = 100.0 * session.elapsed / float(recipe.get("cooking_seconds", 3.0)) if cooking else 0.0
	if pending:
		if is_inf(session.flip_window):
			timer_label.text = "SAFE · Mastered · No time limit — flip when ready"
			progress.value = 100.0
		else:
			var left := maxf(0.0, session.flip_window - session.flip_elapsed)
			timer_label.text = "FLIP NOW!  %.2f seconds" % left
			progress.value = 100.0 * left / session.flip_window
	elif session != null and session.state == CookingSession.State.FEEDBACK:
		timer_label.text = "Burnt — try the next fish" if bool(session.last_result.get("burnt", false)) else "Perfect flip!"
		progress.value = 0.0
	pan.set_cooking(session, raw)
	status.text = session.message if session != null else "Choose raw fish."
	if cooking:
		status.text += "\n%d remaining  ·  %d cooked  ·  %d burnt" % [session.remaining, session.cooked_count, session.burnt_count]
	elif quantity == 0 and (session == null or session.last_result.is_empty()):
		status.text += "\nMove raw fish from your Fishing Pale into your backpack before cooking."
	# Keep displayed quantities current after each completed fish.
	for index in range(raw_picker.item_count):
		var name_string := String(raw_picker.get_item_metadata(index))
		var item: Dictionary = CookingSession.recipe_for_item(name_string)
		raw_picker.set_item_text(index, "%s  —  %d in backpack  —  Cooking %d" % [name_string, int(game.player.backpack.get(name_string, 0)), int(item.get("cooking_level", 1))])

func close() -> void:
	raw_picker.get_popup().hide()
	if session != null:
		session.close()
	hide()
	station = null
	game._reset_held_movement()
	game._refresh_character_ui()

func _exit_tree() -> void:
	if session != null:
		session.close()
