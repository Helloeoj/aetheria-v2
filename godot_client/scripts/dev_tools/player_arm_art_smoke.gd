extends SceneTree
## Native source-mask conservation checks, independent of the live arm renderer.
var checks := 0
var failures: Array[String] = []
var destination := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--arm-output="):
			destination = argument.trim_prefix("--arm-output=")
	if not destination.is_empty():
		DirAccess.make_dir_recursive_absolute(destination)
	if not FileAccess.file_exists("res://scripts/player_arm_art.gd"):
		_check(false, "native arm-art helper exists")
		_finish()
		return
	var helper: Script = load("res://scripts/player_arm_art.gd")
	var armor_rig: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/bronze_armor_arm_rig.json"))
	FittedEquipmentLibrary.initialize()
	for direction: String in ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"]:
		var context := {"direction": direction, "action": "idle", "frame": 0, "padding": Vector2.ZERO}
		var pose := FittedEquipmentLibrary.frame(context)
		context.pose = {"right_hand": pose.joints.hand_right, "left_hand": pose.joints.hand_left}
		context.source_pose = context.pose
		var head := FittedEquipmentLibrary.head_texture(pose).get_image()
		for armored: bool in [false, true]:
			var source := FittedEquipmentLibrary.texture(pose.original).get_image().duplicate() as Image
			context.body_pose = {}
			var hand_masks := {}
			var hidden: Array = []
			if armored:
				context.body_pose = FittedEquipmentLibrary.replacement_pose("bronze-platebody", context)
				# Use the same complete canonical idle chest source as the live
				# articulated renderer, never the old approximate hand patches.
				var armor_texture := load(String(armor_rig.directions[direction].source)) as Texture2D
				source = armor_texture.get_image().duplicate() as Image
				var full_actor := load(String(armor_rig.directions[direction].source_actor)) as Texture2D
				var full_image := full_actor.get_image()
				for side: String in ["left", "right"]:
					var wrist := FittedEquipmentLibrary.point(armor_rig.directions[direction].joints["hand_" + side])
					var original_palm: Dictionary = helper.call("_hand_pixels", full_image, wrist)
					hand_masks[side] = original_palm
					for pixel: Vector2i in original_palm:
						if source.get_pixelv(pixel).a == 0.0:
							source.set_pixelv(pixel, full_image.get_pixelv(pixel))
				hidden = armor_rig.directions[direction].get("hidden", [])
			var joints := FittedEquipmentLibrary.source_joints(context)
			if armored:
				joints = armor_rig.directions[direction].joints.duplicate(true)
			var before := source.get_data()
			var split: Dictionary = helper.call("split", source, joints, armored, null if armored else head, hand_masks, hidden)
			var label := ("bronze" if armored else "bare") + "-" + direction
			_check(before == source.get_data(), label + " input untouched")
			if armored:
				_check(_component_count(split.torso) == 1, label + " fixed torso has no detached old arm contours")
			var masks: Array[Image] = [split.torso, split.lower]
			for side: String in ["left", "right"]:
				var arm: Dictionary = split.arms[side]
				for part: String in ["upper", "forearm", "hand"]:
					var image: Image = arm[part]
					masks.append(image)
					_check(image.get_size() == Vector2i(80, 80) and image.get_used_rect().has_area(), label + "/" + side + "/" + part + " usable native mask")
					if armored and part == "hand":
						_check(_pixel_count(image) >= 20, label + "/" + side + " retains full restored palm")
					if not destination.is_empty():
						image.save_png(destination.path_join(label + "-" + side + "-" + part + ".png"))
			var missing := 0
			var changed := 0
			var neck: Vector2 = FittedEquipmentLibrary.point(joints.neck)
			for y in range(80):
				for x in range(80):
					var color := source.get_pixel(x, y)
					var covered := false
					for image: Image in masks:
						var copied := image.get_pixel(x, y)
						if copied.a > 0.0:
							covered = true
							if copied != color:
								changed += 1
					# Borrowed visible parts use donor source coordinates; the
					# untouched local partition is retained only for this oracle.
					for side: String in ["left", "right"]:
						for part: String in ["upper", "forearm", "hand"]:
							if split.raw_arms[side][part].get_pixel(x, y).a > 0.0:
								covered = true
					var removed_head := not armored and y < neck.y and head.get_pixel(x, y).a > 0.0
					if color.a > 0.0 and not removed_head and not covered:
						missing += 1
			_check(missing == 0, label + " preserves all non-head source alpha (missing " + str(missing) + ")")
			_check(changed == 0, label + " copies exact source RGBA (changed " + str(changed) + ")")
			if not destination.is_empty():
				source.save_png(destination.path_join(label + "-source.png"))
				split.torso.save_png(destination.path_join(label + "-torso.png"))
				split.lower.save_png(destination.path_join(label + "-lower.png"))
	# A hidden far upper arm can borrow a coherent donor, but its old hand
	# must not become a stationary ghost on the body or lower layer.
	var fixture := Image.create(80, 80, false, Image.FORMAT_RGBA8)
	for y in range(39, 54):
		for x in range(29, 32):
			fixture.set_pixel(x, y, Color("5c5145"))
	for y in range(53, 57):
		for x in range(28, 33):
			fixture.set_pixel(x, y, Color("dca482"))
	fixture.set_pixel(50, 55, Color("dca482"))
	var fixture_joints := {
		"chest": [40, 43], "pelvis": [40, 52], "neck": [40, 37],
		"shoulder_left": [30, 39], "elbow_left": [30, 46], "hand_left": [30, 55],
		"shoulder_right": [50, 39], "elbow_right": [50, 46], "hand_right": [50, 55]
	}
	var borrowed: Dictionary = helper.call("split", fixture, fixture_joints, false)
	_check(bool(borrowed.arms.right.borrowed), "hidden far arm borrows usable donor")
	_check(borrowed.arms.right.shoulder == Vector2(30, 39) and borrowed.arms.right.elbow == Vector2(30, 46) and borrowed.arms.right.wrist == Vector2(30, 55), "borrowed arm retains all donor rest pivots")
	_check(borrowed.torso.get_pixel(50, 55).a == 0.0 and borrowed.lower.get_pixel(50, 55).a == 0.0, "old far hand is absent from visible body")
	_check(borrowed.raw_arms.right.hand.get_pixel(50, 55).a > 0.0, "old far hand remains in diagnostic partition only")
	# Muted flesh shadows belong to the palm; nearby bronze beyond the
	# measured hand radius belongs to the forearm, even with flesh-like hue.
	var hand_fixture := Image.create(80, 80, false, Image.FORMAT_RGBA8)
	hand_fixture.set_pixel(40, 40, Color("d29d7f"))
	hand_fixture.set_pixel(41, 40, Color("694330"))
	hand_fixture.set_pixel(42, 40, Color("060101"))
	hand_fixture.set_pixel(40, 36, Color("b3866e"))
	var measured: Dictionary = helper.call("_hand_pixels", hand_fixture, Vector2(40, 40))
	_check(measured.has(Vector2i(41, 40)), "palm includes connected shadow flesh")
	_check(measured.has(Vector2i(42, 40)), "palm includes one-pixel source ink")
	_check(not measured.has(Vector2i(40, 36)), "palm excludes distant bronze vambrace")
	# Side-view source arm seams overlap the breastplate's central contour.
	# Source pixels can overlap at the joint, but must not hollow the torso.
	var body_fixture := Image.create(80, 80, false, Image.FORMAT_RGBA8)
	for y in range(39, 54):
		for x in range(35, 47):
			body_fixture.set_pixel(x, y, Color("a76742"))
	var body_joints := {
		"chest": [42, 46], "pelvis": [42, 54], "neck": [46, 38],
		"shoulder_left": [38, 40], "elbow_left": [38, 45], "hand_left": [40, 55],
		"shoulder_right": [44, 40], "elbow_right": [44, 47], "hand_right": [45, 55]
	}
	var body_parts: Dictionary = helper.call("split", body_fixture, body_joints, true)
	_check(body_parts.torso.get_pixel(39, 46).a > 0.0, "side-view breastplate retains native core")
	_check(body_parts.arms.left.upper.get_pixel(38, 40).a > 0.0, "upper contour reaches native shoulder hinge")
	_check_tier_preservation()
	# A detached old hand must leave, while each independently connected
	# original foot and its leg remain. The helper must not alter its input.
	var lower_fixture := Image.create(80, 80, false, Image.FORMAT_RGBA8)
	for y in range(51, 65):
		for x in range(29, 33):
			lower_fixture.set_pixel(x, y, Color("5c5145"))
		for x in range(47, 51):
			lower_fixture.set_pixel(x, y, Color("81725f"))
	for y in range(53, 56):
		for x in range(20, 23):
			lower_fixture.set_pixel(x, y, Color("dca482"))
	var lower_before := lower_fixture.get_data()
	var cleaned: Image = helper.call("lower_body", lower_fixture, {"foot_left": [49, 63], "foot_right": [31, 63]})
	_check(lower_fixture.get_data() == lower_before, "lower-body cleanup preserves input")
	_check(cleaned.get_pixel(21, 54).a == 0.0, "lower-body cleanup removes detached old hand")
	_check(cleaned.get_pixel(31, 63) == lower_fixture.get_pixel(31, 63), "lower-body cleanup retains original right foot")
	_check(cleaned.get_pixel(49, 63) == lower_fixture.get_pixel(49, 63), "lower-body cleanup retains original left foot")
	_check(_pixel_count(cleaned) == 112 and _component_count(cleaned) == 2, "lower-body cleanup retains both complete native legs only")
	_finish()


