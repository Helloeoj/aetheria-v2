class_name InventoryMenu
extends Control

enum Page { INVENTORY, SKILLS, SPELLS, EQUIPMENT, COMBAT }

const PAGE_NAMES := ["Inventory", "Skills", "Spells", "Equipment", "Combat"]
const PAGE_ICONS := ["bag", "skills", "spells", "equipment", "combat"]
const SLOT_LAYOUT := [
	["Head", "head"], ["Neck", "neck"], ["Cape", "cape"], ["Chest", "chest"],
	["Legs", "legs"], ["Weapon", "weapon"], ["Shield", "shield"],
	["Ring 1", "ring1"], ["Ring 2", "ring2"], ["Quiver", "quiver"]
]
const SKILL_EFFECTS := {
	"health": "Raises maximum health by 20 for each level.",
	"attack": "Improves melee hit accuracy with your selected weapon style.",
	"strength": "Combines with melee strength bonuses to raise your maximum hit.",
	"defense": "Improves defense against physical attacks.",
	"range": "Improves ranged accuracy, damage and damage rolls.",
	"magic": "Unlocks spells, raises mana and improves magic combat.",
	"fishing": "Unlocks poles, bait and fish; improves control without raising combat level.",
	"cooking": "Cooks raw fish at campfires; higher levels unlock fish and reduce burning."
}
const STYLE_NAMES := {"stab": "Stab", "slash": "Slash", "blunt": "Crush", "ranged": "Ranged", "magic": "Magic"}
const PANEL_SIZE := Vector2(930, 610)
const TRAINING_SESSION_TOOLTIP := "Session time starts with the first earned XP and includes downtime. XP/hour appears after 60 seconds. Manual skill level changes are excluded and reset the session. Reset before comparing gear."

var game: Node
var panel: Panel
var tabs: TabBar
var selected_page := Page.INVENTORY
var selected_item_name := ""
var selected_inventory_slot_index := -1
var selected_equipment_slot := ""
var status_text := "Choose a tab to manage your adventurer."
var header_stats: Label
var footer: Label
var body: HBoxContainer
var _built := false
var _refresh_elapsed := 0.0
var _last_signature := ""
var _scrolls: Array[ScrollContainer] = []
var _scroll_positions: Dictionary = {}
var _skill_session_header: HBoxContainer
var _skill_session_label: Label
var _skill_session_labels: Dictionary = {}

func configure(game_ref: Node) -> void:
	game = game_ref
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _built:
		_build_shell()
		_built = true
	visible = false
	refresh_view()
	_update_layout()

func _ready() -> void:
	get_viewport().size_changed.connect(_update_layout)
	_update_layout()

func _process(delta: float) -> void:
	if not visible or not _built:
		return
	_refresh_elapsed += delta
	if _refresh_elapsed < 0.2:
		return
	_refresh_elapsed = 0.0
	_update_header()
	_update_skill_training_readout()
	_repair_spell_selection()
	if _state_signature() != _last_signature:
		refresh_view()

func toggle() -> void:
	visible = not visible
	if is_instance_valid(game):
		if game.has_method("_reset_held_movement"):
			game.call("_reset_held_movement")
		game.set("spell_cast_requested", false)
	if visible:
		refresh_view()
	elif is_inside_tree():
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null and is_ancestor_of(focused):
			focused.release_focus()

func on_key_press(event: InputEventKey) -> bool:
	if not visible:
		return false
	if event.keycode in [KEY_ESCAPE, KEY_I]:
		toggle()
		return true
	if event.keycode == KEY_E and selected_page == Page.SPELLS:
		_cast_selected_spell()
		return true
	return false

func on_mouse_press(position: Vector2) -> bool:
	# Native controls dispatch their own actions; this preserves the caller API.
	return visible and panel != null and panel.get_global_rect().has_point(position)

func select_page(index: int) -> void:
	selected_page = clampi(index, Page.INVENTORY, Page.COMBAT)
	if tabs != null and tabs.current_tab != selected_page:
		tabs.set_block_signals(true)
		tabs.current_tab = selected_page
		tabs.set_block_signals(false)
	refresh_view()

func refresh_view() -> void:
	if not _built or _player() == null:
		return
	_repair_spell_selection()
	_update_header()
	for scroll: ScrollContainer in _scrolls:
		if is_instance_valid(scroll):
			_scroll_positions[String(scroll.name)] = scroll.scroll_vertical
	_scrolls.clear()
	_skill_session_header = null
	_skill_session_label = null
	_skill_session_labels.clear()
	for child: Node in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var player := _player()
	match selected_page:
		Page.INVENTORY:
			_build_inventory(player)
		Page.SKILLS:
			_build_skills(player)
		Page.SPELLS:
			_build_spells(player)
		Page.EQUIPMENT:
			_build_equipment(player)
		Page.COMBAT:
			_build_combat(player)
	_update_skill_training_readout()
	_last_signature = _state_signature()
	_restore_scroll.call_deferred()

func select_spell(spell_id: String) -> bool:
	var player := _player()
	if player == null:
		return false
	if not player.select_spell(spell_id):
		var spell := GameData.get_spell(spell_id)
		_set_status("This spell requires Magic level %d." % int(spell.get("unlock_level", 1)))
		return false
	_set_status("Readied %s. Use Cast now or press E with a suitable target." % String(GameData.get_spell(spell_id).get("name", spell_id)))
	refresh_view()
	return true

