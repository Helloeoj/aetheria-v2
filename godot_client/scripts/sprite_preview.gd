class_name SpritePreview
extends Control

signal closed
signal spawn_requested(monster_id: int)

const DIRECTIONS := ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"]
const VECTORS := [Vector2.DOWN, Vector2(1, 1), Vector2.RIGHT, Vector2(1, -1), Vector2.UP, Vector2(-1, -1), Vector2.LEFT, Vector2(-1, 1)]

var skin_ids: Array[String] = []
var skin_list: ItemList
var direction_picker: OptionButton
var action_picker: OptionButton
var equipment_picker: OptionButton
var shield_picker: OptionButton
var socket_check: CheckButton
var title_label: Label
var coverage_label: Label
var preview_area: ColorRect
var spawn_button: Button
var selected_monster_id := -1
var actor: ActorSprite
var attack_elapsed := 0.0
var equipment_names: Array[String] = ["", "Iron Longsword"]
var shield_names: Array[String] = ["", "Adamantite Kiteshield"]
var armor_slot_picker: OptionButton
var armor_item_picker: OptionButton
var armor_slots: Array[String] = ["head", "chest", "legs", "cape", "neck", "ring"]
var preview_armor: Dictionary = {}
var armor_names: Array[String] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = Color(0.035, 0.05, 0.075, 0.98)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 28)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	margin.add_child(columns)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 280
	columns.add_child(sidebar)
	var heading := Label.new()
	heading.text = "CHARACTER SPRITES"
	heading.add_theme_font_size_override("font_size", 24)
	sidebar.add_child(heading)
	var description := Label.new()
	description.text = "Select a character to inspect.\nThe game pauses while this is open."
	description.add_theme_color_override("font_color", Color(0.7, 0.77, 0.85))
	sidebar.add_child(description)
	skin_list = ItemList.new()
	skin_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(skin_list)
	var catalog: Dictionary = CharacterSpriteLibrary.get_catalog()
	var skins: Dictionary = catalog.get("skins", {})
	for key: String in skins:
		skin_ids.append(key)
		skin_list.add_item(String(skins[key].get("name", key)))
	skin_list.item_selected.connect(_select_skin)
	var close_button := Button.new()
	close_button.text = "Return to game  ·  F7 / Esc"
	close_button.pressed.connect(hide_preview)
	sidebar.add_child(close_button)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 12)
	columns.add_child(details)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 28)
	details.add_child(title_label)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 12)
	details.add_child(controls)
	direction_picker = OptionButton.new()
	for direction: String in DIRECTIONS:
		direction_picker.add_item(direction.capitalize())
	direction_picker.item_selected.connect(_change_direction)
	controls.add_child(direction_picker)
	action_picker = OptionButton.new()
	for action: String in ["Idle", "Walk", "Attack"]:
		action_picker.add_item(action)
	action_picker.item_selected.connect(_change_action)
	controls.add_child(action_picker)
	var hit_button := Button.new()
	hit_button.text = "Test hit"
	hit_button.pressed.connect(func() -> void: actor.play_hurt())
	controls.add_child(hit_button)
	var target_check := CheckButton.new()
	target_check.text = "Target ring"
	target_check.toggled.connect(func(value: bool) -> void: actor.set_targeted(value))
	controls.add_child(target_check)
	var equipment_controls := HFlowContainer.new()
	equipment_controls.add_theme_constant_override("h_separation", 12)
	equipment_controls.add_theme_constant_override("v_separation", 8)
	details.add_child(equipment_controls)
	var equipment_label := Label.new()
	equipment_label.text = "Weapon"
	equipment_controls.add_child(equipment_label)
	equipment_picker = OptionButton.new()
	equipment_picker.add_item("No weapon")
	equipment_picker.add_item("Iron Longsword")
	FittedEquipmentLibrary.initialize()
	for item: Dictionary in FittedEquipmentLibrary.item_data.values():
		if String(item.slot) == "weapon" and String(item.name) != "Iron Longsword":
			equipment_names.append(item.name)
			equipment_picker.add_item(item.name)
	equipment_picker.item_selected.connect(_change_equipment)
	equipment_controls.add_child(equipment_picker)
	var shield_label := Label.new()
	shield_label.text = "Shield"
	equipment_controls.add_child(shield_label)
	shield_picker = OptionButton.new()
	shield_picker.add_item("No shield")
	shield_picker.add_item("Adamantite Kiteshield")
	for item: Dictionary in FittedEquipmentLibrary.item_data.values():
		if String(item.slot) == "shield":
			shield_names.append(item.name)
			shield_picker.add_item(item.name)
	shield_picker.item_selected.connect(_change_shield)
	equipment_controls.add_child(shield_picker)
	socket_check = CheckButton.new()
	socket_check.text = "Show attachment skeleton"
	socket_check.toggled.connect(func(value: bool) -> void: actor.set_socket_debug(value))
	equipment_controls.add_child(socket_check)
	var armor_controls := HFlowContainer.new()
	armor_controls.add_theme_constant_override("h_separation", 8)
	armor_controls.add_theme_constant_override("v_separation", 6)
	details.add_child(armor_controls)
	armor_slot_picker = OptionButton.new()
	for label: String in ["Helmet", "Platebody", "Platelegs", "Cape", "Necklace", "Ring (invisible)"]:
		armor_slot_picker.add_item(label)
	armor_slot_picker.select(1)
	armor_slot_picker.item_selected.connect(_change_armor_slot)
	armor_controls.add_child(armor_slot_picker)
	armor_item_picker = OptionButton.new()
	armor_item_picker.item_selected.connect(_change_armor_item)
	armor_controls.add_child(armor_item_picker)
	for material: String in ["Bronze", "Iron", "Steel", "Clear"]:
		var preset := Button.new()
		preset.text = material + " armor" if material != "Clear" else "Clear armor"
		preset.pressed.connect(_armor_preset.bind(material))
		armor_controls.add_child(preset)
	_change_armor_slot(1)
	preview_area = ColorRect.new()
	preview_area.color = Color(0.085, 0.115, 0.155)
	preview_area.custom_minimum_size.y = 240
	preview_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_child(preview_area)
	actor = ActorSprite.new().configure(Vector2(32, 32), Color(0.15, 0.5, 0.3), "preview")
	actor.collision_layer = 0
	actor.collision_mask = 0
	actor.scale = Vector2(3, 3)
	preview_area.add_child(actor)
	preview_area.resized.connect(_place_actor)
	coverage_label = Label.new()
	coverage_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	coverage_label.custom_minimum_size.y = 80
	coverage_label.add_theme_color_override("font_color", Color(0.73, 0.82, 0.9))
	details.add_child(coverage_label)
	spawn_button = Button.new()
	spawn_button.pressed.connect(_spawn_selected)
	details.add_child(spawn_button)
	var note := Label.new()
	note.text = "3× preview · crisp pixels · original artwork preserved"
	note.add_theme_color_override("font_color", Color(0.5, 0.62, 0.72))
	details.add_child(note)
	if not skin_ids.is_empty():
		skin_list.select(0)
		_select_skin(0)
	visible = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--equipment-review="):
			_open_equipment_review.call_deferred(argument.get_slice("=", 1))

