class_name PlayerArmArt
extends RefCounted
## Segments existing native artwork. Every visible pixel is copied from source.
const SIDES := ["left", "right"]
const PARTS := ["upper", "forearm", "hand"]


static func split(source: Image, joints: Dictionary, armored: bool, head_mask: Image = null, hand_masks: Dictionary = {}, hidden_sides: Array = []) -> Dictionary:
	var image := source.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var result := {"torso": _blank(), "shoulders": _blank(), "lower": _blank(), "arms": {}, "raw_arms": {}}
	var chest := _point(joints.get("chest", [40, 43]))
	var pelvis := _point(joints.get("pelvis", [40, 52]))
	var neck := _point(joints.get("neck", [40, 37]))
	var shoulder_span := absf(_point(joints.get("shoulder_left", [51, 39])).x - _point(joints.get("shoulder_right", [29, 39])).x)
	# Side-view shoulders overlap in projection; their separation is not
	# the body's width. Preserve the native torso beneath the moving arms,
	# including the unarmored robe, rather than leaving a narrow center strip.
	var torso_core := clampf(shoulder_span * 0.325, 8.0, 10.0)
	var hands := {}
	for side: String in SIDES:
		var shoulder := _point(joints.get("shoulder_" + side, [40, 39]))
		var wrist := _point(joints.get("hand_" + side, [40, 51]))
		result.arms[side] = {
			"upper": _blank(), "forearm": _blank(), "hand": _blank(),
			"shoulder": shoulder, "elbow": _point(joints.get("elbow_" + side, [shoulder.x, (shoulder.y + wrist.y) * 0.5])),
			"wrist": wrist, "borrowed": false
		}
		hands[side] = hand_masks.get(side,_hand_pixels(image, wrist))
	for y in range(mini(80, image.get_height())):
		for x in range(mini(80, image.get_width())):
			var pixel := Vector2i(x, y)
			var color := image.get_pixelv(pixel)
			if color.a == 0.0:
				continue
			if head_mask != null and y < neck.y and x < head_mask.get_width() and y < head_mask.get_height() and head_mask.get_pixelv(pixel).a > 0.0:
				continue
			var location := Vector2(pixel)
			var selected := ""
			var nearest := INF
			var is_palm := false
			for side: String in SIDES:
				var arm: Dictionary = result.arms[side]
				var distance := minf(_distance(location, arm.shoulder, arm.elbow), _distance(location, arm.elbow, arm.wrist))
				var actual_hand: bool = hands[side].has(pixel)
				if location.distance_to(arm.shoulder)<=6.25 and (head_mask==null or head_mask.get_pixelv(pixel).a==0.0):
					# Fixed shoulder caps/sleeves cover the upper-arm hinge.
					# Keeping these only on the torso lets a rotated arm repaint them.
					result.shoulders.set_pixelv(pixel,color)
				is_palm = is_palm or (actual_hand and side not in hidden_sides)
				if armored and location.distance_to(arm.shoulder)<=6.25:
					# The complete native pauldron stays with the chest. The
					# moving-arm cut must not turn its round plate into fragments.
					result.torso.set_pixelv(pixel,color)
				# Shoulder caps stay fixed on the breastplate; lower contours move.
				var cap: bool = armored and location.distance_to(arm.shoulder) <= 4.0 and y <= arm.shoulder.y + 2.0
				if cap and y >= arm.shoulder.y and location.distance_to(arm.shoulder) <= 2.25:
					# The fixed pauldron remains intact. Its native lower hinge
					# overlaps the upper arm so rotation cannot expose a bare gap.
					arm.upper.set_pixelv(pixel, color)
				var closer_than_torso := distance + 0.35 < _distance(location, chest, pelvis)
				# Flared cuffs and their ink can sit outside the narrow bone
				# corridor, including below the waist. They still move with it.
				var cuff: bool = y >= arm.elbow.y and location.distance_to(arm.wrist) <= 6.0 and closer_than_torso
				if not cap and y >= neck.y - 1.0 and (actual_hand or cuff or (distance <= 4.25 and closer_than_torso)):
					var score := distance - (10.0 if actual_hand else 0.0)
					if score < nearest:
						nearest = score
						selected = side
			if not is_palm and y >= neck.y and y < pelvis.y and _distance(location, chest, pelvis) <= torso_core:
				# A side-view arm may occlude the breastplate in the source.
				# Keep its actual central contour too, rather than turning the
				# torso into a thin strip when those native arm pixels move.
				result.torso.set_pixelv(pixel, color)
			if selected.is_empty():
				var body: Image = result.lower if y >= pelvis.y else result.torso
				body.set_pixelv(pixel, color)
				continue
			var arm: Dictionary = result.arms[selected]
			if hands[selected].has(pixel):
				arm.hand.set_pixelv(pixel, color)
			else:
				var upper_distance := _distance(location, arm.shoulder, arm.elbow)
				var lower_distance := _distance(location, arm.elbow, arm.wrist)
				var part: Image = arm.upper if upper_distance <= lower_distance else arm.forearm
				part.set_pixelv(pixel, color)
				# One shared elbow pixel prevents a transparent hinge without
				# expanding either original contour or inventing joint colors.
				if location.distance_to(arm.elbow) <= 1.0:
					arm.upper.set_pixelv(pixel, color)
					arm.forearm.set_pixelv(pixel, color)
	if armored:
		# This input is a complete chest export, including belt overlap and
		# occasional clipped arm tails below its pelvis marker. Classify them
		# with the rest of the contours before selecting the fixed torso.
		result.torso.blend_rect(result.lower,Rect2i(0,0,80,80),Vector2i.ZERO)
		result.lower=_blank()
		_move_detached_contours(result, hands)
	# Keep the original source partition available for diagnostics. A hidden
	# far arm can borrow the other arm's source art AND all its rest joints;
	# original arm fragments never remain painted on the visible torso.
	for side: String in SIDES:
		result.raw_arms[side] = result.arms[side].duplicate()
	for side: String in SIDES:
		var donor := "right" if side == "left" else "left"
		if (side in hidden_sides or not _usable(result.raw_arms[side])) and _usable(result.raw_arms[donor]):
			result.arms[side] = result.raw_arms[donor].duplicate()
			result.arms[side].borrowed = true
			result.arms[side].donor = donor
	return result


