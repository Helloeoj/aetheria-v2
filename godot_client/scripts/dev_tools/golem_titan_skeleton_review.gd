extends "res://scripts/dev_tools/golem_titan_animation_review.gd"
## Actual live Skeleton2D rendering, not playback of the native baked images.
## Same actual content/floor/player/camera contract as the animation reviewer.
## Run with -- --social-no-auto --asset-dir=ABS_CANDIDATE --output=ABS_OUTSIDE_REPO --clip=idle

const RIG_SCRIPT := "res://scripts/dev_tools/golem_titan_skeleton_rig.gd"
const RIG_TEXTURE := "res://Assets/Characters/GolemTitanBoundCandidate/south.png"
const SAMPLE_COUNT := 48
const CYCLE_SECONDS := 2.4

var skeletal_actor: Node2D
var rig_structure: Dictionary = {}

func _capture_clip(clip: String, definition: Dictionary) -> void:
	if clip != "idle":
		await super._capture_clip(clip, definition)
		return
	var rig_script: Script = load(RIG_SCRIPT)
	skeletal_actor = rig_script.new()
	skeletal_actor.position = -FOOT_ANCHOR
	titan.add_child(skeletal_actor)
	skeletal_actor.set_process(false)
	visual.hide()
	# Timing metadata remains compatible with the base reviewer. This hidden
	# SpriteFrames resource is never the rendered actor; the live skeleton is.
	var frames := SpriteFrames.new()
	frames.add_animation(clip)
	frames.set_animation_speed(clip, 1.0)
	var source := ProjectSettings.globalize_path(RIG_TEXTURE)
	var texture := ImageTexture.create_from_image(Image.load_from_file(source))
	for index in SAMPLE_COUNT:
		frames.add_frame(clip, texture, CYCLE_SECONDS / float(SAMPLE_COUNT))
		source_index_order.append(index)
	visual.sprite_frames = frames
	visual.play(clip)
	visual.pause()
	for index in SAMPLE_COUNT:
		visual.frame = index
		skeletal_actor.call("sample_at_seconds", CYCLE_SECONDS * float(index) / float(SAMPLE_COUNT))
		for zoom: float in [1.0, 4.0]:
			await _capture(clip, index, zoom, source, "artwork")
		if index == 0 or index == SAMPLE_COUNT / 2:
			await _capture(clip, index, 0.68, source, "artwork")
		if index == SAMPLE_COUNT / 2:
			rig_structure = skeletal_actor.call("get_rig_report")
	for index in [0, 12, 24, 36]:
		visual.frame = index
		skeletal_actor.call("sample_at_seconds", CYCLE_SECONDS * float(index) / float(SAMPLE_COUNT))
		skeletal_actor.call("set_debug_skeleton", true)
		await _capture(clip, index, 4.0, source, "actual-bone-overlay")
	skeletal_actor.call("set_debug_skeleton", false)
	skeletal_actor.call("sample_at_seconds", 0.0)
	visual.frame = 0
	var guide := ContactGuide.new()
	guide.position = titan_position
	guide.z_index = 1000
	viewport.add_child(guide)
	await _capture(clip, 0, 4.0, source, "guide-only-not-contact-proof")
	guide.queue_free()
	skeletal_actor.queue_free()
	await process_frame
	skeletal_actor = null
	visual.show()

func _capture(clip: String, index: int, zoom: float, source: String, kind: String) -> void:
	var prior_count := captures.size()
	await super._capture(clip, index, zoom, source, kind)
	if skeletal_actor != null and index >= 0 and captures.size() > prior_count:
		captures[-1]["rendered_actor"] = "live Skeleton2D + weighted Polygon2D"
		captures[-1]["pose_seconds"] = CYCLE_SECONDS * float(index) / float(SAMPLE_COUNT)
		var bone_poses: Array[Dictionary] = []
		for bone: Bone2D in skeletal_actor.find_children("*", "Bone2D", true, false):
			bone_poses.append({"name": String(bone.name), "position": [bone.position.x, bone.position.y], "rotation": bone.rotation})
		captures[-1]["bone_poses"] = bone_poses

func _review_metadata() -> Dictionary:
	return {"live_skeleton": {"script": RIG_SCRIPT, "script_sha256": FileAccess.get_sha256(RIG_SCRIPT), "texture": RIG_TEXTURE, "texture_sha256": FileAccess.get_sha256(RIG_TEXTURE), "structure_at_peak": rig_structure, "cycle_seconds": CYCLE_SECONDS, "frame_count": SAMPLE_COUNT, "baked_frame_playback": false, "artwork_approval": "pending"}}
