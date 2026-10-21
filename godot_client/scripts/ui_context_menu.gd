class_name InteractionContextMenu
extends Control
## One shared, in-canvas menu. The full-screen input shield prevents click-through.
var panel: PanelContainer
var options: VBoxContainer
var actions: Array[Dictionary] = []
var _anchor := Vector2.ZERO

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = FantasyUI.make_theme()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 100
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", FantasyUI.box(FantasyUI.INK, FantasyUI.GOLD))
	add_child(panel)
	options = VBoxContainer.new()
	options.add_theme_constant_override("separation", 1)
	panel.add_child(options)
	get_viewport().size_changed.connect(dismiss)
	hide()

func show_options(title: String, entries: Array[Dictionary], at: Vector2) -> void:
	actions = entries.duplicate()
	for child: Node in options.get_children():
		options.remove_child(child)
		child.queue_free()
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", FantasyUI.GOLD)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	options.add_child(heading)
	options.add_child(HSeparator.new())
	for entry: Dictionary in actions:
		var button := _option_button(String(entry.get("label", "")))
		button.disabled = bool(entry.get("disabled", false))
		button.pressed.connect(_choose.bind(entry.get("action", Callable())))
		options.add_child(button)
	var cancel := _option_button("Cancel")
	cancel.pressed.connect(dismiss)
	options.add_child(cancel)
	_anchor = get_global_transform_with_canvas().affine_inverse() * at
	panel.position = _anchor
	panel.size = Vector2.ZERO
	# GUI hit-testing follows sibling order, independently of drawing z_index.
	# Keep the input shield above modal panels created after this shared menu.
	move_to_front()
	show()
	_fit_to_viewport.call_deferred()

func _option_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(190, 36)
	button.add_theme_font_size_override("font_size", 18)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := FantasyUI.box(FantasyUI.SLATE if state == "hover" else FantasyUI.INK, Color.TRANSPARENT)
		box.set_border_width_all(0)
		box.content_margin_top = 3
		box.content_margin_bottom = 3
		box.content_margin_left = 5
		box.content_margin_right = 5
		if state == "focus":
			box.bg_color = Color.TRANSPARENT
			box.border_color = FantasyUI.TEAL
			box.set_border_width_all(1)
		button.add_theme_stylebox_override(state, box)
	return button

func _fit_to_viewport() -> void:
	panel.size = panel.get_combined_minimum_size()
	var available := FantasyUI.viewport_size(self)
	panel.position = Vector2(clampf(_anchor.x, 0, maxf(0, available.x - panel.size.x)), clampf(_anchor.y, 0, maxf(0, available.y - panel.size.y)))

func dismiss() -> void:
	hide()
	actions.clear()

func _choose(action: Callable) -> void:
	dismiss()
	if action.is_valid():
		action.call()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		dismiss()
		accept_event()