static func _move_detached_contours(parts: Dictionary, hands: Dictionary) -> void:
	var torso: Image = parts.torso
	var remaining := {}
	for y in range(80):
		for x in range(80):
			if torso.get_pixel(x, y).a > 0.0:
				remaining[Vector2i(x, y)] = true
	var contours: Array = []
	var largest := 0
	while not remaining.is_empty():
		var contour: Array[Vector2i] = [remaining.keys()[0]]
		remaining.erase(contour[0])
		var cursor := 0
		while cursor < contour.size():
			var pixel := contour[cursor]
			cursor += 1
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var neighbor := pixel + Vector2i(dx, dy)
					if remaining.has(neighbor):
						remaining.erase(neighbor)
						contour.append(neighbor)
		if contours.is_empty() or contour.size() > contours[largest].size():
			largest = contours.size()
		contours.append(contour)
	# The breastplate and its fixed shoulder caps are the connected central
	# contour. Small detached edge strips are original arm ink outside the
	# narrow bone corridor; move them with that arm rather than leave ghosts.
	for index in range(contours.size()):
		if index == largest:
			continue
		var selected := "left"
		var nearest := INF
		for side: String in SIDES:
			var arm: Dictionary = parts.arms[side]
			var total := 0.0
			for pixel: Vector2i in contours[index]:
				total += minf(_distance(Vector2(pixel), arm.shoulder, arm.elbow), _distance(Vector2(pixel), arm.elbow, arm.wrist))
			if total < nearest:
				nearest = total
				selected = side
		var arm: Dictionary = parts.arms[selected]
		for pixel: Vector2i in contours[index]:
			var color := torso.get_pixelv(pixel)
			torso.set_pixelv(pixel, Color.TRANSPARENT)
			if hands[selected].has(pixel):
				arm.hand.set_pixelv(pixel, color)
			else:
				var target: Image = arm.upper if _distance(Vector2(pixel), arm.shoulder, arm.elbow) <= _distance(Vector2(pixel), arm.elbow, arm.wrist) else arm.forearm
				target.set_pixelv(pixel, color)


