extends CanvasLayer
## Keep the existing crafting/item controls above the permanent chat HUD while
## following the game's original readable-UI scale, including window resizing.
var source: Control
var surface: Control

static func mount(widget: Control, ui_root: Control) -> void:
	var overlay := ui_root.get_node_or_null("CraftingMenuLayer") as CanvasLayer
	if overlay == null:
		overlay = load("res://scripts/crafting_menu_layer.gd").new()
		overlay.name = "CraftingMenuLayer"
		overlay.layer = 81
		overlay.source = ui_root
		overlay.surface = Control.new()
		overlay.surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(overlay.surface)
		ui_root.add_child(overlay)
		overlay._sync()
	widget.reparent(overlay.surface, false)

func _process(_delta: float) -> void:
	_sync()

func _sync() -> void:
	transform = source.get_global_transform_with_canvas()
	surface.size = source.size
