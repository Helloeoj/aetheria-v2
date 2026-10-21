class_name SkillDebugPanel
extends PanelContainer

signal skill_levels_changed
signal health_restored
signal close_requested

const PANEL_WIDTH := 282.0
const PANEL_HEIGHT := 560.0
const REFRESH_INTERVAL := 0.2
const TEXT_COLOR := Color("cbd7e6")
const MUTED_COLOR := Color("b7c5d0")
const BRASS_COLOR := Color("d6be8b")
const ACCENT_COLOR := Color("62d1c7")

var game: Node
var skill_editors: Dictionary = {}
var combat_label: Label
var health_label: Label
var health_bar: ProgressBar
var status_label: Label
var skill_scroll: ScrollContainer
var skill_rows: VBoxContainer
var _content: VBoxContainer
var _refresh_elapsed := 0.0
var _refreshing := false
var _built := false

func configure(game_ref: Node) -> void:
	game = game_ref
	if not _built:
		_build_panel()
		_built = true
	_refresh_from_player()
	_update_layout()

func _ready() -> void:
	get_viewport().size_changed.connect(_update_layout)
	minimum_size_changed.connect(_update_layout)
	visibility_changed.connect(_on_visibility_changed)
	_update_layout()

func _process(delta: float) -> void:
	if not visible or not _built:
		return
	_refresh_elapsed += delta
	if _refresh_elapsed >= REFRESH_INTERVAL:
		_refresh_elapsed = 0.0
		_refresh_from_player()

func is_editing() -> bool:
	if not is_inside_tree() or not is_visible_in_tree():
		return false
	var focused := get_viewport().gui_get_focus_owner()
	return focused != null and is_ancestor_of(focused)

func set_skill_level(skill: String, value: int) -> void:
	var player := _get_player()
	var skill_id := SkillProgression.normalize_skill(skill)
	if player == null or skill_id not in SkillProgression.SKILL_IDS:
		return
	var bounded_level := clampi(value, SkillProgression.MIN_LEVEL, SkillProgression.MAX_LEVEL)
	player.set_skill_level(skill_id, bounded_level)
	if skill_id == "magic" and not player.selected_spell_id.is_empty():
		if not GameData.is_spell_unlocked(player.selected_spell_id, player.get_magic_level()):
			player.selected_spell_id = ""
			player.cycle_known_spell(1)
	_refresh_actor()
	_refresh_from_player()
	if status_label != null:
		status_label.text = "%s set to level %d.\nSkill XP updated." % [
			_skill_name(skill_id), bounded_level
		]
	skill_levels_changed.emit()

func restore_health() -> void:
	var player := _get_player()
	if player == null:
		return
	player.current_hp = player.get_max_hp()
	_refresh_actor()
	_refresh_from_player()
	if status_label != null:
		status_label.text = "Health restored.\nReady for practice."
	health_restored.emit()

func refresh() -> void:
	_refresh_from_player()

