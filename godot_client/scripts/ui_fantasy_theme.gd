class_name FantasyUI
extends RefCounted

const INK := Color("10151f")
const NAVY := Color("172335")
const SLATE := Color("283d51")
const GOLD := Color("e3bf7e")
const IVORY := Color("efe2bd")
const MUTED := Color("b7c5d0")
const TEAL := Color("7dc4bb")
const ICON_KEYS := ["bag", "skills", "spells", "equipment", "combat", "health", "attack", "strength", "defense", "range", "magic", "coins"]
static var _theme: Theme
static var _atlas: Texture2D
static var _display_font: Font

static func text_size(original: int) -> int:
	return maxi(16, roundi(float(original) * 1.15))

static func viewport_size(control: Control) -> Vector2:
	var parent := control.get_parent() as Control
	return parent.size if parent != null else control.get_viewport_rect().size

static func display_font() -> Font:
	make_theme()
	return _display_font if _display_font != null else ThemeDB.fallback_font

static func box(color: Color = NAVY, border: Color = Color("68563f")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(2)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style

static func frame_style() -> StyleBox:
	var path := "res://Assets/UI/aetheria_frame.png"
	if ResourceLoader.exists(path):
		var style := StyleBoxTexture.new()
		style.texture = load(path)
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			style.set_texture_margin(side, 24)
			style.set_content_margin(side, 26)
		return style
	return box(NAVY, GOLD)

static func icon(key: String) -> Texture2D:
	if _atlas == null and ResourceLoader.exists("res://Assets/UI/aetheria_icons.png"):
		_atlas = load("res://Assets/UI/aetheria_icons.png")
	if _atlas == null:
		return null
	var index := ICON_KEYS.find(key)
	if index < 0:
		index = 0
	var result := AtlasTexture.new()
	result.atlas = _atlas
	result.region = Rect2((index % 6) * 32, floori(float(index) / 6.0) * 32, 32, 32)
	return result

static func make_theme() -> Theme:
	if _theme != null:
		return _theme
	_theme = Theme.new()
	_theme.default_font_size = 18
	_theme.default_font = ThemeDB.fallback_font
	if ResourceLoader.exists("res://Assets/UI/PixelifySans.ttf"):
		var font: FontFile = load("res://Assets/UI/PixelifySans.ttf")
		font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_display_font = font
		_theme.set_font("font", "TabBar", font)
	_theme.set_color("font_color", "Label", IVORY)
	for type in ["Button", "TabBar", "LineEdit", "SpinBox"]:
		_theme.set_color("font_color", type, IVORY)
		_theme.set_color("font_hover_color", type, Color.WHITE)
		_theme.set_color("font_pressed_color", type, GOLD)
		_theme.set_color("font_disabled_color", type, Color("94a4b3"))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var color := NAVY
		var border := Color("675540")
		if state == "hover":
			color = Color("30475b")
			border = GOLD
		elif state == "pressed":
			color = Color("36545d")
			border = TEAL
		elif state == "disabled":
			color = Color("161e2a")
			border = Color("35414d")
		elif state == "focus":
			color = Color.TRANSPARENT
			border = TEAL
		_theme.set_stylebox(state, "Button", box(color, border))
	_theme.set_constant("h_separation", "Button", 8)
	_theme.set_constant("icon_max_width", "Button", 32)
	_theme.set_stylebox("panel", "PanelContainer", box())
	_theme.set_stylebox("tab_selected", "TabBar", box(SLATE, GOLD))
	_theme.set_stylebox("tab_unselected", "TabBar", box(INK, Color("66533f")))
	_theme.set_stylebox("tab_hovered", "TabBar", box(Color("30475b"), TEAL))
	_theme.set_color("font_selected_color", "TabBar", GOLD)
	_theme.set_color("font_unselected_color", "TabBar", MUTED)
	_theme.set_font_size("font_size", "TabBar", 20)
	_theme.set_constant("icon_max_width", "TabBar", 24)
	for state: String in ["normal", "focus"]:
		var field := box(INK, TEAL if state == "focus" else Color("71869b"))
		field.content_margin_top = 5
		field.content_margin_bottom = 5
		_theme.set_stylebox(state, "LineEdit", field)
	_theme.set_font_size("font_size", "LineEdit", 20)
	var bar_background := box(INK, Color("354554"))
	var bar_fill := box(Color("4f8891"), TEAL)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		bar_background.set_content_margin(side, 0)
		bar_fill.set_content_margin(side, 0)
	_theme.set_stylebox("background", "ProgressBar", bar_background)
	_theme.set_stylebox("fill", "ProgressBar", bar_fill)
	_theme.set_stylebox("panel", "TooltipPanel", box(INK, GOLD))
	return _theme
