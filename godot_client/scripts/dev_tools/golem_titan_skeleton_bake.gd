extends SceneTree
## Bake the real weighted skeleton, without changing production scenes/catalogs.
## Godot --path godot_client --script res://scripts/dev_tools/golem_titan_skeleton_bake.gd -- --social-no-auto --output=ABS_OUTSIDE_REPOSITORY

const RIG_SCRIPT := "res://scripts/dev_tools/golem_titan_skeleton_rig.gd"
const SOURCE := "res://Assets/Characters/GolemTitanBoundCandidate/south.png"
const SAMPLE_COUNT := 48
const CYCLE_SECONDS := 2.4
const FIXED_RECTS := [Rect2i(80, 153, 96, 89), Rect2i(60, 217, 56, 26), Rect2i(143, 217, 56, 26), Rect2i(25, 217, 33, 26), Rect2i(203, 217, 32, 26)]

var output_dir := ""
var failures: Array[String] = []
var poses: Array[Dictionary] = []
var viewport: SubViewport
var rig: Node2D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_dir = argument.trim_prefix("--output=").simplify_path()
	var repository := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/").get_base_dir().to_lower()
	var normalized := output_dir.replace("\\", "/").to_lower()
	if not output_dir.is_absolute_path() or normalized == repository or normalized.begins_with(repository + "/"):
		printerr("[Titan skeleton bake] Evidence output must be absolute and outside the repository.")
		quit(1)
		return
	if DisplayServer.get_name() == "headless":
		printerr("[Titan skeleton bake] Actual GPU frames require graphical Godot.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output_dir.path_join("native"))
	DirAccess.make_dir_recursive_absolute(output_dir.path_join("skeleton-proof"))
	root.position = Vector2i(-10000, -10000)
	root.size = Vector2i(320, 240)
	viewport = SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	var script: Script = load(RIG_SCRIPT)
	if script == null:
		printerr("[Titan skeleton bake] Missing rig script.")
		quit(1)
		return
	rig = script.new()
	viewport.add_child(rig)
	rig.set_process(false)
	rig.call("set_debug_skeleton", false)
	await process_frame
	await process_frame
	var original := Image.load_from_file(SOURCE)
	original.convert(Image.FORMAT_RGBA8)
	var neutral: Image
	for index in SAMPLE_COUNT + 1:
		var seconds := CYCLE_SECONDS * float(index) / float(SAMPLE_COUNT)
		rig.call("sample_at_seconds", seconds)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		if index == 0:
			neutral = image.duplicate()
			if image.get_data() != original.get_data():
				failures.append("Neutral GPU pixels differ from the original source.")
		if index == SAMPLE_COUNT and image.get_data() != neutral.get_data():
			failures.append("Full-cycle endpoint differs from the native neutral render.")
		for rectangle: Rect2i in FIXED_RECTS:
			if image.get_region(rectangle).get_data() != neutral.get_region(rectangle).get_data():
				failures.append("Protected lower-body pixels changed at sample %d in %s." % [index, rectangle])
		var path := output_dir.path_join("native").path_join("%02d.png" % index) if index < SAMPLE_COUNT else output_dir.path_join("cycle-endpoint.png")
		if image.save_png(path) != OK:
			failures.append("Failed to save native sample: " + path)
		poses.append({"sample": index, "seconds": seconds, "path": path, "sha256": FileAccess.get_sha256(path), "bones": _bone_poses()})
	for index in [0, 12, 24, 36]:
		viewport.size = Vector2i(1024, 1024)
		rig.scale = Vector2(4, 4)
		rig.call("sample_at_seconds", CYCLE_SECONDS * float(index) / float(SAMPLE_COUNT))
		rig.call("set_debug_skeleton", true)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var proof_path := output_dir.path_join("skeleton-proof").path_join("bones-4x-frame-%02d.png" % index)
		if viewport.get_texture().get_image().save_png(proof_path) != OK:
			failures.append("Failed to save actual skeleton proof.")
	var report := {"rig_script": RIG_SCRIPT, "rig_script_sha256": FileAccess.get_sha256(RIG_SCRIPT), "source": SOURCE, "source_sha256": FileAccess.get_sha256(SOURCE), "native_canvas": [256, 256], "foot_anchor": [128, 240], "world_pixels_per_source_pixel": 1, "cycle_seconds": CYCLE_SECONDS, "frame_count": SAMPLE_COUNT, "durations_ms": 50, "poses": poses, "bone_count": rig.find_children("*", "Bone2D", true, false).size(), "failures": failures, "source_artwork_approval": "pending", "runtime_installation": "not_performed"}
	if rig.has_method("get_rig_report"):
		report["rig_structure"] = rig.call("get_rig_report")
	var file := FileAccess.open(output_dir.path_join("skeleton-bake-report.json"), FileAccess.WRITE)
	if file == null:
		failures.append("Cannot save skeleton bake report.")
	else:
		file.store_string(JSON.stringify(report, "  ") + "\n")
		file.close()
	print("[Titan skeleton bake] %d native samples plus exact-cycle endpoint; %d bones; %d failures." % [SAMPLE_COUNT, report.bone_count, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _bone_poses() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for bone: Bone2D in rig.find_children("*", "Bone2D", true, false):
		result.append({"name": String(bone.name), "path": String(rig.get_path_to(bone)), "parent": String(bone.get_parent().name), "position": [bone.position.x, bone.position.y], "global_position": [bone.global_position.x, bone.global_position.y], "rotation": bone.rotation, "rest": var_to_str(bone.rest)})
	return result
