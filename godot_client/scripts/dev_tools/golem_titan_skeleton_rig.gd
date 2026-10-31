extends Node2D
## Review-only native 256px skin, never registered in gameplay or a catalog.
## Origin is the PNG's TOP LEFT. Place this node at world_anchor - FOOT_ANCHOR.
## One unchanged texture and one shared-vertex Polygon2D; no image cutouts.
## Bone coordinates and amplitudes are native pixels, before camera zoom.

const SOURCE_TEXTURE := "res://Assets/Characters/GolemTitanBoundCandidate/south.png"
const NATIVE_SIZE := Vector2i(256, 256)
const FOOT_ANCHOR := Vector2(128, 240)
const CYCLE_SECONDS := 2.4
const MESH_STEP := 4
const PINNED_RECTS := [
	Rect2(80, 153, 96, 89),
	Rect2(60, 217, 56, 26),
	Rect2(143, 217, 56, 26),
	Rect2(25, 217, 33, 26),
	Rect2(203, 217, 32, 26),
]

# Character-right is screen-left in the south-facing source.
const JOINTS := [
	["pelvis", "", Vector2(128, 156)],
	["waist", "pelvis", Vector2(128, 148)],
	["spine", "waist", Vector2(128, 134)],
	["chest", "spine", Vector2(128, 121)],
	["neck", "chest", Vector2(128, 99)],
	["head", "neck", Vector2(128, 72)],
	["clavicle_right", "chest", Vector2(106, 107)],
	["shoulder_right", "clavicle_right", Vector2(78, 103)],
	["upper_arm_right", "shoulder_right", Vector2(68, 115)],
	["forearm_right", "upper_arm_right", Vector2(46, 140)],
	["wrist_right", "forearm_right", Vector2(43, 170)],
	["fist_right", "wrist_right", Vector2(43, 187)],
	["clavicle_left", "chest", Vector2(150, 107)],
	["shoulder_left", "clavicle_left", Vector2(178, 104)],
	["upper_arm_left", "shoulder_left", Vector2(189, 117)],
	["forearm_left", "upper_arm_left", Vector2(210, 142)],
	["wrist_left", "forearm_left", Vector2(211, 173)],
	["fist_left", "wrist_left", Vector2(212, 189)],
	["hip_right", "pelvis", Vector2(103, 160)],
	["knee_right", "hip_right", Vector2(95, 183)],
	["ankle_right", "knee_right", Vector2(88, 215)],
	["hip_left", "pelvis", Vector2(153, 160)],
	["knee_left", "hip_left", Vector2(161, 184)],
	["ankle_left", "knee_left", Vector2(169, 215)],
	["bindings", "", Vector2(128, 220)],
]

var skeleton: Skeleton2D
var skin: Polygon2D
var bones: Dictionary = {}
var _joint_positions: Dictionary = {}
var _source_image: Image
var _built := false
var _debug_skeleton := false
var _debug_overlay: BoneOverlay

class BoneOverlay extends Node2D:
	var rig: Node2D
	func _draw() -> void:
		rig._draw_bone_overlay(self)


func _ready() -> void:
	_build()
	sample_at_seconds(0.0)


func _build() -> void:
	if _built:
		return
	_built = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	skeleton = Skeleton2D.new()
	skeleton.name = "TitanSkeleton"
	add_child(skeleton)
	for definition: Array in JOINTS:
		var bone_name: String = definition[0]
		var parent_name: String = definition[1]
		var joint: Vector2 = definition[2]
		var bone := Bone2D.new()
		bone.name = bone_name
		bone.set_autocalculate_length_and_angle(false)
		bone.length = 10.0
		_joint_positions[bone_name] = joint
		if parent_name.is_empty():
			bone.position = joint
			skeleton.add_child(bone)
		else:
			var parent_joint: Vector2 = _joint_positions[parent_name]
			bone.position = joint - parent_joint
			(bones[parent_name] as Bone2D).add_child(bone)
		bone.rest = bone.transform
		bones[bone_name] = bone
	for definition: Array in JOINTS:
		var parent_name: String = definition[1]
		if not parent_name.is_empty():
			var parent_bone: Bone2D = bones[parent_name]
			var direction: Vector2 = definition[2] - _joint_positions[parent_name]
			parent_bone.length = direction.length()
			parent_bone.set_bone_angle(direction.angle())
	_build_skin()
	_debug_overlay = BoneOverlay.new()
	_debug_overlay.name = "BoneProofOverlay"
	_debug_overlay.rig = self
	_debug_overlay.z_index = 1
	_debug_overlay.visible = _debug_skeleton
	add_child(_debug_overlay)