func _check_tier_preservation() -> void:
	var body_script: Script = load("res://scripts/player_articulated_body.gd")
	for material: String in ["iron", "steel"]:
		for direction: String in ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"]:
			var context := {"direction": direction, "action": "idle", "frame": 0, "padding": Vector2.ZERO, "chest_item_id": material + "-platebody"}
			var pose := FittedEquipmentLibrary.frame(context)
			context.pose = {"right_hand": pose.joints.hand_right, "left_hand": pose.joints.hand_left}
			context.source_pose = context.pose
			context.body_pose = FittedEquipmentLibrary.replacement_pose(context.chest_item_id, context)
			var path := "replacement-v1/" + material + "/chest/" + direction + "/0.png"
			var chest := FittedEquipmentLibrary.texture(path).get_image()
			var original := chest.duplicate() as Image
			var before := chest.get_data()
			var actor := FittedEquipmentLibrary.texture("replacement-v1/source/" + direction + "/0.png").get_image()
			var actor_before := actor.get_data()
			var parts: Dictionary = body_script.call("source_parts", context)
			var layers: Array[Image] = [parts.torso, parts.lower]
			for side: String in ["left", "right"]:
				for part: String in ["upper", "forearm", "hand"]:
					# The raw partition preserves the actual local contour even
					# when its visible far arm borrows a coherent opposite donor.
					layers.append(parts.raw_arms[side][part])
			var missing := 0
			var changed := 0
			for y in range(80):
				for x in range(80):
					var expected := original.get_pixel(x, y)
					if expected.a == 0.0:
						continue
					var found := false
					for layer: Image in layers:
						var color := layer.get_pixel(x, y)
						if color.a > 0.0:
							found = true
							if color != expected:
								changed += 1
					if not found:
						missing += 1
			var label := material + "/" + direction
			_check(missing == 0, label + " reassembled source retains every existing chest pixel (missing " + str(missing) + ")")
			_check(changed == 0, label + " preserves original opaque tier RGBA (changed " + str(changed) + ")")
			_check(chest.get_data() == before, label + " canonical tier source remains untouched")
			_check(actor.get_data() == actor_before, label + " full actor source remains untouched")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func _pixel_count(image: Image) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0:
				count += 1
	return count


func _component_count(image: Image) -> int:
	var remaining := {}
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0:
				remaining[Vector2i(x, y)] = true
	var count := 0
	while not remaining.is_empty():
		count += 1
		var pending: Array[Vector2i] = [remaining.keys()[0]]
		remaining.erase(pending[0])
		var cursor := 0
		while cursor < pending.size():
			var pixel := pending[cursor]
			cursor += 1
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var neighbor := pixel + Vector2i(dx, dy)
					if remaining.has(neighbor):
						remaining.erase(neighbor)
						pending.append(neighbor)
	return count


func _finish() -> void:
	print(JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "artwork_approval": false}))
	quit(0 if failures.is_empty() else 1)
