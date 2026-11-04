extends RefCounted
## Journal-only summon catalogue. No costs, actor spawning or combat actions.
const Portrait = preload("res://scripts/ui_summon_portrait.gd")

func build(menu: Control) -> void:
	var left: VBoxContainer = menu._column(menu.body)
	left.add_child(menu._label("Summoning", 18, FantasyUI.IVORY))
	left.add_child(menu._label("Choose a companion to inspect.", 12, FantasyUI.MUTED, true))
	var scroll: ScrollContainer = menu._scroll("SummonListScroll")
	left.add_child(scroll)
	var grid: GridContainer = menu._grid(2, 8)
	scroll.add_child(grid)
	var selected: Dictionary = {}
	for summon: Dictionary in menu.summon_catalog:
		var active: bool = String(summon.id) == menu.selected_summon_id
		if active:
			selected = summon
		var button: Button = menu._card_button(Vector2(254, 84), active)
		button.name = String(summon.id).to_pascal_case() + "Card"
		button.tooltip_text = "Inspect " + String(summon.name)
		button.pressed.connect(menu.select_summon.bind(String(summon.id)))
		var column: VBoxContainer = menu._button_column(button, 6)
		column.add_child(menu._label(String(summon.name), 14, FantasyUI.IVORY))
		column.add_child(menu._label(String(summon.attack), 11, FantasyUI.TEAL, true))
		grid.add_child(button)
	var details: VBoxContainer = menu._details_column("SummonDetails")
	if selected.is_empty():
		return
	var title: Label = menu._label(String(selected.name), 20, FantasyUI.GOLD, true)
	title.name = "SummonName"
	details.add_child(title)
	var portrait := Portrait.new()
	portrait.name = "SummonPortrait"
	portrait.configure(selected.preview)
	details.add_child(portrait)
	details.add_child(menu._label(String(selected.attack), 14, FantasyUI.TEAL, true))
	details.add_child(menu._label(String(selected.description), 13, FantasyUI.IVORY, true))
	details.add_child(HSeparator.new())
	var summon_button := Button.new()
	summon_button.name = "SummonAction"
	summon_button.text = "Summon"
	summon_button.custom_minimum_size.y = 42
	summon_button.disabled = true
	summon_button.tooltip_text = "Summoning is not yet available."
	details.add_child(summon_button)
	details.add_child(menu._label("Summoning is not yet available.", 11, FantasyUI.MUTED, true))