func _build_panel() -> void:
	theme = FantasyUI.make_theme()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_theme_stylebox_override("panel", FantasyUI.frame_style())
	custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE

	var margin := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 0)
	add_child(margin)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 7)
	margin.add_child(_content)
	var content := _content

	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 7)
	content.add_child(heading)
	heading.add_child(_make_icon("skills", 22))
	var title := _make_label("Test skills", 18, BRASS_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	heading.add_child(_make_label("K", 11, MUTED_COLOR))
	var close_button := Button.new()
	close_button.name = "CloseSkillTools"
	close_button.text = "×"
	close_button.tooltip_text = "Close skill testing [K]"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(func() -> void: close_requested.emit())
	heading.add_child(close_button)
	content.add_child(_make_label("DEVELOPER CONTROLS", 10, MUTED_COLOR))
	content.add_child(HSeparator.new())

	var combat_row := HBoxContainer.new()
	combat_row.add_theme_constant_override("separation", 7)
	content.add_child(combat_row)
	combat_row.add_child(_make_icon("combat", 20))
	combat_label = _make_label("Combat level 1 / 150", 14, ACCENT_COLOR)
	combat_row.add_child(combat_label)
	health_label = _make_label("Health", 12, TEXT_COLOR)
	content.add_child(health_label)
	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size.y = 6
	health_bar.show_percentage = false
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(health_bar)

	# The registry supplies every row; a growing skill list scrolls independently
	# so the title, close control, health restore and edit result remain reachable.
	skill_scroll = ScrollContainer.new()
	skill_scroll.name = "AllSkillLevels"
	skill_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	skill_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	skill_scroll.follow_focus = true
	content.add_child(skill_scroll)
	skill_rows = VBoxContainer.new()
	skill_rows.add_theme_constant_override("separation", 5)
	skill_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_scroll.add_child(skill_rows)
	for skill: String in SkillProgression.SKILL_IDS:
		_build_skill_row(skill_rows, skill)
	skill_rows.minimum_size_changed.connect(_update_layout)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(spacer)
	var restore_button := Button.new()
	restore_button.text = "Restore full health"
	restore_button.icon = FantasyUI.icon("health")
	restore_button.expand_icon = true
	restore_button.add_theme_constant_override("icon_max_width", 18)
	restore_button.custom_minimum_size.y = 34
	restore_button.add_theme_font_size_override("font_size", 17)
	restore_button.focus_mode = Control.FOCUS_NONE
	restore_button.pressed.connect(restore_health)
	content.add_child(restore_button)
	status_label = _make_label("Practice levels also update XP.", 10, MUTED_COLOR)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.y = 48
	content.add_child(status_label)

func _build_skill_row(container: VBoxContainer, skill: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	container.add_child(row)
	row.add_child(_make_icon(skill, 20))
	var label := _make_label(_skill_name(skill), 13, TEXT_COLOR)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.tooltip_text = _skill_name(skill)
	row.add_child(label)
	var editor := SpinBox.new()
	editor.name = skill.capitalize() + "Level"
	editor.min_value = SkillProgression.MIN_LEVEL
	editor.max_value = SkillProgression.MAX_LEVEL
	editor.step = 1.0
	editor.rounded = true
	editor.custom_minimum_size = Vector2(84, 36)
	editor.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	editor.tooltip_text = "Set %s level for practice; skill XP changes with it." % _skill_name(skill)
	editor.value_changed.connect(_on_skill_value_changed.bind(skill))
	editor.focus_entered.connect(_on_editor_focus_entered)
	var line_edit := editor.get_line_edit()
	line_edit.select_all_on_focus = true
	line_edit.focus_entered.connect(_on_editor_focus_entered)
	row.add_child(editor)
	skill_editors[skill] = editor

func _skill_name(skill: String) -> String:
	return String(SkillProgression.SKILL_NAMES.get(skill, skill.capitalize()))

func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FantasyUI.text_size(font_size))
	if font_size >= 18:
		label.add_theme_font_override("font", FantasyUI.display_font())
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _make_icon(key: String, side: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = FantasyUI.icon(key if key in FantasyUI.ICON_KEYS else "skills")
	icon.custom_minimum_size = Vector2(side, side)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func _get_player() -> PlayerState:
	if not is_instance_valid(game):
		return null
	return game.get("player") as PlayerState

func _refresh_actor() -> void:
	if is_instance_valid(game) and game.has_method("_refresh_player_actor_from_player"):
		game.call("_refresh_player_actor_from_player")

func _refresh_from_player() -> void:
	var player := _get_player()
	if player == null or not _built:
		return
	_refreshing = true
	for skill: String in skill_editors:
		var editor: SpinBox = skill_editors[skill]
		if not editor.has_focus() and not editor.get_line_edit().has_focus():
			editor.set_value_no_signal(player.get_skill_level(skill))
	combat_label.text = "Combat level %d / %d" % [
		player.get_combat_level(), SkillProgression.MAX_COMBAT_LEVEL
	]
	health_label.text = "Health  %d / %d" % [player.current_hp, player.get_max_hp()]
	health_bar.max_value = player.get_max_hp()
	health_bar.value = player.current_hp
	_refreshing = false

func _on_skill_value_changed(value: float, skill: String) -> void:
	if not _refreshing:
		set_skill_level(skill, roundi(value))

func _on_editor_focus_entered() -> void:
	if is_instance_valid(game) and game.has_method("_reset_held_movement"):
		game.call("_reset_held_movement")

func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_refresh_from_player()
		_update_layout()
		return
	if not is_inside_tree():
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused):
		focused.release_focus()

func _update_layout() -> void:
	if not is_inside_tree():
		return
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -PANEL_WIDTH - 26.0
	offset_right = -26.0
	var viewport_height := FantasyUI.viewport_size(self).y
	var available_height := maxf(1.0, viewport_height - 36.0)
	var minimum_height := minf(PANEL_HEIGHT, available_height)
	if not is_equal_approx(custom_minimum_size.y, minimum_height):
		custom_minimum_size.y = minimum_height
	if skill_scroll != null and skill_rows != null:
		# Measure the fixed controls separately from the scroll viewport. This keeps
		# all current rows visible while bounding future registry additions on screen.
		var frame_height := get_theme_stylebox("panel").get_minimum_size().y
		var fixed_height := frame_height + _content.get_combined_minimum_size().y - skill_scroll.get_combined_minimum_size().y
		var rows_height := skill_rows.get_combined_minimum_size().y
		var scroll_height := minf(rows_height, maxf(1.0, available_height - fixed_height))
		if not is_equal_approx(skill_scroll.custom_minimum_size.y, scroll_height):
			skill_scroll.custom_minimum_size.y = scroll_height
	var panel_height := maxf(minimum_height, get_combined_minimum_size().y)
	var top := minf(115.0, maxf(12.0, viewport_height - panel_height - 24.0))
	offset_top = top
	offset_bottom = top + panel_height