func select_combat_style(style: String) -> bool:
	var player := _player()
	if player == null:
		return false
	var canonical_style := style.to_lower()
	if canonical_style == "crush":
		canonical_style = "blunt"
	elif canonical_style == "range":
		canonical_style = "ranged"
	if not player.set_attack_style(canonical_style):
		_set_status("Your current weapon does not support that combat style.")
		return false
	_refresh_combat_view()
	_set_status("Combat style set to %s." % String(STYLE_NAMES.get(canonical_style, canonical_style)))
	refresh_view()
	return true

func _build_shell() -> void:
	theme = FantasyUI.make_theme()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# A fixed Panel keeps temporary wrapped-label minima inside the journal.
	panel = Panel.new()
	panel.add_theme_stylebox_override("panel", FantasyUI.frame_style())
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	_update_layout()
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	panel.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 26
	content.offset_top = 26
	content.offset_right = -26
	content.offset_bottom = -26
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 10)
	content.add_child(heading)
	heading.add_child(_icon("bag", 28))
	var title := _label("Adventurer journal", 23, FantasyUI.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close := _action_button("Close [I]", toggle)
	close.custom_minimum_size = Vector2(112, 40)
	close.add_theme_font_size_override("font_size", 17)
	heading.add_child(close)
	header_stats = _label("", 14, FantasyUI.TEAL)
	header_stats.custom_minimum_size.y = 24
	content.add_child(header_stats)
	tabs = TabBar.new()
	tabs.name = "JournalTabs"
	tabs.clip_tabs = false
	for index in range(PAGE_NAMES.size()):
		tabs.add_tab(String(PAGE_NAMES[index]), FantasyUI.icon(String(PAGE_ICONS[index])))
		tabs.set_tab_icon_max_width(index, 22)
	tabs.tab_changed.connect(select_page)
	content.add_child(tabs)
	body = HBoxContainer.new()
	body.name = "JournalContent"
	body.add_theme_constant_override("separation", 14)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	content.add_child(HSeparator.new())
	footer = _label(status_text, 12, FantasyUI.MUTED, true)
	footer.custom_minimum_size.y = 44
	content.add_child(footer)

func _build_inventory(player: PlayerState) -> void:
	var left := _column(body)
	left.add_child(_label("Backpack", 18, FantasyUI.IVORY))
	left.add_child(_label("Left-click to select. Right-click for item actions.", 12, FantasyUI.MUTED))
	var scroll := _scroll("InventoryScroll")
	left.add_child(scroll)
	var grid := _grid(5, 7)
	scroll.add_child(grid)
	var slots := InventorySystem.inventory_slots(player)
	if selected_inventory_slot_index < 0 or selected_inventory_slot_index >= slots.size() or String(slots[selected_inventory_slot_index].name) != selected_item_name:
		selected_inventory_slot_index = -1
		for slot_index in range(slots.size()):
			if String(slots[slot_index].name) == selected_item_name:
				selected_inventory_slot_index = slot_index
				break
		if selected_inventory_slot_index < 0 and not slots.is_empty():
			selected_inventory_slot_index = 0
	selected_item_name = String(slots[selected_inventory_slot_index].name) if selected_inventory_slot_index >= 0 else ""
	for slot_index in range(slots.size()):
		var item_name := String(slots[slot_index].name)
		var item := GameData.get_item_by_name(item_name)
		var button := _card_button(Vector2(112, 152), slot_index == selected_inventory_slot_index)
		button.set_meta("inventory_slot", slot_index)
		button.set_meta("item_name", item_name)
		button.tooltip_text = "%s\n%s" % [item_name, _equipment_requirement_text(player, item)]
		button.pressed.connect(_inspect_item.bind(item_name, slot_index))
		button.gui_input.connect(_inventory_context_input.bind(item_name, button))
		var card := _button_column(button, 4)
		card.add_child(_item_icon(item, 40))
		var item_label := _label(item_name, 11, FantasyUI.IVORY, true)
		item_label.custom_minimum_size.y = 70
		item_label.max_lines_visible = 3
		item_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(item_label)
		if InventorySystem.is_stackable(item_name):
			var quantity := _label("× %d" % int(slots[slot_index].quantity), 11, FantasyUI.GOLD)
			quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			card.add_child(quantity)
		grid.add_child(button)
	for index in range(maxi(0, 20 - slots.size())):
		var empty := _card_button(Vector2(112, 152))
		empty.disabled = true
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(empty)
	var details := _details_column("InventoryDetails")
	if selected_item_name.is_empty():
		details.add_child(_icon("bag", 44))
		details.add_child(_label("An empty backpack", 19, FantasyUI.GOLD, true))
		details.add_child(_label("Items you find appear here. Select an item to inspect its bonuses and equip it.", 14, FantasyUI.MUTED, true))
		return
	var selected := GameData.get_item_by_name(selected_item_name)
	details.add_child(_item_icon(selected, 64))
	details.add_child(_label(selected_item_name, 19, FantasyUI.GOLD, true))
	details.add_child(_label("%s  ·  Tier %d" % [String(selected.get("material", "Item")), int(selected.get("tier", 1))], 13, FantasyUI.TEAL, true))
	details.add_child(_label("%s  ·  %s" % [String(selected.get("type", "Item")), String(selected.get("rarity", "common")).capitalize()], 12, FantasyUI.MUTED, true))
	var quantity_text := "In backpack: %d" % int(player.backpack.get(selected_item_name, 0)) if InventorySystem.is_stackable(selected_item_name) else "Individual fish · Uses 1 backpack slot"
	details.add_child(_label(quantity_text, 13, FantasyUI.IVORY, true))
	var can_equip: bool = selected.get("slot", null) != null
	var meets_requirement := EquipmentProgression.can_equip(player, selected)
	if can_equip:
		details.add_child(_label(_equipment_requirement_text(player, selected), 13, FantasyUI.TEAL if meets_requirement else FantasyUI.GOLD, true))
	AetheriaDiagnostics.event("Inventory", "display item details", {"item": selected_item_name, "equippable": selected.get("slot", null) != null})
	var bonuses := _item_bonus_text(selected)
	if not bonuses.is_empty():
		details.add_child(HSeparator.new())
		details.add_child(_label(bonuses, 13, FantasyUI.IVORY, true))
	var equip := _action_button(("Equip item" if meets_requirement else "Skill level too low") if can_equip else "Not equippable", _handle_equip.bind(selected_item_name))
	equip.disabled = not can_equip or not meets_requirement
	equip.tooltip_text = _equipment_requirement_text(player, selected)
	details.add_child(equip)
	if String(selected.get("name", "")) == "Magic Orb":
		for element: String in ["fire", "ice", "lightning", "hurricane"]:
			var empower := _action_button("Empower with %s Sigil" % element.capitalize(), _empower_orb.bind(element))
			empower.disabled = int(player.backpack.get(element.capitalize() + " Sigil", 0)) <= 0
			details.add_child(empower)
	if not String(selected.get("orb_element", "")).is_empty():
		details.add_child(_label("%s orb: 10%% chance on a successful damaging staff hit. Effects do not stack or refresh." % String(selected.orb_element).capitalize(), 13, FantasyUI.TEAL, true))
	if int(selected.get("food_healing", 0)) > 0:
		details.add_child(_label("Food: restores up to %d health." % int(selected.food_healing), 13, FantasyUI.TEAL, true))
		details.add_child(_label("Eating adds %.2f seconds to your remaining attack delay (one weapon attack interval)." % FishingSession.eating_attack_delay_seconds(player), 13, FantasyUI.MUTED, true))
		details.add_child(_label("Food cooldown: %.1f seconds." % FishingSession.EATING_COOLDOWN_SECONDS, 13, FantasyUI.MUTED, true))
		details.add_child(_action_button("Eat fish", _eat_fish.bind(selected_item_name)))
		details.add_child(_action_button("Quick food [H]" if player.quick_food_name == selected_item_name else "Set quick food [H]", _set_quick_food.bind(selected_item_name)))
	if selected.has("sell_value"):
		details.add_child(_label("Sell value: %d gold each" % int(selected.sell_value), 13, FantasyUI.GOLD, true))
	if selected.has("cooking_level"):
		details.add_child(_label("Campfire cooking: level %d\nBurn chance now: %.1f%% (0%% at level %d)\nSuccessful cook: %d XP, %.1f seconds" % [int(selected.cooking_level), CookingSession.burn_chance(player.get_skill_level("cooking"), selected) * 100.0, int(selected.no_burn_level), int(selected.cooking_xp), float(selected.cooking_seconds)], 13, FantasyUI.TEAL, true))
	if selected.has("fishing_level"):
		var requirement := "Fishing skill requirement: %d." if String(selected.get("type", "")) == "Food" else "Requires Fishing %d."
		details.add_child(_label((requirement % int(selected.fishing_level)) + " " + String(selected.get("description", "")), 13, FantasyUI.TEAL, true))
	if selected.has("required_bait_grade"):
		details.add_child(_label("Required bait grade: %d (exact match)" % int(selected.required_bait_grade), 13, FantasyUI.GOLD, true))
	if selected.has("minimum_catch_distance"):
		details.add_child(_label("Catch distance: at least %d ft\nFight strength: %.2f" % [int(selected.minimum_catch_distance), float(selected.get("fish_strength", 0.65))], 13, FantasyUI.TEAL, true))
	if selected.has("cast_distance"):
		var fishing_preview := FishingSession.new(player)
		fishing_preview.rod = selected_item_name
		details.add_child(_label("Range now: %.1f ft\nFull range: %d ft at Fishing %d\nInput strength: %.2f\nSkill pull resistance: %.1f%%\nReel speed: %.1f ft/s" % [fishing_preview.effective_max_cast_distance(), int(selected.cast_distance), fishing_preview.cast_mastery_level(), fishing_preview.input_strength(), (1.0 - 1.0 / fishing_preview.skill_pull_tolerance()) * 100, float(selected.get("reel_speed", 9.0))], 13, FantasyUI.TEAL, true))
	details.add_child(_action_button("View equipment", select_page.bind(Page.EQUIPMENT)))

func _build_skills(player: PlayerState) -> void:
	var skills := _column(body)
	_skill_session_header = HBoxContainer.new()
	_skill_session_header.add_theme_constant_override("separation", 10)
	skills.add_child(_skill_session_header)
	_skill_session_label = _label("Training session: 00:00:00", 14, FantasyUI.TEAL)
	_skill_session_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_session_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_skill_session_label.tooltip_text = TRAINING_SESSION_TOOLTIP
	_skill_session_header.add_child(_skill_session_label)
	var reset := _action_button("Reset session", _reset_skill_training_session)
	reset.custom_minimum_size.x = 150
	reset.tooltip_text = TRAINING_SESSION_TOOLTIP
	_skill_session_header.add_child(reset)
	var scroll := _scroll("SkillsScroll")
	skills.add_child(scroll)
	var grid := _grid(2, 12)
	scroll.add_child(grid)
	for skill: String in SkillProgression.SKILL_IDS:
		var progress := player.get_skill_progress(skill)
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(365, 240)
		card.add_theme_stylebox_override("panel", _card_style(false))
		grid.add_child(card)
		var column := _column(card, 5)
		var heading := HBoxContainer.new()
		heading.add_theme_constant_override("separation", 8)
		column.add_child(heading)
		heading.add_child(_icon(skill, 24))
		var name_label := _label(String(progress.get("name", skill)), 18, FantasyUI.IVORY)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_child(name_label)
		heading.add_child(_label("%d / 100" % int(progress.get("level", 1)), 20, FantasyUI.GOLD))
		column.add_child(_label(String(SKILL_EFFECTS[skill]), 12, FantasyUI.MUTED, true))
		var source := _label(SkillProgression.experience_source_text(skill), 12, FantasyUI.IVORY, true)
		column.add_child(source)
		var experience := int(progress.get("experience", 0))
		var level := int(progress.get("level", 1))
		if skill in ["attack", "defense"]:
			column.add_child(_label(_equipment_tier_text(skill, level), 12, FantasyUI.GOLD, true))
		var current_threshold := int(progress.get("experience_for_current_level", 0))
		var next_threshold := int(progress.get("experience_for_next_level", 0))
		column.add_child(_label("%s XP" % _number(experience), 12, FantasyUI.TEAL))
		var bar := ProgressBar.new()
		bar.custom_minimum_size.y = 8
		bar.show_percentage = false
		bar.max_value = 100.0
		bar.value = 100.0 if level == SkillProgression.MAX_LEVEL else 100.0 * float(experience - current_threshold) / float(maxi(1, next_threshold - current_threshold))
		column.add_child(bar)
		var hint := "Mastered" if level == SkillProgression.MAX_LEVEL else "%s XP to level %d" % [_number(int(progress.get("experience_to_next_level", 0))), level + 1]
		column.add_child(_label(hint, 11, FantasyUI.MUTED))
		var session_label := _label("", 12, FantasyUI.TEAL, true)
		session_label.mouse_filter = Control.MOUSE_FILTER_PASS
		session_label.tooltip_text = TRAINING_SESSION_TOOLTIP
		column.add_child(session_label)
		_skill_session_labels[skill] = session_label

func _build_spells(player: PlayerState) -> void:
	var left := _column(body)
	left.add_child(_label("Spellbook", 18, FantasyUI.IVORY))
	left.add_child(_label("Magic level %d  ·  Choose an unlocked spell to ready it." % player.get_magic_level(), 12, FantasyUI.MUTED, true))
	var scroll := _scroll("SpellListScroll")
	left.add_child(scroll)
	var grid := _grid(2, 8)
	scroll.add_child(grid)
	var spells := GameData.list_spells()
	spells.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_level := int(first.get("unlock_level", 1))
		var second_level := int(second.get("unlock_level", 1))
		return String(first.get("name", "")) < String(second.get("name", "")) if first_level == second_level else first_level < second_level
	)
	for spell: Dictionary in spells:
		var spell_id := String(spell.get("id", ""))
		var unlocked := GameData.is_spell_unlocked(spell_id, player.get_magic_level())
		var button := _card_button(Vector2(254, 84), spell_id == player.selected_spell_id)
		button.disabled = not unlocked
		var spell_unlock_level := int(spell.get("unlock_level", 1))
		button.tooltip_text = "Requires Magic level %d" % spell_unlock_level if not unlocked else "Ready " + String(spell.get("name", "spell"))
		button.tooltip_text += "\n%s" % _spell_experience_text(spell_unlock_level)
		button.pressed.connect(select_spell.bind(spell_id))
		var column := _button_column(button, 5)
		var heading := HBoxContainer.new()
		heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		heading.add_theme_constant_override("separation", 6)
		column.add_child(heading)
		heading.add_child(_icon("magic", 18))
		heading.add_child(_label(String(spell.get("name", "Spell")), 14, FantasyUI.IVORY if unlocked else FantasyUI.MUTED))
		column.add_child(_label("Magic %d  ·  %d mana%s" % [int(spell.get("unlock_level", 1)), int(spell.get("mana_cost", 0)), "  ·  Locked" if not unlocked else ""], 11, FantasyUI.TEAL if unlocked else FantasyUI.MUTED))
		grid.add_child(button)
	var details := _details_column("SpellDetails")
	var selected := GameData.get_spell(player.selected_spell_id)
	if selected.is_empty():
		details.add_child(_label("Choose a spell", 19, FantasyUI.GOLD))
		return
	details.add_child(_icon("spells", 38))
	details.add_child(_label(String(selected.get("name", "Spell")), 20, FantasyUI.GOLD, true))
	details.add_child(_label("%s  ·  Magic %d" % [String(selected.get("school", "arcane")).capitalize(), int(selected.get("unlock_level", 1))], 13, FantasyUI.TEAL))
	details.add_child(_label("Mana: %d\nCast time: %.1f seconds\nRange: %.0f tiles" % [int(selected.get("mana_cost", 0)), float(selected.get("cast_time_seconds", 0.0)), float(selected.get("range", 0.0))], 14, FantasyUI.IVORY, true))
	var effect_text := _spell_effect_text(selected)
	if not effect_text.is_empty():
		details.add_child(_label(effect_text, 13, FantasyUI.IVORY, true))
	var unlock_level := int(selected.get("unlock_level", 1))
	var failure := SkillProgression.magic_cast_failure_chance(player.get_magic_level(), unlock_level)
	details.add_child(HSeparator.new())
	details.add_child(_label(_spell_experience_text(unlock_level), 13, FantasyUI.IVORY, true))
	details.add_child(_label("Cast success: %.0f%%\nFailure chance: %.0f%%" % [(1.0 - failure) * 100.0, failure * 100.0], 14, FantasyUI.TEAL, true))
	var mastery_level := unlock_level + SkillProgression.MAGIC_LEVELS_TO_MASTER_SPELL
	var mastery := "Mastered: casting cannot fail." if is_zero_approx(failure) else "Failure drops by 1%% per Magic level. Mastery at Magic %d." % mastery_level
	if mastery_level > SkillProgression.MAX_LEVEL:
		mastery += " Mastery exceeds the current skill cap."
	details.add_child(_label(mastery, 11, FantasyUI.MUTED, true))
	var cast := _action_button("Cast now [E]", _cast_selected_spell)
	cast.disabled = player.current_mana < int(selected.get("mana_cost", 0)) or player.current_hp <= 0
	details.add_child(cast)
	details.add_child(_label("Damage spells still make their normal hit checks. Hostile spells use your current target.", 11, FantasyUI.MUTED, true))

