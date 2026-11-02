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
var review_paused := false
var pause_button: Button
var frame_label: Label
var zoom_picker: OptionButton
var reference_actor: ActorSprite
var reference_check: CheckButton
var inspection_status: Label
var review_caption: Label
var reference_caption: Label
var review_equipment: Dictionary = {}
var review_surface: SubViewportContainer
var review_viewport: SubViewport
const REVIEW_ZOOMS := [1, 3, 4]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var inspection_layer := CanvasLayer.new()
	inspection_layer.name = "InspectionLayer"
	inspection_layer.layer = 90 # Above the persistent chat overlay (80).
	add_child(inspection_layer)
	visibility_changed.connect(func() -> void: inspection_layer.visible = is_visible_in_tree())
	var background := ColorRect.new()
	background.color = Color(0.035, 0.05, 0.075, 0.98)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inspection_layer.add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 28)
	inspection_layer.add_child(margin)
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
	# Artwork-only tools can use the real rig before catalog/mining rules exist.
	var visual_catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/equipment_visuals.json"))
	for item_name: String in visual_catalog.get("items", {}):
		var definition: Dictionary = visual_catalog.items[item_name]
		if bool(definition.get("preview_only", false)) and definition.get("slot", "") == "weapon" and not equipment_names.has(item_name):
			equipment_names.append(item_name)
			equipment_picker.add_item(item_name)
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
	var review_controls := HFlowContainer.new()
	review_controls.add_theme_constant_override("h_separation", 8)
	details.add_child(review_controls)
	pause_button = Button.new()
	pause_button.text = "Pause"
	pause_button.toggle_mode = true
	pause_button.toggled.connect(_set_review_paused)
	review_controls.add_child(pause_button)
	for offset: int in [-1, 1]:
		var step_button := Button.new()
		step_button.text = "Previous frame" if offset < 0 else "Next frame"
		step_button.pressed.connect(_step_review_frame.bind(offset))
		review_controls.add_child(step_button)
	frame_label = Label.new()
	frame_label.custom_minimum_size.x = 125
	review_controls.add_child(frame_label)
	zoom_picker = OptionButton.new()
	for zoom: int in REVIEW_ZOOMS:
		zoom_picker.add_item("%d×" % zoom)
	zoom_picker.select(1)
	zoom_picker.item_selected.connect(_change_review_zoom)
	review_controls.add_child(zoom_picker)
	reference_check = CheckButton.new()
	reference_check.text = "Original body beside gear"
	reference_check.toggled.connect(_set_reference_visible)
	review_controls.add_child(reference_check)
	var export_button := Button.new()
	export_button.text = "Save PNG + pose"
	export_button.pressed.connect(_export_review_frame)
	review_controls.add_child(export_button)
	var review_scroll := ScrollContainer.new()
	review_scroll.custom_minimum_size.y = 240
	review_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(review_scroll)
	review_surface = SubViewportContainer.new()
	review_surface.stretch = true
	review_surface.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	review_surface.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	review_surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
	review_surface.custom_minimum_size = Vector2(240,240)
	review_scroll.add_child(review_surface)
	review_viewport = SubViewport.new()
	review_viewport.size = Vector2i(240,240)
	review_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	review_surface.add_child(review_viewport)
	preview_area = ColorRect.new()
	preview_area.color = Color(0.085, 0.115, 0.155)
	preview_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	review_viewport.add_child(preview_area)
	preview_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	actor = ActorSprite.new().configure(Vector2(32, 32), Color(0.15, 0.5, 0.3), "preview")
	actor.collision_layer = 0
	actor.collision_mask = 0
	actor.scale = Vector2(3, 3)
	preview_area.add_child(actor)
	reference_actor = ActorSprite.new().configure(Vector2(32, 32), Color.BLUE, "preview_reference")
	reference_actor.collision_layer = 0
	reference_actor.collision_mask = 0
	reference_actor.set_process(false)
	reference_actor.visible = false
	preview_area.add_child(reference_actor)
	review_caption = Label.new()
	review_caption.position = Vector2(12, 8)
	review_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_area.add_child(review_caption)
	reference_caption = Label.new()
	reference_caption.text = "Original body · same pose"
	reference_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reference_caption.visible = false
	preview_area.add_child(reference_caption)
	actor.animated_sprite.frame_changed.connect(_refresh_review_frame)
	actor.animated_sprite.animation_changed.connect(_refresh_review_frame)
	preview_area.resized.connect(_place_actor)
	coverage_label = Label.new()
	coverage_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	coverage_label.custom_minimum_size.y = 80
	coverage_label.add_theme_color_override("font_color", Color(0.73, 0.82, 0.9))
	details.add_child(coverage_label)
	spawn_button = Button.new()
	spawn_button.pressed.connect(_spawn_selected)
	details.add_child(spawn_button)
	inspection_status = Label.new()
	inspection_status.text = "Nearest pixels · PNG export freezes the current pose · visual approval pending"
	inspection_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	inspection_status.add_theme_color_override("font_color", Color(0.5, 0.62, 0.72))
	details.add_child(inspection_status)
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
		var compare := reference_actor != null and reference_actor.visible
		var sprite := actor.animated_sprite
		var dimensions := Vector2(sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame).get_size())
		var body: Rect2 = sprite.transform * Rect2(sprite.offset - dimensions * 0.5, dimensions)
		if not actor.weapon_animation_family().is_empty():
			body=body.grow(24.0 * sprite.scale.x)
		var above := maxf(0.0, -body.position.y * actor.scale.y)
		var below := maxf(0.0, body.end.y * actor.scale.y)
		# Keep the entire native frame and foot shadow at the requested zoom.
		# Large skins scroll; exports read the full canvas, never the visible crop.
		review_surface.custom_minimum_size = Vector2(ceilf(body.size.x * actor.scale.x + 48) * (2 if compare else 1), maxf(240, ceilf(above + below + 56)))
		var foot_y := maxf(above + 32, preview_area.size.y - below - 24)
		actor.position = Vector2(roundf(preview_area.size.x * (0.28 if compare else 0.5)), roundf(foot_y))
		if reference_actor != null:
			reference_actor.position = Vector2(roundf(preview_area.size.x * 0.72), roundf(foot_y))
		if reference_caption != null:
			reference_caption.position = Vector2(roundf(preview_area.size.x * 0.57), 8)