func _build_skin() -> void:
	_source_image = Image.load_from_file(SOURCE_TEXTURE)
	assert(_source_image != null and _source_image.get_size() == NATIVE_SIZE,
		"Titan candidate requires the unchanged native 256x256 source.")
	# ImageTexture keeps native lossless RGBA; this image has no generated mipmaps.
	if _source_image.has_mipmaps():
		_source_image.clear_mipmaps()
	skin = Polygon2D.new()
	skin.name = "ContinuousWeightedSkin"
	skin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	skin.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	skin.antialiased = false
	skin.texture = ImageTexture.create_from_image(_source_image)
	add_child(skin)
	skin.skeleton = skin.get_path_to(skeleton)
	var vertices := PackedVector2Array()
	var triangles: Array[PackedInt32Array] = []
	var columns := NATIVE_SIZE.x / MESH_STEP + 1
	var rows := NATIVE_SIZE.y / MESH_STEP + 1
	for row in rows:
		for column in columns:
			vertices.append(Vector2(column * MESH_STEP, row * MESH_STEP))
	for row in rows - 1:
		for column in columns - 1:
			var a := row * columns + column
			var b := a + 1
			var c := a + columns
			var d := c + 1
			# Alternating diagonals avoid a directional deformation bias.
			if (row + column) % 2 == 0:
				triangles.append(PackedInt32Array([a, b, d]))
				triangles.append(PackedInt32Array([a, d, c]))
			else:
				triangles.append(PackedInt32Array([a, b, c]))
				triangles.append(PackedInt32Array([b, d, c]))
	skin.polygon = vertices
	skin.uv = vertices
	skin.polygons = triangles
	var per_bone: Dictionary = {}
	for bone_name: String in bones:
		var weights := PackedFloat32Array()
		weights.resize(vertices.size())
		per_bone[bone_name] = weights
	for index in vertices.size():
		var local_weights := _weights_at(vertices[index])
		for bone_name: String in local_weights:
			per_bone[bone_name][index] = local_weights[bone_name]
	for bone_name: String in bones:
		# Polygon2D's bone paths are relative to its Skeleton2D, not the skin.
		skin.add_bone(skeleton.get_path_to(bones[bone_name]), per_bone[bone_name])


func _weights_at(point: Vector2) -> Dictionary:
	# Bind the glyphs, blue lower restraints and the floor to a separate fixed bone.
	# This pins vertices only; it never extracts/repaints texture pixels.
	if point.y >= 204.0 or _is_protected(point) or _near_lower_binding(point):
		return {"bindings": 1.0}
	var horizontal := absf(point.x - 128.0)
	var body_edge := 46.0 - clampf((point.y - 110.0) * 0.14, -3.0, 7.0)
	var arm_amount := smoothstep(body_edge - 6.0, body_edge + 10.0, horizontal)
	var lower_amount := smoothstep(154.0, 168.0, point.y)
	var scores: Dictionary = {}
	var body_names: Array[String] = ["pelvis", "waist", "spine", "chest", "neck", "head"]
	for bone_name: String in body_names:
		var joint: Vector2 = _joint_positions[bone_name]
		var along := (point.y - joint.y) / 16.0
		scores[bone_name] = exp(-along * along) * (1.0 - arm_amount) * (1.0 - lower_amount)
	var side := "right" if point.x < 128.0 else "left"
	var arm_names: Array[String] = ["clavicle_", "shoulder_", "upper_arm_", "forearm_", "wrist_", "fist_"]
	for prefix: String in arm_names:
		var bone_name := prefix + side
		var joint: Vector2 = _joint_positions[bone_name]
		var radius := 19.0 if prefix != "clavicle_" else 23.0
		scores[bone_name] = exp(-point.distance_squared_to(joint) / (radius * radius)) * arm_amount
	for prefix: String in ["hip_", "knee_", "ankle_"]:
		var bone_name := prefix + side
		var joint: Vector2 = _joint_positions[bone_name]
		var along := (point.y - joint.y) / 18.0
		scores[bone_name] = exp(-along * along) * lower_amount * (1.0 - arm_amount)
	# Pelvis/legs become wholly fixed below the belt, while the lateral fists
	# retain their own articulated weights. No breathing reaches the knees.
	if point.y >= 168.0 and horizontal <= 64.0:
		for bone_name: String in scores:
			if not bone_name.begins_with("hip_") and not bone_name.begins_with("knee_") and not bone_name.begins_with("ankle_"):
				scores[bone_name] = 0.0
	# Godot 2D skinning accepts the four strongest influences per vertex.
	# Keep and normalize those explicitly, rather than rely on GPU truncation.
	var ranked: Array = scores.keys()
	ranked.sort_custom(func(a: String, b: String) -> bool: return float(scores[a]) > float(scores[b]))
	var total := 0.0
	for index in mini(4, ranked.size()):
		total += float(scores[ranked[index]])
	if total <= 0.000000001:
		return {"bindings": 1.0}
	var result: Dictionary = {}
	for index in mini(4, ranked.size()):
		var bone_name: String = ranked[index]
		var weight: float = scores[bone_name] / total
		if weight > 0.0:
			result[bone_name] = weight
	return result