func _build_equipment(player: PlayerState) -> void:
	var left := _column(body)
	left.add_child(_label("Equipment", 18, FantasyUI.IVORY))
	left.add_child(_label("Left-click to select. Right-click to unequip into your backpack.", 12, FantasyUI.MUTED, true))
	var scroll := _scroll("EquipmentScroll")
	left.add_child(scroll)
	var grid := _grid(2, 8)
	scroll.add_child(grid)
	for entry: Array in SLOT_LAYOUT:
		var slot := String(entry[1])
		var item: Dictionary = player.quiver_item if slot == "quiver" else player.equipment.get(slot, {})
		var button := _card_button(Vector2(254, 96), slot == selected_equipment_slot)
		button.disabled = item.is_empty()
		if not item.is_empty():
			button.tooltip_text = "%s\n%s" % [String(item.get("name", "Item")), _equipment_requirement_text(player, item)]
		button.pressed.connect(_inspect_equipment.bind(slot))
		button.gui_input.connect(_equipment_context_input.bind(slot, button))
		var column := _button_column(button, 5)
		var heading := HBoxContainer.new()
		heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		heading.add_theme_constant_override("separation", 7)
		column.add_child(heading)
		heading.add_child(_item_icon(item, 32))
		heading.add_child(_label(String(entry[0]), 13, FantasyUI.GOLD if not item.is_empty() else FantasyUI.MUTED))
		var item_name := String(item.get("name", "Empty"))
		if slot == "quiver" and not item.is_empty():
			item_name = "%s × %d" % [item_name, player.quiver_amount]
		column.add_child(_label(item_name, 12, FantasyUI.IVORY if not item.is_empty() else FantasyUI.MUTED, true))
		grid.add_child(button)
	var details := _details_column("EquipmentDetails")
	var inspected: Dictionary = player.quiver_item if selected_equipment_slot == "quiver" else player.equipment.get(selected_equipment_slot, {})
	if not inspected.is_empty():
		details.add_child(_item_icon(inspected, 48))
		details.add_child(_label(String(inspected.get("name", "Item")), 19, FantasyUI.GOLD, true))
		details.add_child(_label("Tier %d" % int(inspected.get("tier", 1)), 13, FantasyUI.TEAL))
		var meets_requirement := EquipmentProgression.can_equip(player, inspected)
		details.add_child(_label(_equipment_requirement_text(player, inspected), 13, FantasyUI.TEAL if meets_requirement else FantasyUI.GOLD, true))
		var bonuses := _item_bonus_text(inspected)
		if not bonuses.is_empty():
			details.add_child(_label(bonuses, 13, FantasyUI.IVORY, true))
		details.add_child(HSeparator.new())
	_build_battle_stats(details, player)
	details.add_child(_action_button("Open backpack", select_page.bind(Page.INVENTORY)))