func _select_skin(index: int) -> void:
	if index < 0 or index >= skin_ids.size():
		return
	actor.set_skin(skin_ids[index])
	reference_actor.set_skin(skin_ids[index])
	reference_actor.animated_sprite.pause()
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
	review_equipment = equipment.duplicate(true)
	actor.set_equipment(equipment)
	actor.set_socket_debug(socket_check.button_pressed and actor.skin_id == "peasant")
	_change_action(action_picker.selected)

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
	if review_paused:
		actor.animated_sprite.set_frame_and_progress(0, 0.0)
		actor.animated_sprite.pause()
	_place_actor()
	_refresh_review_frame()
	_update_coverage()

func _process(delta: float) -> void:
	if not visible or actor == null:
		return
	_refresh_review_frame()
	if review_paused:
		return
	if action_picker.selected == 1:
		actor.update_visual_motion(VECTORS[direction_picker.selected])
	elif action_picker.selected == 2:
		attack_elapsed += delta
		if attack_elapsed >= 1.8:
			attack_elapsed = 0.0
			actor.play_attack(VECTORS[direction_picker.selected])

func _set_review_paused(value: bool) -> void:
	review_paused = value
	pause_button.set_pressed_no_signal(value)
	pause_button.text = "Resume" if value else "Pause"
	actor.set_process(not value)
	if value:
		actor.animated_sprite.pause()
	else:
		actor.animated_sprite.play()
	_refresh_review_frame()

func _step_review_frame(offset: int) -> void:
	_set_review_paused(true)
	var sprite := actor.animated_sprite
	var count := sprite.sprite_frames.get_frame_count(sprite.animation)
	if count > 0:
		sprite.set_frame_and_progress(posmod(sprite.frame + offset, count), 0.0)
	actor.attachment_rig.sync_pose()
	_refresh_review_frame()

func _change_review_zoom(index: int) -> void:
	zoom_picker.select(index)
	actor.scale = Vector2.ONE * REVIEW_ZOOMS[index]
	reference_actor.scale = actor.scale
	_place_actor()
	_refresh_review_frame()

func _set_reference_visible(value: bool) -> void:
	reference_check.set_pressed_no_signal(value)
	reference_actor.visible = value
	reference_caption.visible = value
	reference_actor.scale = actor.scale
	_refresh_review_frame()
	_place_actor()