func _near_lower_binding(point: Vector2) -> bool:
	if point.y < 166.0:
		return false
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var pixel := Vector2i(point) + Vector2i(dx, dy)
			if pixel.x < 0 or pixel.y < 0 or pixel.x >= NATIVE_SIZE.x or pixel.y >= NATIVE_SIZE.y:
				continue
			var color := _source_image.get_pixelv(pixel)
			var binding_zone := (pixel.x >= 50 and pixel.x <= 80) or (pixel.x >= 175 and pixel.x <= 207)
			var cyan := binding_zone and color.r < 0.48 and color.g > 0.48 and color.b > 0.65 and color.b > color.r * 1.45
			var icy_white := binding_zone and color.g > 0.66 and color.b > 0.72 and color.b >= color.r * 0.98
			if color.a > 0.1 and (cyan or icy_white):
				return true
	return false


func _is_protected(point: Vector2) -> bool:
	for rectangle: Rect2 in PINNED_RECTS:
		# Pin the full support of every triangle touching a protected source pixel.
		if rectangle.grow(float(MESH_STEP)).has_point(point):
			return true
	return false


## Deterministic sampling; the review/export harness owns playback and timing.
## All tracks subtract their phase baseline, so 0s and 2.4s share the source pose.
func sample_at_seconds(seconds: float) -> void:
	_build()
	for bone: Bone2D in bones.values():
		bone.apply_rest()
	var fraction := fposmod(seconds, CYCLE_SECONDS) / CYCLE_SECONDS
	if is_zero_approx(fraction) or is_equal_approx(fraction, 1.0):
		_debug_overlay.queue_redraw()
		return
	var phase := TAU * fraction
	var breath := 1.0 - cos(phase)
	(bones.waist as Bone2D).position.y -= 0.10 * breath
	(bones.spine as Bone2D).position.y -= 0.25 * breath
	(bones.chest as Bone2D).position.y -= 0.30 * breath
	(bones.spine as Bone2D).rotation = deg_to_rad(0.08 * sin(phase))
	(bones.chest as Bone2D).rotation = deg_to_rad(-0.08 * sin(phase))
	(bones.neck as Bone2D).rotation = deg_to_rad(0.16 * _wave(phase, -0.22))
	(bones.head as Bone2D).rotation = deg_to_rad(-0.24 * _wave(phase, -0.42))
	(bones.head as Bone2D).position.y -= 0.08 * _wave(phase, -0.32)
	for side: String in ["right", "left"]:
		var sign_value := 1.0 if side == "right" else -1.0
		var delay := 0.0 if side == "right" else -0.12
		(bones["clavicle_" + side] as Bone2D).rotation = deg_to_rad(sign_value * 0.12 * _wave(phase, delay - 0.12))
		(bones["shoulder_" + side] as Bone2D).rotation = deg_to_rad(sign_value * 0.12 * _wave(phase, delay - 0.24))
		(bones["upper_arm_" + side] as Bone2D).rotation = deg_to_rad(sign_value * 1.10 * _wave(phase, delay))
		(bones["forearm_" + side] as Bone2D).rotation = deg_to_rad(-sign_value * 0.58 * _wave(phase, delay - 0.65))
		(bones["wrist_" + side] as Bone2D).rotation = deg_to_rad(sign_value * 0.42 * _wave(phase, delay - 1.30))
		(bones["fist_" + side] as Bone2D).rotation = deg_to_rad(-sign_value * 0.14 * _wave(phase, delay - 1.45))
	_debug_overlay.queue_redraw()