func _build_combat(player: PlayerState) -> void:
	var left := _column(body, 11)
	left.add_child(_label("Combat styles", 20, FantasyUI.GOLD))
	var weapon: Dictionary = player.equipment.get("weapon", {})
	left.add_child(_label("Current weapon: " + String(weapon.get("name", "Unarmed")), 15, FantasyUI.IVORY, true))
	left.add_child(_label("Your weapon determines which combat styles you can use.", 12, FantasyUI.MUTED, true))
	var grid := _grid(2, 9)
	left.add_child(grid)
	var supported := PlayerStats.valid_styles_for_weapon(weapon)
	var current := String(player.get_combat_stats().get("style", "blunt"))
	for style: String in ["stab", "slash", "blunt", "ranged", "magic"]:
		var available := style in supported
		var button := _card_button(Vector2(244, 84), current == style)
		button.disabled = not available
		button.pressed.connect(select_combat_style.bind(style))
		var column := _button_column(button, 7)
		var heading := HBoxContainer.new()
		heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		heading.add_theme_constant_override("separation", 7)
		column.add_child(heading)
		heading.add_child(_icon("magic" if style == "magic" else ("range" if style == "ranged" else "attack"), 20))
		heading.add_child(_label(String(STYLE_NAMES[style]), 17, FantasyUI.GOLD if current == style else FantasyUI.IVORY))
		column.add_child(_label("Readied" if current == style else ("Select style" if available else "Weapon unsupported"), 12, FantasyUI.TEAL if available else FantasyUI.MUTED))
		grid.add_child(button)
	var details := _details_column("CombatDetails")
	_build_battle_stats(details, player)
	details.add_child(_action_button("Manage equipment", select_page.bind(Page.EQUIPMENT)))

