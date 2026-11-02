class_name FittedEquipmentLibrary
extends RefCounted
## The fitted pack follows the existing CharacterVisual animation clock.
const ROOT := "res://Assets/Equipment/fitted_bronze_iron/"
static var rig_data: Dictionary = {}
static var item_data: Dictionary = {}
static var textures: Dictionary = {}
static var bodies: Dictionary = {}
static var forearms: Dictionary = {}
static var native_parts: Dictionary = {}
static var replacement_tracks: Dictionary = {}
static var complete_heads: Dictionary = {}
static var armor_arm_rigs: Dictionary = {}

static func motion_rest_joints(context: Dictionary) -> Dictionary:
	var direction:=String(context.direction)
	var idle: Dictionary=rig_data.rigs[direction].frames[0]
	if not context.get("body_pose",{}).is_empty():
		if armor_arm_rigs.is_empty():
			var path:="res://data/bronze_armor_arm_rig.json"
			if FileAccess.file_exists(path):
				armor_arm_rigs=JSON.parse_string(FileAccess.get_file_as_string(path))
		var entry: Dictionary=armor_arm_rigs.get("directions",{}).get(direction,{})
		if not entry.is_empty():
			var joints: Dictionary=idle.joints.duplicate(true)
			joints.merge(entry.joints,true)
			joints.back=joints.neck
			return joints
	var result: Dictionary=idle.joints.duplicate(true)
	result.back=result.neck
	return result

static func motion_upper_shift(context: Dictionary) -> Vector2:
	var pose:=frame(context)
	var idle: Dictionary=rig_data.rigs[String(context.direction)].frames[0]
	var current_shift:=point(context.get("body_pose",{}).get("bodyOffset",[0,0]))
	var idle_context: Dictionary=context.duplicate()
	idle_context.action="idle"
	idle_context.frame=0
	var idle_track:=replacement_pose(String(context.get("chest_item_id","")),idle_context)
	return point(pose.joints.head)+current_shift-point(idle.joints.head)-point(idle_track.get("bodyOffset",[0,0]))

static func motion_head_offset(context: Dictionary) -> Vector2:
	var idle_context: Dictionary=context.duplicate()
	idle_context.action="idle"
	idle_context.frame=0
	var idle_track:=replacement_pose(String(context.get("chest_item_id","")),idle_context)
	return point(idle_track.get("headOffset",[0,0]))
const HAIR_COLORS := [Color("523d2f"), Color("31231c"), Color("2c201a"), Color("49372c"), Color("281c15"), Color("382c25"), Color("3f3129")]

## Extend the supplied head cut through its connected face and ink outline.
## Copy source RGBA only: armor cannot recolor or reshape the character's jaw.
static func head_texture(pose: Dictionary) -> Texture2D:
	var key := String(pose.original)
	if complete_heads.has(key):
		return complete_heads[key]
	var source := texture(pose.original).get_image()
	var supplied := texture(pose.head).get_image()
	var image := Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8)
	var selected := {}
	var pending: Array[Vector2i] = []
	var hair: Array[Vector2i] = []
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := Vector2i(x,y)
			if supplied.get_pixelv(pixel).a == 0.0:
				continue
			var color := source.get_pixelv(pixel)
			if color in HAIR_COLORS:
				hair.append(pixel)
			if _is_skin(color):
				selected[pixel] = true
				pending.append(pixel)
	# Robe shadows can share a dark hair color. Keep only hair clusters that
	# reach the crown; disconnected shoulder/robe clusters are not head art.
	var remaining_hair := {}
	for pixel: Vector2i in hair:
		remaining_hair[pixel] = true
	hair.clear()
	var crown_limit := source.get_used_rect().position.y + 10
	while not remaining_hair.is_empty():
		var cluster: Array[Vector2i] = [remaining_hair.keys()[0]]
		remaining_hair.erase(cluster[0])
		var first_row := cluster[0].y
		var index := 0
		while index < cluster.size():
			var pixel := cluster[index]
			index += 1
			first_row = mini(first_row,pixel.y)
			for dy in range(-1,2):
				for dx in range(-1,2):
					var next := pixel + Vector2i(dx,dy)
					if remaining_hair.has(next):
						remaining_hair.erase(next)
						cluster.append(next)
		if first_row < crown_limit:
			hair.append_array(cluster)
	var cursor := 0
	while cursor < pending.size():
		var pixel := pending[cursor]
		cursor += 1
		for dy in range(-1,2):
			for dx in range(-1,2):
				var next := pixel + Vector2i(dx,dy)
				if next.x < 0 or next.y < 0 or next.x >= source.get_width() or next.y >= source.get_height() or selected.has(next):
					continue
				if _is_skin(source.get_pixelv(next)):
					selected[next] = true
					pending.append(next)
	# Trace only hair/face/ears, excluding robe triangles in the supplied cut.
	# Face shadows, eyes, mouth and jaw ink remain inside this native contour.
	var silhouette: Array[Vector2i] = pending.duplicate()
	silhouette.append_array(hair)
	for y in range(image.get_height()):
		var left := image.get_width()
		var right := -1
		for pixel: Vector2i in silhouette:
			if pixel.y == y:
				left = mini(left, pixel.x)
				right = maxi(right, pixel.x)
		for x in range(left, right + 1):
			image.set_pixel(x,y,source.get_pixel(x,y))
	for pixel: Vector2i in silhouette:
		for dy in range(-2,3):
			for dx in range(-2,3):
				var next := pixel + Vector2i(dx,dy)
				if next.x < 0 or next.y < 0 or next.x >= source.get_width() or next.y >= source.get_height():
					continue
				var color := source.get_pixelv(next)
				if color.a > 0.0 and maxf(color.r, maxf(color.g,color.b)) < 0.28:
					image.set_pixelv(next,color)
	# The crown contains only the original head. Preserve even isolated ink
	# tips/highlights there; lower rows use the traced contour to reject robe.
	for y in range(int(pose.joints.head[1])):
		for x in range(source.get_width()):
			image.set_pixel(x,y,source.get_pixel(x,y))
	var result := ImageTexture.create_from_image(image)
	complete_heads[key] = result
	return result

