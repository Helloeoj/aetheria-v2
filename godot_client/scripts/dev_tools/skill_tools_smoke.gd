extends Node
## Verifies discoverable skill controls and real editing after fishing UI handoffs.
## Optional rendered captures: -- --capture=<absolute directory>
var checks := 0
var failures: Array[String] = []
var capture_dir := ""
var root: Window
var game: Node
var skills: SkillDebugPanel
var fishing: FishingPanel


func _ready() -> void:
	root = get_tree().root
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_dir = argument.trim_prefix("--capture=")
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		printerr("[Skill tools FAIL] Test timed out")
		get_tree().quit(1))
	_run.call_deferred()


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("[Skill tools FAIL] ", description)


func frames(count: int = 3) -> void:
	for _frame in range(count):
		await get_tree().process_frame


func key_event(code: Key, pressed: bool, character: int = 0) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.unicode = character
	event.pressed = pressed
	Input.parse_input_event(event)


func key(code: Key) -> void:
	key_event(code, true)
	await frames()
	key_event(code, false)
	await frames()


func click(control: Control) -> void:
	var point := control.get_global_transform_with_canvas() * (control.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	await frames()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		root.push_input(event)
		await frames(6 if pressed else 3)


func capture(file_name: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await frames()
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	check(image != null and image.save_png(capture_dir.path_join(file_name)) == OK, "Rendered UI capture saves: " + file_name)


func edit_level(skill: String, value: int) -> void:
	var editor: SpinBox = skills.skill_editors[skill]
	skills.skill_scroll.ensure_control_visible(editor)
	await frames()
	var line := editor.get_line_edit()
	await click(line)
	if not line.has_focus():
		printerr("[Skill tools context] Editor ", skill, " line ", line.get_global_rect(), " scroll ", skills.skill_scroll.get_global_rect(), " offset ", skills.skill_scroll.scroll_vertical, " focus ", root.gui_get_focus_owner())
	check(line.has_focus(), skill + " editor accepts pointer focus")
	line.select_all()
	var text := str(value)
	for index in range(text.length()):
		key_event(KEY_NONE, true, text.unicode_at(index))
		await frames(1)
		key_event(KEY_NONE, false, text.unicode_at(index))
		await frames(1)
	await key(KEY_ENTER)
	check(game.player.get_skill_level(skill) == value, skill + " level changes through typed SpinBox input")
	check(game.player.get_skill_experience(skill) == SkillProgression.experience_for_level(value), skill + " edit updates matching XP")
	check(is_equal_approx(editor.value, float(value)), skill + " editor keeps its submitted value")
	var actor: CombatActor = game.combat.actors[game.player.entity_id]
	var stats: Dictionary = game.player.get_combat_stats()
	check(actor.max_hp == game.player.get_max_hp() and actor.hp == game.player.current_hp, skill + " edit synchronizes actor health")
	check(actor.magic_level == game.player.get_magic_level() and actor.defence_level == int(stats.defence_level), skill + " edit synchronizes actor skill stats")
	check(is_equal_approx(actor.melee_attack_roll, float(stats.melee_attack_roll)) and actor.max_damage == int(stats.max_damage), skill + " edit synchronizes actor attack stats")


func exercise_skill_overflow() -> void:
	# Increasing row height exercises arbitrary registry growth without mutating
	# the shared game catalog. All registered editors remain the real controls.
	root.gui_release_focus()
	var had_scrollbar := skills.skill_scroll.get_v_scroll_bar().visible
	var row_sizes: Dictionary = {}
	for row: Control in skills.skill_rows.get_children():
		row_sizes[row] = row.custom_minimum_size
		row.custom_minimum_size.y = 110.0
	await frames(8)
	check(skills.skill_scroll.get_v_scroll_bar().visible, "Growing skill rows produce a vertical scrollbar")
	var panel_bottom := skills.get_global_transform_with_canvas() * (skills.size - Vector2.ONE)
	check(root.get_visible_rect().has_point(panel_bottom), "Growing skill rows keep the panel frame inside the viewport")
	var status_bottom := skills.status_label.get_global_transform_with_canvas() * (skills.status_label.size - Vector2.ONE)
	check(root.get_visible_rect().has_point(status_bottom), "Skill edit status remains visible outside the scrolling rows")
	skills.skill_scroll.scroll_vertical = 0
	await frames()
	var point := skills.skill_scroll.get_global_transform_with_canvas() * (skills.skill_scroll.size * Vector2(0.1, 0.5))
	for _step in range(20):
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_WHEEL_DOWN
		event.pressed = true
		root.push_input(event)
		await frames(1)
		event = event.duplicate()
		event.pressed = false
		root.push_input(event)
		await frames(1)
	check(skills.skill_scroll.scroll_vertical > 0, "Mouse wheel scrolls the growing skill list")
	var last_skill: String = SkillProgression.SKILL_IDS.back()
	await edit_level(last_skill, 42)
	check(skills.is_editing(), "Last registered skill stays editable after scrolling")
	await capture("skill-tools-scroll-overflow.png")
	for row: Control in row_sizes:
		row.custom_minimum_size = row_sizes[row]
	root.gui_release_focus()
	skills.skill_scroll.scroll_vertical = 0
	await frames(8)
	check(skills.skill_scroll.get_v_scroll_bar().visible == had_scrollbar, "Restoring normal row sizes restores the original scrolling layout")
	await click(skills.find_child("CloseSkillTools", true, false))
	check(not skills.visible, "The fixed close button remains reachable after scrolling")
	await key(KEY_K)
	# Restore focus so the following input-suppression checks exercise editing.
	await click((skills.skill_editors[last_skill] as SpinBox).get_line_edit())


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene := (load("res://scenes/EastOutskirtsLayered.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await frames(8)
	await get_tree().physics_frame
	game = scene.get_node("Combat")
	skills = game.skill_debug_panel
	fishing = game.fishing_panel
	check(game.SKILL_TEST_KEY == KEY_K, "Skills use the ordinary K shortcut")
	check(game.skill_test_button.is_visible_in_tree() and game.skill_test_button.text.ends_with("[K]"), "Top bar advertises a visible Test skills [K] button")
	check(not skills.visible, "Practice tools start closed")
	await click(game.skill_test_button)
	check(skills.visible, "Top-bar button opens skills after a real click")
	var panel_bottom := skills.get_global_transform_with_canvas() * (skills.size - Vector2.ONE)
	check(root.get_visible_rect().has_point(panel_bottom), "All skill tools and their bottom frame fit within the viewport")
	check(skills.get_node_or_null("CloseSkillTools") != null or skills.find_child("CloseSkillTools", true, false) != null, "Practice tools expose an explicit close button")
	check(skills.skill_editors.size() == SkillProgression.SKILL_IDS.size(), "Every skill remains manually editable")
	for skill: String in SkillProgression.SKILL_IDS:
		check(skills.skill_editors.has(skill), "Registry skill has an editor: " + skill)
		var editor: SpinBox = skills.skill_editors[skill]
		skills.skill_scroll.ensure_control_visible(editor)
		await frames()
		var bottom := skills.skill_scroll.get_global_transform_with_canvas().affine_inverse() * (editor.get_global_transform_with_canvas() * (editor.size - Vector2.ONE))
		check(Rect2(Vector2.ZERO, skills.skill_scroll.size).has_point(bottom), "Registry skill row can be shown fully: " + skill)
	var value := 12
	for skill: String in SkillProgression.SKILL_IDS:
		await edit_level(skill, value)
		value = 12 + (value - 9) % 60
	check(skills.combat_label.text.contains(str(game.player.get_combat_level())), "Practice combat label reflects edited levels")
	check(game.skill_training_session.get_elapsed_seconds() == 0.0, "Practice edits reset the earned-XP rate session")
	await exercise_skill_overflow()

	# Character shortcuts must not consume numeric input or trigger combat/movement.
	var point_before: Vector2 = game.player.get_position()
	var selected_before: String = game.player.selected_spell_id
	var target_before: String = game.player.current_target
	await key(KEY_D)
	await key(KEY_W)
	await key(KEY_T)
	await key(KEY_Q)
	await key(KEY_E)
	await key(KEY_SPACE)
	check(game.player.get_position().is_equal_approx(point_before), "Movement keys do not move the character while editing")
	check(game.movement_controller.get_move_vector().is_zero_approx(), "Editing never leaves movement keys held")
	check(game.player.current_target == target_before and not game.auto_chase_target, "Combat target/chase shortcuts stay inactive while editing")
	check(game.player.selected_spell_id == selected_before and not game.spell_cast_requested and not game.combat.active_spell_casts.has(game.player.entity_id), "Spell shortcuts stay inactive while editing")
	await key(KEY_K)
	check(not skills.visible, "K closes skills while a numeric editor has focus")
	check(root.gui_get_focus_owner() == null, "Closing skills releases editor focus")
	await key(KEY_K)
	check(skills.visible, "K reopens skills")
	await click(skills.find_child("CloseSkillTools", true, false))
	check(not skills.visible, "Close button closes skills through pointer input")

	# Both handoff directions preserve the same character and refresh fishing range.
	await key(KEY_K)
	await edit_level("fishing", 1)
	await key(KEY_P)
	check(fishing.visible and not skills.visible and fishing.session.state == FishingSession.State.READY, "P opens fishing and hides focused skill tools")
	check(is_equal_approx(fishing.session.effective_max_cast_distance(), 15.0), "Fishing starts at the edited level-1 Beginner range")
	await key(KEY_K)
	check(skills.visible and not fishing.visible and fishing.session.state == FishingSession.State.CLOSED, "K leaves READY fishing and opens skill tools")
	await edit_level("fishing", 10)
	await capture("skill-tools-fishing-10.png")
	await key(KEY_P)
	check(fishing.visible and is_equal_approx(fishing.session.effective_max_cast_distance(), 60.0), "Reopened fishing uses the edited level-10 Beginner range")
	await capture("fishing-skills-entry.png")
	await key(KEY_SPACE)
	check(fishing.session.state == FishingSession.State.POWER, "Live Space input starts fishing power")
	await key(KEY_K)
	check(skills.visible and not fishing.visible and fishing.session.state == FishingSession.State.CLOSED, "K leaves an active power meter and opens skill tools")
	await edit_level("fishing", 5)
	await key(KEY_P)
	check(fishing.visible and is_equal_approx(fishing.session.effective_max_cast_distance(), 35.0), "Fishing sees skill edits after cancelling a power meter")
	await click(fishing.get_node("EditFishingSkills"))
	check(skills.visible and not fishing.visible, "Fishing's Skills [K] button opens the editable skill tools")
	await edit_level("fishing", 7)
	await key(KEY_P)
	check(fishing.visible and is_equal_approx(fishing.session.effective_max_cast_distance(), 45.0), "Fishing sees edits after its Skills button handoff")
	await click(fishing.rod_picker)
	check(fishing.rod_picker.get_popup().visible, "Fishing rod dropdown opens before handoff")
	# Top-bar/keyboard handoff must clean up native dropdowns as well as the panel.
	game.toggle_skill_debug_panel()
	await frames()
	check(skills.visible and not fishing.visible, "Skill handoff works with an open fishing popup")
	check(not fishing.rod_picker.get_popup().visible and not fishing.bait_picker.get_popup().visible, "Closing fishing for skills also hides native dropdown windows")
	await click(skills.find_child("CloseSkillTools", true, false))
	await key(KEY_P)
	await key(KEY_ESCAPE)
	check(not skills.visible and not fishing.visible, "Fishing still closes normally after repeated skill handoffs")
	check(game.is_physics_processing() and fishing.is_processing() and skills.is_processing(), "All runtime callbacks stay active throughout editing")
	print("[Skill tools] %d checks, %d failures" % [checks, failures.size()])
	scene.free()
	get_tree().quit(0 if failures.is_empty() else 1)