func _build_battle_stats(column: VBoxContainer, player: PlayerState) -> void:
	var stats := player.get_combat_stats()
	column.add_child(_icon("combat", 36))
	column.add_child(_label("Battle readiness", 19, FantasyUI.GOLD, true))
	column.add_child(_label("Combat level %d / 150" % player.get_combat_level(), 14, FantasyUI.TEAL))
	column.add_child(HSeparator.new())
	var accuracy_text := "Accuracy: %.1f%%" % (float(stats.get("accuracy", 0.0)) * 100.0)
	if float(stats.get("melee_attack_roll", -1.0)) >= 0.0:
		accuracy_text = "Melee strength: %+d\nAttack roll: %.0f\nHit chance depends on target defense." % [int(stats.melee_strength_bonus), float(stats.melee_attack_roll)]
	column.add_child(_label("Style: %s\nDamage: %d–%d\n%s\nAttack interval: %.2f sec\nAttack range: %.1f tiles" % [String(STYLE_NAMES.get(String(stats.get("style", "blunt")), "Crush")), int(stats.get("min_damage", 1)), int(stats.get("max_damage", 1)), accuracy_text, float(stats.get("attack_interval_seconds", 0.0)), float(stats.get("attack_range", 0.0))], 14, FantasyUI.IVORY, true))
	var weapon: Dictionary = player.equipment.get("weapon", {})
	column.add_child(_label("Weapon\n" + String(weapon.get("name", "Unarmed")), 13, FantasyUI.MUTED, true))