func _open_equipment_review(material: String) -> void:
	material = material.capitalize()
	if material not in ["Bronze", "Iron", "Steel"]:
		return
	_select_skin(skin_ids.find("peasant"))
	_armor_preset(material)
	equipment_picker.select(equipment_names.find(material + " Longsword"))
	shield_picker.select(shield_names.find(material + " Kiteshield"))
	_change_equipment(equipment_picker.selected)
	show_preview()
	await get_tree().create_timer(0.3).timeout
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--equipment-proof="):
			await RenderingServer.frame_post_draw
			var destination := argument.trim_prefix("--equipment-proof=")
			var result := get_viewport().get_texture().get_image().save_png(destination)
			print("[Equipment preview capture] ", destination, " status=", result)

func show_preview() -> void:
	visible = true
	_place_actor()
	skin_list.grab_focus()

func hide_preview() -> void:
	visible = false
	closed.emit()

func _place_actor() -> void:
	if actor != null:
		actor.position = preview_area.size * Vector2(0.5, 0.78)

func _select_skin(index: int) -> void:
	actor.set_skin(skin_ids[index])
	var supports_equipment := skin_ids[index] == "peasant"
	equipment_picker.disabled = not supports_equipment
	shield_picker.disabled = not supports_equipment
	armor_slot_picker.disabled = not supports_equipment
	armor_item_picker.disabled = not supports_equipment
	socket_check.disabled = not supports_equipment
	_change_equipment(equipment_picker.selected)
	actor.face_direction(VECTORS[direction_picker.selected])
	title_label.text = String(CharacterSpriteLibrary.get_skin(skin_ids[index]).get("name", skin_ids[index]))
	selected_monster_id = -1
	var selected_monster_name := ""
	for template: Dictionary in GameData.monsters:
		if CharacterSpriteLibrary.skin_for_monster(String(template.get("name", ""))) != skin_ids[index]:
			continue
		if selected_monster_id < 0 or String(template.get("name", "")) == title_label.text:
			selected_monster_id = int(template.get("id", -1))
			selected_monster_name = String(template.get("name", ""))
	spawn_button.disabled = selected_monster_id < 0
	spawn_button.text = "Spawn %s in game" % selected_monster_name if selected_monster_id >= 0 else "Player appearance · peasant supports separate equipment assets"
	_change_action(action_picker.selected)
	_update_coverage()