func _wave(phase: float, delay: float) -> float:
	return sin(phase + delay) - sin(delay)


func set_debug_skeleton(enabled: bool) -> void:
	_build()
	_debug_skeleton = enabled
	_debug_overlay.visible = enabled
	_debug_overlay.queue_redraw()


func _draw_bone_overlay(surface: Node2D) -> void:
	for definition: Array in JOINTS:
		var bone_name: String = definition[0]
		var parent_name: String = definition[1]
		var bone: Bone2D = bones[bone_name]
		var point := to_local(bone.global_position)
		var fixed := bone_name == "bindings" or bone_name == "pelvis" or bone_name.begins_with("hip_") or bone_name.begins_with("knee_") or bone_name.begins_with("ankle_")
		var color := Color(0.1, 0.9, 1.0) if fixed else Color(1.0, 0.3, 0.55)
		if not parent_name.is_empty():
			var parent_bone: Bone2D = bones[parent_name]
			surface.draw_line(to_local(parent_bone.global_position), point, color, 0.65)
		surface.draw_circle(point, 1.3, color)


## CPU evaluation of the same native rest/bone weights used by Polygon2D.
## Inspection only; this never rewrites polygon vertices or texture pixels.
func get_deformed_vertices() -> PackedVector2Array:
	_build()
	var vertices := skin.polygon
	var result := PackedVector2Array()
	result.resize(vertices.size())
	var skeleton_inverse := skeleton.global_transform.affine_inverse()
	for bone_index in skin.get_bone_count():
		var bone: Bone2D = skeleton.get_node(skin.get_bone_path(bone_index))
		var deform := skeleton_inverse * bone.global_transform * bone.get_skeleton_rest().affine_inverse()
		var weights := skin.get_bone_weights(bone_index)
		for vertex_index in vertices.size():
			if weights[vertex_index] > 0.0:
				result[vertex_index] += (deform * vertices[vertex_index]) * weights[vertex_index]
	return result


func get_rig_report() -> Dictionary:
	_build()
	var maximum_error := 0.0
	var maximum_pin_delta := 0.0
	var protected_vertices := 0
	var deformed := get_deformed_vertices()
	var vertices := skin.polygon
	for vertex_index in vertices.size():
		var total := 0.0
		for bone_index in skin.get_bone_count():
			total += skin.get_bone_weights(bone_index)[vertex_index]
		maximum_error = maxf(maximum_error, absf(1.0 - total))
		if _is_protected(vertices[vertex_index]) or _near_lower_binding(vertices[vertex_index]) or vertices[vertex_index].y >= 204.0:
			protected_vertices += 1
			maximum_pin_delta = maxf(maximum_pin_delta, vertices[vertex_index].distance_to(deformed[vertex_index]))
	var hierarchy: Dictionary = {}
	for definition: Array in JOINTS:
		hierarchy[definition[0]] = definition[1]
	return {
		"implementation": "Godot Skeleton2D + Bone2D + one continuous weighted Polygon2D",
		"native_size": [256, 256], "origin": "source_top_left", "foot_anchor": [128, 240],
		"cycle_seconds": CYCLE_SECONDS, "automatic_playback": false,
		"bone_count": bones.size(), "bone_names": bones.keys(), "hierarchy": hierarchy,
		"vertex_count": vertices.size(), "triangle_count": skin.polygons.size(),
		"mesh_step_native_pixels": MESH_STEP, "maximum_influences_per_vertex": 4,
		"maximum_weight_normalization_error": maximum_error,
		"protected_vertex_count": protected_vertices,
		"current_maximum_protected_vertex_displacement": maximum_pin_delta,
		"source_texture_sha256": FileAccess.get_sha256(SOURCE_TEXTURE),
		"texture_filter": "nearest", "mipmaps": false,
	}