func _handle_equip(item_name: String) -> void:
	var player := _player()
	if player == null:
		return
	_set_status(player.equip_item(item_name))
	_refresh_combat_view()
	refresh_view()

func _handle_unequip(slot_name: String) -> void:
	var player := _player()
	if player == null:
		return
	_set_status(player.unequip_slot(slot_name))
	_refresh_combat_view()
	refresh_view()

func _refresh_combat_view() -> void:
	if is_instance_valid(game) and game.has_method("_refresh_player_actor_from_player"):
		game.call("_refresh_player_actor_from_player")

func _inspect_item(item_name: String, slot_index: int = -1) -> void:
	selected_item_name = item_name
	selected_inventory_slot_index = slot_index
	refresh_view()

func _inspect_equipment(slot: String) -> void:
	selected_equipment_slot = slot
	refresh_view()

func _inventory_context_input(event: InputEvent, item_name: String, source: Control) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT:
		return
	source.accept_event()
	var at: Vector2 = source.get_global_transform_with_canvas() * event.position
	_inspect_item(item_name, int(source.get_meta("inventory_slot", -1)))
	var item := GameData.get_item_by_name(item_name)
	var amount := int(_player().backpack.get(item_name, 0))
	var requirement := _equipment_requirement_text(_player(), item)
	var equip_label := "Equip" if EquipmentProgression.requirements(item).is_empty() or requirement == "No skill requirement" else "Equip - %s" % requirement
	var entries: Array[Dictionary] = [
		{"label": equip_label, "disabled": item.get("slot", null) == null or not EquipmentProgression.can_equip(_player(), item), "action": _handle_equip.bind(item_name)},
		{"label": "Drop", "action": _handle_drop.bind(item_name, 1)}
	]
	if amount > 1 and InventorySystem.is_stackable(item_name):
		entries.append({"label": "Drop all (%d)" % amount, "action": _handle_drop.bind(item_name, amount)})
	if int(item.get("food_healing", 0)) > 0:
		entries.push_front({"label": "Eat fish", "action": _eat_fish.bind(item_name)})
		entries.append({"label": "Set quick food [H]", "action": _set_quick_food.bind(item_name)})
	game.get("context_menu").show_options(item_name, entries, at)

func _eat_fish(item_name: String) -> void:
	var result: Dictionary = game.eat_food(item_name)
	_set_status(String(result.message))
	refresh_view()

func _set_quick_food(item_name: String) -> void:
	if game.set_quick_food(item_name):
		_set_status("Quick food: %s. Press H or click its HUD button to eat." % item_name)
	else:
		_set_status("That food is no longer in your backpack.")
	refresh_view()

func _equipment_context_input(event: InputEvent, slot: String, source: Control) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT:
		return
	source.accept_event()
	var at: Vector2 = source.get_global_transform_with_canvas() * event.position
	_inspect_equipment(slot)
	var player := _player()
	var item: Dictionary = player.quiver_item if slot == "quiver" else player.equipment.get(slot, {})
	if item.is_empty():
		return
	var entries: Array[Dictionary] = [{"label": "Unequip", "action": _handle_unequip.bind(slot)}]
	game.get("context_menu").show_options(String(item.get("name", "Equipment")), entries, at)

func _handle_drop(item_name: String, quantity: int) -> void:
	if not InventorySystem.is_stackable(item_name):
		quantity = 1
	if bool(game.call("drop_inventory_item", item_name, quantity)):
		_set_status("Dropped %d × %s on the ground." % [quantity, item_name])
	else:
		_set_status("That item is no longer in your backpack.")
	refresh_view()

func _cast_selected_spell() -> void:
	var player := _player()
	if player == null or player.selected_spell_id.is_empty():
		return
	var spell := GameData.get_spell(player.selected_spell_id)
	if not GameData.is_spell_unlocked(player.selected_spell_id, player.get_magic_level()):
		_set_status("Your Magic level does not meet this spell's requirement.")
		return
	if player.current_hp <= 0:
		_set_status("Restore your health before casting.")
		return
	if player.current_mana < int(spell.get("mana_cost", 0)):
		_set_status("You need more mana to cast this spell.")
		return
	game.set("spell_cast_requested", true)
	_set_status("Casting %s. Hostile spells require your current target." % String(spell.get("name", "spell")))

