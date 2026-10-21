class_name FittedEquipmentLibrary
extends RefCounted
## The fitted pack follows the existing CharacterVisual animation clock.
const ROOT := "res://Assets/Equipment/fitted_bronze_iron/"
static var rig_data: Dictionary = {}
static var item_data: Dictionary = {}
static var textures: Dictionary = {}
static var bodies: Dictionary = {}
static var forearms: Dictionary = {}

static func initialize() -> void:
	if not rig_data.is_empty():
		return
	rig_data = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "rigs.json"))
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "equipment.json"))
	for item: Dictionary in catalog.items:
		item_data[item.id] = item
	# Approval candidates are opt-in. The normal inventory keeps its catalog
	# until the user accepts the new fit, and no other tier is changed.
	if "--equipment-fit-candidate" in OS.get_cmdline_user_args():
		var candidate: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "side-fit-candidate.json"))
		for patch: Dictionary in candidate.get("items", []):
			if item_data.has(patch.id):
				item_data[patch.id].merge(patch, true)

static func texture(path: String) -> Texture2D:
	if not textures.has(path):
		var resource := load(ROOT + path) as Texture2D
		if resource == null:
			push_error("Missing fitted equipment PNG: " + path)
			return null
		textures[path] = resource
	return textures[path] as Texture2D

static func point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

static func frame(context: Dictionary) -> Dictionary:
	initialize()
	var direction := String(context.get("direction", ""))
	if not rig_data.rigs.has(direction):
		return {}
	var index := 0
	if String(context.get("action", "idle")) == "walk":
		index = posmod(int(context.get("frame", 0)), 8) + 1
	return rig_data.rigs[direction].frames[index]

static func joints(context: Dictionary) -> Dictionary:
	var pose := frame(context)
	if pose.is_empty():
		return {}
	var result: Dictionary = pose.joints.duplicate(true)
	# One hand track for the skin, sleeves AND held items. The old fitted pack
	# had a second, approximate hand track which pulled elbows away from grips.
	for side: String in ["right", "left"]:
		var hand := point(context.pose[side + "_hand"]) + Vector2(context.padding)
		result["hand_" + side] = [hand.x, hand.y]
		var shoulder := point(result["shoulder_" + side])
		var elbow := shoulder.lerp(hand, 0.55).round()
		result["elbow_" + side] = [elbow.x, elbow.y]
	return result

static func _limb(image: Image, a: Vector2, b: Vector2, radius: float) -> void:
	# Pixel-snapped, continuous fitted arming clothes, NOT a robe. These sit
	# below independent metal plates and bridge flex joints in every pose.
	var first := (a.min(b) - Vector2.ONE * radius).floor().max(Vector2.ZERO)
	var last := (a.max(b) + Vector2.ONE * radius).ceil().min(Vector2(79, 79))
	for y in range(int(first.y), int(last.y) + 1):
		for x in range(int(first.x), int(last.x) + 1):
			var pixel := Vector2(x, y)
			var nearest := Geometry2D.get_closest_point_to_segment(pixel, a, b)
			var distance := pixel.distance_to(nearest)
			if distance > radius:
				continue
			var color := Color("171b20")
			if distance <= radius - 0.9:
				color = Color("353b40") if x < nearest.x else Color("252b30")
			if distance <= radius - 1.5 and x < nearest.x - 0.5:
				color = Color("4a5054")
			image.set_pixel(x, y, color)

static func _hand(image: Image, source: Image, center: Vector2) -> void:
	# Keep the actual character's skin pixels, not the square patch of robe
	# that used to be redrawn over armored wrists.
	for y in range(maxi(0, int(center.y) - 3), mini(80, int(center.y) + 4)):
		for x in range(maxi(0, int(center.x) - 3), mini(80, int(center.x) + 4)):
			var color := source.get_pixel(x, y)
			if color.a > 0.0 and color.r > 0.42 and color.r > color.g * 1.2 and color.g > color.b * 1.05:
				image.set_pixel(x, y, color)

static func forearm_texture(context: Dictionary, side: String) -> Texture2D:
	var pose := frame(context)
	var key := String(pose.original) + side
	if forearms.has(key):
		return forearms[key]
	var tracked := joints(context)
	var image := Image.create(80, 80, false, Image.FORMAT_RGBA8)
	var hand := point(tracked["hand_" + side])
	var elbow := point(tracked["elbow_" + side])
	_limb(image, elbow, hand.lerp(elbow, 0.2), 2.6)
	_hand(image, texture(pose.original).get_image(), hand)
	var result := ImageTexture.create_from_image(image)
	forearms[key] = result
	return result

static func hand_texture(context: Dictionary, side: String) -> Texture2D:
	var pose := frame(context)
	var key := String(pose.original) + side + "_hand"
	if not forearms.has(key):
		var image := Image.create(80, 80, false, Image.FORMAT_RGBA8)
		_hand(image, texture(pose.original).get_image(), point(joints(context)["hand_" + side]))
		forearms[key] = ImageTexture.create_from_image(image)
	return forearms[key]

static func base_texture(pose: Dictionary, flags: Dictionary, context: Dictionary = {}) -> Texture2D:
	var chest := bool(flags.get("chest", false))
	var legs := bool(flags.get("legs", false))
	var head := bool(flags.get("head", false))
	var key := "%s/%s/%s/%s" % [pose.original, chest, legs, head]
	if bodies.has(key):
		return bodies[key] as Texture2D
	var image := texture(pose.body if chest else pose.original).get_image()
	image.convert(Image.FORMAT_RGBA8)
	var head_image := texture(pose.head).get_image()
	head_image.convert(Image.FORMAT_RGBA8)
	var tracked: Dictionary = joints(context) if not context.is_empty() else pose.joints
	var pelvis := point(tracked.pelvis)
	var chest_point := point(tracked.chest)
	var neck := point(tracked.neck)
	var torso_half_width := 8.0 if String(pose.direction) in ["east", "west"] else 10.0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if legs and y >= int(pelvis.y) - 1:
				image.set_pixel(x, y, Color.TRANSPARENT)
			elif chest and y >= int(neck.y) and y < int(pelvis.y) + 3 and absf(x - chest_point.x) > torso_half_width:
				image.set_pixel(x, y, Color.TRANSPARENT)
			elif head or chest:
				var color := image.get_pixel(x, y)
				color.a = maxf(0.0, color.a - head_image.get_pixel(x, y).a)
				image.set_pixel(x, y, color)
	if legs:
		_limb(image, point(tracked.hip_left), point(tracked.hip_right), 3.4)
		for side: String in ["left", "right"]:
			var hip := point(tracked["hip_" + side])
			var knee := point(tracked["knee_" + side])
			var foot := point(tracked["foot_" + side])
			_limb(image, hip, knee, 3.3)
			_limb(image, knee, foot - Vector2(0, 1), 2.8)
	if chest:
		var original := texture(pose.original).get_image()
		for side: String in ["left", "right"]:
			var shoulder := point(tracked["shoulder_" + side])
			var elbow := point(tracked["elbow_" + side])
			var hand := point(tracked["hand_" + side])
			_limb(image, shoulder, elbow, 3.4)
			_limb(image, elbow, hand.lerp(elbow, 0.2), 2.6)
			_hand(image, original, hand)
	var result := ImageTexture.create_from_image(image)
	bodies[key] = result
	return result
