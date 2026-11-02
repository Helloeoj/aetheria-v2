extends SceneTree
## Tests the existing F7 widget; optional lossless captures require rendering.
var failures := 0
var preview: Variant

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("[Equipment inspection FAIL] ", message)

func click(control: Control) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = control.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event)
		await process_frame

func _run() -> void:
	root.size = Vector2i(1280,720)
	create_timer(90).timeout.connect(func() -> void: quit(1))
	preview = (load("res://scripts/sprite_preview.gd") as GDScript).new()
	root.add_child(preview)
	await process_frame
	if not preview.has_method("_set_review_paused"):
		check(false, "F7 has no frame inspection controls")
		quit(1)
		return
	preview._select_skin(preview.skin_ids.find("peasant"))
	preview.show_preview()
	check(preview.get_node_or_null("InspectionLayer") != null, "F7 sits above the persistent chat overlay")
	preview.hide_preview()
	if preview.get_node_or_null("InspectionLayer") != null:
		check(not preview.get_node("InspectionLayer").visible, "closing F7 hides its inspection layer")
	preview.show_preview()
	preview.action_picker.select(1)
	preview._change_action(1)
	preview._set_review_paused(true)
	var sprite: AnimatedSprite2D = preview.actor.animated_sprite
	var clip: StringName = sprite.animation
	var count := sprite.sprite_frames.get_frame_count(clip)
	check(count == 8, "peasant walk fixture has eight frames")
	preview._step_review_frame(-1)
	check(sprite.frame == count - 1, "previous wraps to last frame")
	await create_timer(0.4).timeout
	check(sprite.frame == count - 1 and sprite.animation == clip and not sprite.is_playing(), "paused walk remains frozen beyond actor walk hold")
	preview._step_review_frame(1)
	check(sprite.frame == 0, "next wraps to first frame")
	preview._step_review_frame(1)
	preview._armor_preset("Iron")
	check(sprite.frame == 1 and not sprite.is_playing(), "equipment changes preserve frozen frame")
	preview._set_reference_visible(true)
	preview._refresh_review_frame()
	check(preview.reference_actor.visible, "unarmored reference is visible")
	check(preview.reference_actor.animated_sprite.frame == sprite.frame and preview.reference_actor.animated_sprite.animation == sprite.animation, "reference matches equipped pose")
	check(preview.reference_actor.attachment_rig.get_equipped_visual("chest") == null, "reference has no armor")
	preview._change_review_zoom(2)
	check(preview.actor.scale == Vector2(4,4) and preview.reference_actor.scale == Vector2(4,4), "both actors use integer 4x zoom")
	preview._change_review_zoom(0)
	check(preview.actor.scale == Vector2.ONE, "1x zoom is available")
	preview.direction_picker.select(4)
	preview._change_direction(4)
	check(sprite.animation == &"walk_north" and sprite.frame == 0 and not sprite.is_playing(), "direction changes reset pose while staying paused")
	preview.action_picker.select(2)
	preview._change_action(2)
	check(not sprite.is_playing() and preview.frame_label.text.contains("fallback"), "missing peasant attack is labeled as fallback")
	preview.action_picker.select(0)
	preview._change_action(0)
	preview._step_review_frame(-1)
	check(sprite.frame == 0, "single-frame idle wraps safely")
	preview._select_skin(preview.skin_ids.find("goblin_scout"))
	check(preview.reference_actor.skin_id == preview.actor.skin_id, "skin change updates reference")
	preview.action_picker.select(2)
	preview._change_action(2)
	check(not sprite.is_playing(), "authored attack stays paused")
	preview._select_skin(preview.skin_ids.find("peasant"))
	preview.action_picker.select(1)
	preview._change_action(1)
	preview._set_review_paused(false)
	await create_timer(0.35).timeout
	check(sprite.is_playing() and sprite.animation == &"walk_north" and preview.actor.is_processing(), "resume restores original walk playback and actor clock")
	await click(preview.pause_button)
	check(preview.review_paused and not sprite.is_playing(), "real pointer input reaches Pause above chat")
	var frozen_frame := sprite.frame
	for node: Node in preview.find_children("*", "Button", true, false):
		if node.text == "Next frame":
			await click(node)
	check(sprite.frame == posmod(frozen_frame + 1, 8), "real pointer input advances one frame")
	preview._select_skin(preview.skin_ids.find("golem_titan"))
	preview._change_review_zoom(2)
	await process_frame
	await process_frame
	var dimensions := Vector2(sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame).get_size())
	var body_bounds: Rect2 = preview.actor.transform * (sprite.transform * Rect2(sprite.offset - dimensions * 0.5, dimensions))
	check(Rect2(Vector2.ZERO, preview.preview_area.size).encloses(body_bounds), "large skin fits the complete 4x review canvas")
	root.size = Vector2i(960,720)
	await process_frame
	await process_frame
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(preview.pause_button.get_global_rect()), "review controls stay on screen in a narrower window")
	check(preview.review_surface.get_parent().size.y >= 240, "scrollable review remains usable in a narrower window")
	root.size = Vector2i(1280,720)
	preview._select_skin(preview.skin_ids.find("peasant"))
	var destination := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--inspection-output="):
			destination = arg.trim_prefix("--inspection-output=")
	if not destination.is_empty():
		DirAccess.make_dir_recursive_absolute(destination)
		if "--inspection-minimized" in OS.get_cmdline_user_args():
			root.mode = Window.MODE_MINIMIZED
		await _capture_review(destination)
	print("[Equipment inspection] ", failures, " failures")
	preview.free()
	quit(0 if failures == 0 else 1)

func _capture_review(destination: String) -> void:
	preview._set_reference_visible(true)
	preview._set_review_paused(true)
	preview.preview_armor = {"chest":"Iron Platebody", "legs":"Iron Platelegs"}
	preview._change_equipment(0)
	for zoom_index: int in [0, 2]:
		preview._change_review_zoom(zoom_index)
		for direction_index in range(8):
			preview.direction_picker.select(direction_index)
			preview._change_direction(direction_index)
			for frame in range(8):
				var path := destination.path_join("%dx-%s-%02d.png" % [int(preview.actor.scale.x), preview.DIRECTIONS[direction_index], frame])
				check(await preview.capture_review_frame(path) == OK, "lossless frame export")
				if direction_index == 0 and frame == 0:
					root.get_texture().get_image().save_png(destination.path_join("viewer-%dx.png" % int(preview.actor.scale.x)))
				var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path.get_basename() + ".json"))
				if not parsed is Dictionary:
					check(false, "export metadata is immediately readable")
					return
				var record: Dictionary = parsed
				check(int(record.frame) == frame and record.animation == String(preview.actor.animated_sprite.animation), "export metadata matches rendered pose")
				var exported := Image.load_from_file(path)
				check(exported.get_size() == Vector2i(int(record.canvas_size[0]), int(record.canvas_size[1])), "PNG exports the full review canvas")
				preview._step_review_frame(1)
	preview.action_picker.select(0)
	for direction_index in range(8):
		preview.direction_picker.select(direction_index)
		preview._change_direction(direction_index)
		check(await preview.capture_review_frame(destination.path_join("4x-%s-idle.png" % preview.DIRECTIONS[direction_index])) == OK, "idle collar export")
	preview._select_skin(preview.skin_ids.find("golem_titan"))
	preview._change_review_zoom(2)
	check(await preview.capture_review_frame(destination.path_join("titan-4x.png")) == OK, "large skin exports without cropping")
	root.get_texture().get_image().save_png(destination.path_join("viewer-titan-4x.png"))