func _repair_spell_selection() -> void:
	var player := _player()
	if player != null and not GameData.is_spell_unlocked(player.selected_spell_id, player.get_magic_level()):
		player.selected_spell_id = ""
		player.cycle_known_spell(1)

func _update_header() -> void:
	var player := _player()
	if player == null or header_stats == null:
		return
	header_stats.text = "Combat %d / 150     Health %d / %d     Mana %d / %d     Gold %s" % [player.get_combat_level(), player.current_hp, player.get_max_hp(), player.current_mana, player.get_max_mana(), _number(player.gold)]

func _training_session() -> Object:
	if not is_instance_valid(game):
		return null
	# Older fixtures may supply a game node without the optional session field.
	for property: Dictionary in game.get_property_list():
		if String(property.get("name", "")) == "skill_training_session":
			return game.get("skill_training_session") as Object
	return null

func _update_skill_training_readout() -> void:
	if selected_page != Page.SKILLS or _skill_session_header == null:
		return
	var session := _training_session()
	var available := session != null and session.has_method("get_progress") and session.has_method("get_elapsed_seconds")
	_skill_session_header.visible = available
	if available:
		_skill_session_label.text = "Training session: %s" % _format_session_time(float(session.call("get_elapsed_seconds")))
	for skill: String in _skill_session_labels:
		var label: Label = _skill_session_labels[skill]
		label.visible = available
		if not available:
			continue
		var progress: Dictionary = session.call("get_progress", skill)
		var rate := "%s XP/hour" % _number(int(progress.get("experience_per_hour", 0))) if bool(progress.get("rate_ready", false)) else "Measuring..."
		label.text = "This session: %s XP\nRate: %s" % [_number(int(progress.get("experience_gained", 0))), rate]

func _reset_skill_training_session() -> void:
	if is_instance_valid(game) and game.has_method("reset_skill_training_session"):
		game.call("reset_skill_training_session")
		_update_skill_training_readout()

func _format_session_time(elapsed_seconds: float) -> String:
	var seconds := maxi(0, floori(elapsed_seconds))
	return "%02d:%02d:%02d" % [floori(float(seconds) / 3600.0), floori(float(seconds % 3600) / 60.0), seconds % 60]

func _spell_experience_text(unlock_level: int) -> String:
	return "Successful cast: %s Magic XP\nActual damage: %d Magic XP per point\nFailed cast: 0 XP" % [_number(SkillProgression.magic_experience_for_cast(unlock_level)), int(SkillProgression.XP_PER_DAMAGE.get("magic", 0))]

func _equipment_requirement_text(player: PlayerState, item: Dictionary) -> String:
	var unmet := EquipmentProgression.unmet_requirement_text(player, item)
	return EquipmentProgression.requirement_text(item) if unmet.is_empty() else unmet

func _equipment_tier_text(skill: String, level: int) -> String:
	var tier := EquipmentProgression.tier_for_level(level)
	var text := "%s tier unlocked: %d" % ["Weapon" if skill == "attack" else "Armor", tier]
	var next_level := EquipmentProgression.required_level_for_tier(tier + 1)
	if next_level <= SkillProgression.MAX_LEVEL:
		text += "\nNext: Tier %d at %s %d" % [tier + 1, skill.capitalize(), next_level]
	else:
		text += "\nMaximum skill requirement reached."
	return text

func _set_status(message: String) -> void:
	status_text = message
	if footer != null:
		footer.text = message

func _state_signature() -> String:
	var player := _player()
	if player == null:
		return ""
	var state := {"page": selected_page, "levels": player.levels, "backpack": player.backpack, "equipment": player.get_equipped_names(), "quiver_amount": player.quiver_amount, "style": player.attack_style, "spell": player.selected_spell_id}
	if selected_page == Page.SKILLS:
		state["experience"] = player.skill_experience
	elif selected_page == Page.SPELLS:
		state["mana"] = player.current_mana
		state["alive"] = player.current_hp > 0
	return JSON.stringify(state)

func _player() -> PlayerState:
	if not is_instance_valid(game):
		return null
	return game.get("player") as PlayerState

func _column(parent: Node, separation: int = 8) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", separation)
	parent.add_child(column)
	return column