static func _hand_pixels(source: Image, wrist: Vector2) -> Dictionary:
	var selected := {}
	var candidates := {}
	var seed := Vector2i(-1, -1)
	var nearest := INF
	var neighbors: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]
	# The authored wrist is the actual glove center. A bounded contour is
	# safer than hue alone: bronze and flesh shadows share several hues.
	for y in range(maxi(0, int(wrist.y) - 4), mini(source.get_height(), int(wrist.y) + 5)):
		for x in range(maxi(0, int(wrist.x) - 4), mini(source.get_width(), int(wrist.x) + 5)):
			var pixel := Vector2i(x, y)
			var color := source.get_pixelv(pixel)
			var distance := Vector2(pixel).distance_to(wrist)
			var flesh := color.a > 0.0 and color.r > 0.27 and color.r > color.g * 1.15 and color.g > color.b * 1.05 and color.g < color.b * 1.5
			if distance <= 3.5 and flesh:
				candidates[pixel] = true
				if distance < nearest:
					nearest = distance
					seed = pixel
	var skin: Array[Vector2i] = []
	if seed.x >= 0:
		skin.append(seed)
		selected[seed] = true
	var cursor := 0
	while cursor < skin.size():
		var pixel := skin[cursor]
		cursor += 1
		for offset: Vector2i in neighbors:
			var neighbor := pixel + offset
			if candidates.has(neighbor) and not selected.has(neighbor):
				selected[neighbor] = true
				skin.append(neighbor)
	for pixel: Vector2i in skin:
		for offset: Vector2i in neighbors:
			var neighbor := pixel + offset
			if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= source.get_width() or neighbor.y >= source.get_height() or Vector2(neighbor).distance_to(wrist) > 3.5:
				continue
			var color := source.get_pixelv(neighbor)
			if color.a > 0.0 and maxf(color.r, maxf(color.g, color.b)) < 0.3:
				selected[neighbor] = true
	return selected


static func _usable(arm: Dictionary) -> bool:
	for part: String in PARTS:
		if not (arm[part] as Image).get_used_rect().has_area():
			return false
	return true

static func lower_body(image: Image, joints: Dictionary) -> Image:
	# The lower section owns both legs/feet. Disconnected sleeve/hand
	# fragments from the old upper body must leave with that upper body.
	var output:=image.duplicate() as Image
	var remaining: Dictionary={}
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x,y).a>0.0:
				remaining[Vector2i(x,y)]=true
	while not remaining.is_empty():
		var pixels: Array[Vector2i]=[remaining.keys()[0]]
		remaining.erase(pixels[0])
		var cursor:=0
		var leg:=false
		while cursor<pixels.size():
			var pixel:=pixels[cursor]
			cursor+=1
			for side: String in SIDES:
				if Vector2(pixel).distance_to(_point(joints["foot_"+side]))<=4.0:
					leg=true
			for dy in range(-1,2):
				for dx in range(-1,2):
					var neighbor:=pixel+Vector2i(dx,dy)
					if remaining.has(neighbor):
						remaining.erase(neighbor)
						pixels.append(neighbor)
		if not leg:
			for pixel: Vector2i in pixels:
				output.set_pixelv(pixel,Color.TRANSPARENT)
	return output


static func _blank() -> Image:
	return Image.create(80, 80, false, Image.FORMAT_RGBA8)


static func _point(value: Variant) -> Vector2:
	return value if value is Vector2 else Vector2(float(value[0]), float(value[1]))


static func _distance(pixel: Vector2, first: Vector2, last: Vector2) -> float:
	return pixel.distance_to(Geometry2D.get_closest_point_to_segment(pixel, first, last))


static func _skin(color: Color) -> bool:
	# Skin's muted red/peach palette differs from the saturated bronze plates.
	# The blue ratio prevents a bronze vambrace from becoming a giant hand.
	return color.a > 0.0 and color.r > 0.42 and color.r > color.g * 1.2 and color.g > color.b * 1.05 and color.g < color.b * 1.38