func _change_equipment(index: int) -> void:
	if actor == null:
		return
	var equipment := {}
	if actor.skin_id == "peasant":
		if index > 0 and index < equipment_names.size():
			equipment["weapon"] = {"name": equipment_names[index]}
		var two_handed := EquipmentUtils.is_two_handed(GameData.get_item_by_name(equipment_names[index])) if index > 0 else false
		shield_picker.disabled = two_handed
		if shield_picker.selected > 0 and not two_handed:
			equipment["shield"] = {"name": shield_names[shield_picker.selected]}
		for slot: String in preview_armor:
			equipment[slot] = {"name": preview_armor[slot]}
	actor.set_equipment(equipment)
	actor.set_socket_debug(socket_check.button_pressed and actor.skin_id == "peasant")

func _change_shield(_index: int) -> void:
	_change_equipment(equipment_picker.selected)

func _change_armor_slot(index: int) -> void:
	if armor_item_picker == null:
		return
	armor_item_picker.clear()
	armor_item_picker.add_item("None")
	armor_names = [""]
	var slot := armor_slots[index]
	for item: Dictionary in FittedEquipmentLibrary.item_data.values():
		if String(item.slot) == slot:
			armor_names.append(item.name)
			armor_item_picker.add_item(item.name)
	var selected_name := String(preview_armor.get(slot, ""))
	armor_item_picker.select(maxi(0, armor_names.find(selected_name)))

func _change_armor_item(index: int) -> void:
	var slot := armor_slots[armor_slot_picker.selected]
	if index == 0:
		preview_armor.erase(slot)
	else:
		preview_armor[slot] = armor_names[index]
	_change_equipment(equipment_picker.selected)

func _armor_preset(material: String) -> void:
	preview_armor.clear()
	if material != "Clear":
		for item: Dictionary in FittedEquipmentLibrary.item_data.values():
			if String(item.material) == material and String(item.slot) in armor_slots:
				preview_armor[item.slot] = item.name
	_change_armor_slot(armor_slot_picker.selected)
	_change_equipment(equipment_picker.selected)

func _change_direction(_index: int) -> void:
	actor.face_direction(VECTORS[direction_picker.selected])
	_change_action(action_picker.selected)
	_update_coverage()

func _spawn_selected() -> void:
	if selected_monster_id >= 0:
		hide_preview()
		spawn_requested.emit(selected_monster_id)

func _change_action(index: int) -> void:
	attack_elapsed = 0.0
	actor.cancel_action()
	actor.face_direction(VECTORS[direction_picker.selected])
	if index == 2:
		actor.play_attack(VECTORS[direction_picker.selected])
	elif index == 1:
		actor.update_visual_motion(VECTORS[direction_picker.selected])
	_update_coverage()

func _process(delta: float) -> void:
	if not visible or actor == null:
		return
	if action_picker.selected == 1:
		actor.update_visual_motion(VECTORS[direction_picker.selected])
	elif action_picker.selected == 2:
		attack_elapsed += delta
		if attack_elapsed >= 1.8:
			attack_elapsed = 0.0
			actor.play_attack(VECTORS[direction_picker.selected])

func _update_coverage() -> void:
	if coverage_label == null or actor == null:
		return
	var skin: Dictionary = CharacterSpriteLibrary.get_skin(actor.skin_id)
	var role: String = ["idle", "walk", "attack"][action_picker.selected]
	var clips: Dictionary = skin.get("animations", {})
	var clip: Dictionary = clips.get(role, {})
	var directions: Dictionary = clip.get("directions", {})
	var direction: String = DIRECTIONS[direction_picker.selected]
	var frames: Array = directions.get(direction, [])
	if frames.is_empty():
		var feedback := " Attack uses a brief movement cue." if role == "attack" else ""
		coverage_label.text = "%s / %s: matching static pose. No authored animation was supplied for this action and direction.%s\nAll eight facing poses are available." % [role.capitalize(), direction, feedback]
	else:
		coverage_label.text = "%s / %s: %d authored frames at %s fps.\nAll eight facing poses are available. Missing action directions use their matching static pose." % [role.capitalize(), direction, frames.size(), str(clip.get("fps", 10))]