func _grid(columns: int, separation: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", separation)
	grid.add_theme_constant_override("v_separation", separation)
	return grid

func _scroll(scroll_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = scroll_name
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_scrolls.append(scroll)
	return scroll

func _details_column(scroll_name: String) -> VBoxContainer:
	var scroll := _scroll(scroll_name)
	scroll.custom_minimum_size.x = 235
	scroll.size_flags_horizontal = Control.SIZE_FILL
	body.add_child(scroll)
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _card_style(false))
	scroll.add_child(card)
	return _column(card, 10)

func _label(text: String, font_size: int, color: Color, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var readable_size := FantasyUI.text_size(font_size)
	label.add_theme_font_size_override("font_size", readable_size)
	if font_size >= 18:
		label.add_theme_font_override("font", FantasyUI.display_font())
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.custom_minimum_size.y = ceilf(float(readable_size) * 1.35)
	return label

func _icon(key: String, side: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = FantasyUI.icon(key)
	icon.custom_minimum_size = Vector2(side, side)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func _item_icon(item: Dictionary, side: float) -> TextureRect:
	var icon := _icon(_item_icon_key(item) if not item.is_empty() else "equipment", side)
	var item_texture := ItemVisualLibrary.texture(String(item.get("name", "")))
	if item_texture != null:
		icon.texture = item_texture
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return icon

func _action_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 42
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(action)
	return button

func _card_style(selected: bool, hover: bool = false) -> StyleBoxFlat:
	var style := FantasyUI.box(FantasyUI.SLATE if selected else FantasyUI.NAVY, FantasyUI.GOLD if selected else Color("4a5d70"))
	if hover:
		style.bg_color = style.bg_color.lightened(0.12)
		style.border_color = FantasyUI.TEAL
	style.set_corner_radius_all(4)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _card_button(minimum: Vector2, selected: bool = false) -> Button:
	var button := Button.new()
	button.custom_minimum_size = minimum
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_stylebox_override("normal", _card_style(selected))
	button.add_theme_stylebox_override("hover", _card_style(selected, true))
	button.add_theme_stylebox_override("pressed", _card_style(true))
	button.add_theme_stylebox_override("disabled", FantasyUI.box(FantasyUI.INK, Color("35414d")))
	return button

func _button_column(button: Button, margin_size: int) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, margin_size)
	button.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	return column

func _restore_scroll() -> void:
	for scroll: ScrollContainer in _scrolls:
		if is_instance_valid(scroll):
			scroll.scroll_vertical = int(_scroll_positions.get(String(scroll.name), 0))

func _update_layout() -> void:
	if panel == null or not is_inside_tree():
		return
	var viewport_size := FantasyUI.viewport_size(self)
	panel.position = Vector2(22, 52)
	panel.size = Vector2(minf(PANEL_SIZE.x, viewport_size.x - 44.0), minf(PANEL_SIZE.y, viewport_size.y - 76.0))

func _item_icon_key(item: Dictionary) -> String:
	var slot := String(item.get("slot", "")) if item.get("slot", null) != null else ""
	if slot == "weapon":
		var bonuses: Dictionary = item.get("attack_bonuses", {})
		if int(bonuses.get("magic", 0)) > 0:
			return "magic"
		if int(bonuses.get("ranged", 0)) > 0:
			return "range"
		return "attack"
	if slot == "shield":
		return "defense"
	if slot == "quiver":
		return "range"
	return "equipment" if not slot.is_empty() else "bag"

func _item_bonus_text(item: Dictionary) -> String:
	var lines: Array[String] = []
	if item.has("melee_strength_bonus"):
		lines.append("Melee strength: %+d" % int(item.melee_strength_bonus))
	# Crafting items and food deliberately have a null slot, which String() cannot accept.
	if item.get("slot", null) == "weapon":
		for style: String in PlayerStats.valid_styles_for_weapon(item):
			var profile := PlayerStats.base_attack_profile(item, style)
			if not profile.is_empty():
				lines.append("%s base: %d–%d damage, %.0f%% accuracy" % [String(STYLE_NAMES[style]), int(profile.min_damage), int(profile.max_damage), float(profile.accuracy) * 100.0])
			lines.append("%s reach: %.0f tiles" % [String(STYLE_NAMES[style]), PlayerStats.get_attack_range(style, item)])
		lines.append("Attack interval: %.2f sec" % PlayerStats.weapon_attack_interval_seconds(item))
	var attack: Dictionary = item.get("attack_bonuses", {})
	for style: String in STYLE_NAMES:
		if int(attack.get(style, 0)) != 0 or (item.has("melee_strength_bonus") and style in PlayerStats.MELEE_STYLES):
			lines.append("%s %s: %+d" % [String(STYLE_NAMES[style]), "accuracy" if item.has("melee_strength_bonus") and style in PlayerStats.MELEE_STYLES else "attack", int(attack[style])])
	var defense: Dictionary = item.get("defence_bonuses", {})
	for style: String in STYLE_NAMES:
		if not is_zero_approx(float(defense.get(style, 0.0))):
			lines.append("%s defense: %s" % [String(STYLE_NAMES[style]), str(defense[style])])
	var accuracy_bonus := float(item.get("accuracy_bonus", 0.0))
	if not is_zero_approx(accuracy_bonus):
		lines.append("Accuracy bonus: %+.1f%%" % (accuracy_bonus * 100.0))
	return "\n".join(lines)

func _spell_effect_text(spell: Dictionary) -> String:
	match String(spell.get("kind", "projectile")):
		"heal":
			return "Restores %d health to an ally." % int(spell.get("healing", 0))
		"wall":
			return "Creates a projectile-blocking wall for %.0f seconds." % float(spell.get("duration_seconds", 0.0))
		"knockback":
			return "Pushes the target back %.0f tiles." % float(spell.get("knockback_distance", 0.0))
		_:
			var text := "Base damage: %d" % int(spell.get("damage", 0))
			if float(spell.get("area_radius", 0.0)) > 0.0:
				text += "\nArea radius: %.0f tiles" % float(spell.get("area_radius", 0.0))
			return text

func _number(value: int) -> String:
	var digits := str(value)
	var result := ""
	for index in range(digits.length()):
		if index > 0 and (digits.length() - index) % 3 == 0:
			result += ","
		result += digits[index]
	return result

func _empower_orb(element: String) -> void:
	if game.combat.active_spell_casts.has(game.player.entity_id):
		status_text = "Finish casting before empowering an orb."
		refresh_view()
		return
	var result: Dictionary = preload("res://scripts/crafting_service.gd").empower_orb(game.player, element)
	status_text = String(result.message)
	refresh_view()