func _refresh_review_frame() -> void:
	if actor == null or reference_actor == null or frame_label == null:
		return
	var sprite := actor.animated_sprite
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(sprite.animation):
		return
	var count := sprite.sprite_frames.get_frame_count(sprite.animation)
	var fallback := action_picker.selected == 2 and not String(sprite.animation).begins_with("attack_")
	frame_label.text = "Frame %d / %d%s" % [sprite.frame + 1, count, " (fallback)" if fallback else ""]
	review_caption.text = "%s · %s · %d/%d · %d×" % [actor.skin_id.capitalize(), sprite.animation, sprite.frame + 1, count, int(actor.scale.x)]
	var reference := reference_actor.animated_sprite
	var reference_clip:=sprite.animation
	if reference.sprite_frames!=null and not reference.sprite_frames.has_animation(reference_clip):
		reference_clip=CharacterSpriteLibrary.animation_name("idle",String(sprite.animation).get_slice("_",1))
	if reference.sprite_frames != null and reference.sprite_frames.has_animation(reference_clip):
		reference.animation = reference_clip
		reference.set_frame_and_progress(mini(sprite.frame,reference.sprite_frames.get_frame_count(reference_clip)-1), sprite.frame_progress)
		reference.pause()
		reference.position = sprite.position
		reference.modulate = sprite.modulate

func _export_review_frame() -> void:
	var folder := "user://equipment-review"
	DirAccess.make_dir_recursive_absolute(folder)
	var filename := "%s-%s-%02d-%d.png" % [actor.skin_id, actor.animated_sprite.animation, actor.animated_sprite.frame, Time.get_ticks_msec()]
	var result := await capture_review_frame(folder.path_join(filename))
	inspection_status.text = "Saved PNG + pose: " + ProjectSettings.globalize_path(folder.path_join(filename)) if result == OK else "PNG export failed: " + error_string(result)
	inspection_status.tooltip_text = inspection_status.text

## Freeze first, then export the actual on-screen pixels and matching pose data.
func capture_review_frame(destination: String) -> Error:
	_set_review_paused(true)
	await get_tree().process_frame
	# A minimized review window has no normal frame_post_draw signal.
	# Draw the actual SubViewport explicitly so batch evidence cannot stall.
	RenderingServer.force_draw(false)
	var screenshot := review_viewport.get_texture().get_image()
	var result := screenshot.save_png(destination)
	if result != OK:
		return result
	var record := FileAccess.open(destination.get_basename() + ".json", FileAccess.WRITE)
	if record == null:
		return FileAccess.get_open_error()
	var sprite := actor.animated_sprite
	var pose := {
		"skin": actor.skin_id,
		"animation": String(sprite.animation),
		"requested_action": action_picker.get_item_text(action_picker.selected),
		"frame": sprite.frame,
		"frame_count": sprite.sprite_frames.get_frame_count(sprite.animation),
		"zoom": actor.scale.x,
		"original_body_reference": reference_actor.visible,
		"equipment": review_equipment,
		"canvas_size": [screenshot.get_width(), screenshot.get_height()],
		"equipped_anchor": [actor.position.x, actor.position.y],
		"reference_anchor": [reference_actor.position.x, reference_actor.position.y],
		"artwork_approval": "pending"
	}
	record.store_string(JSON.stringify(pose, "  "))
	record.close()
	return OK

func _update_coverage() -> void:
	if coverage_label == null or actor == null:
		return
	var skin: Dictionary = CharacterSpriteLibrary.get_skin(actor.skin_id)
	var role: String = ["idle", "walk", "attack"][action_picker.selected]
	var clips: Dictionary = skin.get("animations", {})
	var clip: Dictionary = clips.get(role, {})
	var directions: Dictionary = clip.get("directions", {})
	var direction: String = DIRECTIONS[direction_picker.selected]
	if role=="attack" and CharacterWeaponMotion.enabled() and not actor.weapon_animation_family().is_empty():
		var family:=actor.weapon_animation_family()
		coverage_label.text="Attack / %s: 8 shared %s poses, authored on Bronze and reused across tiers." % [direction,family.replace("-"," ")]
		return
	var frames: Array = directions.get(direction, [])
	if frames.is_empty():
		var feedback := " Attack uses a brief movement cue." if role == "attack" else ""
		coverage_label.text = "%s / %s: matching static pose. No authored animation was supplied for this action and direction.%s\nAll eight facing poses are available." % [role.capitalize(), direction, feedback]
	else:
		coverage_label.text = "%s / %s: %d authored frames at %s fps.\nAll eight facing poses are available. Missing action directions use their matching static pose." % [role.capitalize(), direction, frames.size(), str(clip.get("fps", 10))]