static func _is_skin(color: Color) -> bool:
	return color.a > 0.0 and color.r > 0.42 and color.r > color.g * 1.2 and color.g > color.b * 1.05

## Fit transformed hand items once on their native pixel grid, then display
## whole pixels like the character. Never resample armor to match bare limbs.
static func native_part(path: String, pivot: Vector2, offset: Vector2, angle: float, size: Vector2) -> Dictionary:
	var key := "%s/%s/%s/%s/%s" % [path, pivot, offset, angle, size]
	if native_parts.has(key):
		return native_parts[key]
	var source := texture(path).get_image()
	source.convert(Image.FORMAT_RGBA8)
	var transform := Transform2D(angle, size, 0.0, offset)
	var bounds := Rect2(transform * -pivot, Vector2.ZERO)
	for corner: Vector2 in [Vector2(source.get_width(), 0), Vector2(0, source.get_height()), Vector2(source.get_size())]:
		bounds = bounds.expand(transform * (corner - pivot))
	var origin := bounds.position.floor()
	var dimensions := Vector2i(bounds.end.ceil() - origin).max(Vector2i.ONE)
	var result := Image.create(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8)
	var inverse := transform.affine_inverse()
	for y in range(dimensions.y):
		for x in range(dimensions.x):
			var sample := Vector2i((inverse * (origin + Vector2(x + 0.5, y + 0.5)) + pivot).floor())
			if sample.x >= 0 and sample.y >= 0 and sample.x < source.get_width() and sample.y < source.get_height():
				result.set_pixel(x, y, source.get_pixel(sample.x, sample.y))
	# Nearest inverse sampling can drop a one-pixel bowstring or disconnect a
	# thin limb. Conservatively carry connected source centers onto the same
	# grid, filling only transparent gaps with original palette colors.
	for y in range(source.get_height()):
		for x in range(source.get_width()):
			var color := source.get_pixel(x,y)
			if color.a == 0.0:
				continue
			var first := (transform * (Vector2(x+0.5,y+0.5) - pivot) - origin - Vector2.ONE * 0.5).round()
			_native_sample(result,Vector2i(first),color)
			for neighbor: Vector2i in [Vector2i(1,0),Vector2i(0,1),Vector2i(1,1),Vector2i(-1,1)]:
				var other := Vector2i(x,y) + neighbor
				if other.x < 0 or other.y < 0 or other.x >= source.get_width() or other.y >= source.get_height() or source.get_pixelv(other).a == 0.0:
					continue
				var last := (transform * (Vector2(other) + Vector2.ONE * 0.5 - pivot) - origin - Vector2.ONE * 0.5).round()
				var steps := maxi(1,int(maxf(absf(last.x-first.x),absf(last.y-first.y))))
				for step in range(1,steps):
					_native_sample(result,Vector2i(first.lerp(last,float(step)/steps).round()),color)
	var fitted := {"texture":ImageTexture.create_from_image(result), "origin":origin}
	native_parts[key] = fitted
	return fitted

static func _native_sample(image: Image, pixel: Vector2i, color: Color) -> void:
	if pixel.x >= 0 and pixel.y >= 0 and pixel.x < image.get_width() and pixel.y < image.get_height() and image.get_pixelv(pixel).a == 0.0:
		image.set_pixelv(pixel,color)

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

static func replacement_pose(item_id: String, context: Dictionary) -> Dictionary:
	initialize()
	var track := String(item_data.get(item_id, {}).get("replacementTrack", ""))
	if track.is_empty():
		return {}
	if not replacement_tracks.has(track):
		replacement_tracks[track] = JSON.parse_string(FileAccess.get_file_as_string(ROOT + track))
	var action := "run" if String(context.get("action", "idle")) == "walk" else "idle"
	var index := str(int(context.get("frame", 0)) if action == "run" else 0)
	return replacement_tracks[track].get(context.get("direction", ""), {}).get(action, {}).get(index, {})

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
	var motion: Dictionary = context.get("weapon_motion",{})
	if bool(motion.get("active",false)):
		return motion.joints.duplicate(true)
	return source_joints(context)

static func source_joints(context: Dictionary) -> Dictionary:
	var pose := frame(context)
	if pose.is_empty():
		return {}
	var result: Dictionary = pose.joints.duplicate(true)
	var body: Dictionary = context.get("body_pose",{})
	var shift := point(body.get("bodyOffset",[0,0]))
	for name: String in result:
		var location := point(result[name])+shift
		result[name]=[location.x,location.y]
	var head := point(pose.joints.head)+point(body.get("headOffset",[0,0]))
	result.head=[head.x,head.y]
	var back := point(context.get("source_pose",{}).get("back",pose.joints.chest))+Vector2(context.get("padding",Vector2.ZERO))+shift
	result.back=[back.x,back.y]
	# One hand track for the skin, sleeves AND held items. The old fitted pack
	# had a second, approximate hand track which pulled elbows away from grips.
	for side: String in ["right", "left"]:
		var hand := point(body.get("hands",{}).get(side+"_hand", context.get("source_pose",context.pose).get(side+"_hand",[0,0])))
		if not body.get("hands",{}).has(side+"_hand"):
			hand += Vector2(context.padding)
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
	var replacement: Dictionary = context.get("body_pose", {})
	if not replacement.is_empty():
		var replacement_key := String(replacement.source) + side + "_replacement_hand"
		if not forearms.has(replacement_key):
			var image := Image.create(80, 80, false, Image.FORMAT_RGBA8)
			var source := texture(replacement.source).get_image()
			for pixel: Array in replacement.get("handPixels", {}).get(side, []):
				image.set_pixel(int(pixel[0]), int(pixel[1]), source.get_pixel(int(pixel[0]), int(pixel[1])))
			forearms[replacement_key] = ImageTexture.create_from_image(image)
		return forearms[replacement_key]
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
	var replacement_chest := bool(flags.get("replacement_chest", false))
	var replacement_legs := bool(flags.get("replacement_legs", false))
	var key := "%s/%s/%s/%s/%s/%s" % [pose.original, chest, legs, head, replacement_chest, replacement_legs]
	if bodies.has(key):
		return bodies[key] as Texture2D
	# CompressedTexture2D may return the same CPU Image to every caller.
	# Masks must edit a private copy or future loadouts lose source pixels.
	var image := texture(pose.body if chest and not replacement_chest else pose.original).get_image().duplicate() as Image
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
			if replacement_chest and y < int(pelvis.y) + 1:
				# The armor frame owns the entire torso/arms, including empty
				# space between them. No old robe or procedural limbs remain.
				image.set_pixel(x, y, Color.TRANSPARENT)
			elif legs and y >= int(pelvis.y) - 1:
				image.set_pixel(x, y, Color.TRANSPARENT)
			elif chest and y >= int(neck.y) and y < int(pelvis.y) + 3 and absf(x - chest_point.x) > torso_half_width:
				image.set_pixel(x, y, Color.TRANSPARENT)
			elif head or chest:
				var color := image.get_pixel(x, y)
				color.a = maxf(0.0, color.a - head_image.get_pixel(x, y).a)
				image.set_pixel(x, y, color)
	if replacement_chest and not legs:
		# Old hands may swing below the waist cut. They belong to the old
		# torso, not to the unequipped legs, and must disappear with it.
		var source := texture(pose.original).get_image()
		var old_hands := Image.create(80, 80, false, Image.FORMAT_RGBA8)
		for side: String in ["left", "right"]:
			var hand: Array = context.get("source_pose", {}).get(side + "_hand", [])
			if not hand.is_empty():
				_hand(old_hands, source, point(hand) + Vector2(context.padding))
		for y in range(80):
			for x in range(80):
				if old_hands.get_pixel(x, y).a == 0.0:
					continue
				image.set_pixel(x, y, Color.TRANSPARENT)
				for yy in range(maxi(0, y - 1), mini(80, y + 2)):
					for xx in range(maxi(0, x - 1), mini(80, x + 2)):
						var color := source.get_pixel(xx, yy)
						if maxf(color.r, maxf(color.g, color.b)) < 0.28:
							image.set_pixel(xx, yy, Color.TRANSPARENT)
	if legs and not replacement_legs:
		_limb(image, point(tracked.hip_left), point(tracked.hip_right), 3.4)
		for side: String in ["left", "right"]:
			var hip := point(tracked["hip_" + side])
			var knee := point(tracked["knee_" + side])
			var foot := point(tracked["foot_" + side])
			_limb(image, hip, knee, 3.3)
			_limb(image, knee, foot - Vector2(0, 1), 2.8)
	if chest and not replacement_chest:
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
