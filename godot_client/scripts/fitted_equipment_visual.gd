class_name FittedEquipmentVisual
extends Node2D
## An independent equipped item, attached through the existing socket registry.
@export var item_id := ""
var current_facing := ""
var part_sprites: Array[Sprite2D] = []
var part_bones: Array[Bone2D] = []
var parts: Array = []
var item_definition: Dictionary = {}
var part_skeleton: Skeleton2D
var current_pose_key := ""
var authored_pose := false

func get_weapon_profile(direction: String) -> Dictionary:
	FittedEquipmentLibrary.initialize()
	var item: Dictionary = FittedEquipmentLibrary.item_data.get(item_id,{})
	if item.get("slot","")!="weapon" or item.get("views",{}).get(direction,[]).is_empty():
		return {}
	var part: Dictionary = item.views[direction][0]
	var family := CharacterWeaponMotion.family_for_name(String(item.name))
	var pivot := FittedEquipmentLibrary.point(part.pivot)
	var support := pivot+Vector2(0,-9)
	var texture := FittedEquipmentLibrary.texture(part.file)
	var tips: Array=[]
	if family=="bow":
		var width := texture.get_width()
		var upper_x := 1 if direction in ["south","south-west","north-west","north","east"] else width-2
		var lower_x := width-2 if direction in ["south-west","north-west","west"] else 1
		tips=[Vector2(upper_x,1),Vector2(lower_x,texture.get_height()-2)]
		support=(tips[0]+tips[1])*0.5
	elif family=="crossbow":
		support=pivot+Vector2.DOWN.rotated(-CharacterSpriteLibrary.DIRECTIONS.find(direction)*PI/4.0)*7.0
	return {"family":family,"texture":texture,"source_key":part.file,"pivot":pivot,"support_grip":support,"string_tips":tips,"source_scale":1.0,"carry_rotation":float(part.get("carryRotation",0.0))}

func bow_source(profile: Dictionary, motion: Dictionary) -> Dictionary:
	var key:="bow-string/"+String(profile.source_key)+"/"+str(motion.frame)+"/"+str(motion.is_attack)
	var margin:=Vector2(16,16)
	if not FittedEquipmentLibrary.textures.has(key):
		var source: Image=profile.texture.get_image()
		var image:=Image.create(source.get_width()+32,source.get_height()+32,false,Image.FORMAT_RGBA8)
		image.blit_rect(source,Rect2i(Vector2i.ZERO,source.get_size()),Vector2i(margin))
		var first: Vector2=profile.string_tips[0]
		var last: Vector2=profile.string_tips[1]
		# Remove the old static string inside its measured tip-to-tip path.
		for y in range(source.get_height()):
			for x in range(source.get_width()):
				var pixel:=Vector2(x,y)
				var nearest:=Geometry2D.get_closest_point_to_segment(pixel,first,last)
				if nearest.distance_to(first)>3 and nearest.distance_to(last)>3 and nearest.distance_to(pixel)<=1.0:
					image.set_pixelv(Vector2i(pixel+margin),Color.TRANSPARENT)
		var nock: Vector2=Vector2(profile.pivot)+(Vector2(motion.secondary)-Vector2(motion.primary)).rotated(-float(motion.rotation))
		for line: Array in [[first,nock],[nock,last]]:
			var steps:=ceili(Vector2(line[0]).distance_to(line[1])*2.0)
			for step in range(steps+1):
				var pixel:=Vector2i((Vector2(line[0]).lerp(line[1],float(step)/maxi(steps,1))+margin).round())
				if Rect2i(Vector2i.ZERO,image.get_size()).has_point(pixel):
					image.set_pixelv(pixel,Color("f5b57a"))
		FittedEquipmentLibrary.textures[key]=ImageTexture.create_from_image(image)
	return {"file":key,"pivot":Vector2(profile.pivot)+margin}

func set_attachment_facing(direction: String) -> void:
	FittedEquipmentLibrary.initialize()
	item_definition = FittedEquipmentLibrary.item_data.get(item_id, {})
	if direction == current_facing or item_definition.is_empty():
		return
	_rebuild_parts(direction, "", item_definition.views.get(direction, []))

func _rebuild_parts(direction: String, pose_key: String, selected: Array) -> void:
	if direction == current_facing and pose_key == current_pose_key and not part_sprites.is_empty():
		return
	current_facing = direction
	current_pose_key = pose_key
	authored_pose = not pose_key.is_empty()
	for sprite: Sprite2D in part_sprites:
		sprite.free()
	for bone: Bone2D in part_bones:
		bone.free()
	part_sprites.clear()
	part_bones.clear()
	if part_skeleton == null:
		part_skeleton = Skeleton2D.new()
		part_skeleton.name = "ArticulatedItemSockets"
		add_child(part_skeleton)
	parts = selected.duplicate()
	parts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.z) < int(b.z))
	for part: Dictionary in parts:
		var bone := Bone2D.new()
		bone.name = String(part.name).validate_node_name()
		bone.set_autocalculate_length_and_angle(false)
		bone.length = 1.0
		part_skeleton.add_child(bone)
		var sprite := Sprite2D.new()
		sprite.name = "Artwork" if parts.size() == 1 else String(part.name).validate_node_name()
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.texture = FittedEquipmentLibrary.texture(part.file)
		sprite.offset = -FittedEquipmentLibrary.point(part.pivot)
		sprite.position = FittedEquipmentLibrary.point(part.get("offset", [0, 0]))
		bone.add_child(sprite)
		part_bones.append(bone)
		part_sprites.append(sprite)

func set_attachment_pose(context: Dictionary) -> void:
	var pose := FittedEquipmentLibrary.frame(context)
	if pose.is_empty() or context.get("pose", {}).is_empty():
		visible = false
		return
	FittedEquipmentLibrary.initialize()
	if item_definition.is_empty():
		item_definition = FittedEquipmentLibrary.item_data.get(item_id, {})
	var action := "run" if String(context.action) == "walk" else "idle"
	var frame_index := str(int(context.frame) if action == "run" else 0)
	var authored: Variant = item_definition.get("poseViews", {}).get(context.direction, {}).get(action, {}).get(frame_index)
	var pose_key := action + "/" + frame_index if authored is Array else ""
	_rebuild_parts(context.direction, pose_key, authored if authored is Array else item_definition.views.get(context.direction, []))
	var parent_socket := get_parent() as Node2D
	rotation = -parent_socket.rotation if parent_socket != null else 0.0
	var root_point := FittedEquipmentLibrary.point(context.pose.get(context.root_socket, [0, 0]))
	var padding: Vector2 = context.padding
	var tracked := FittedEquipmentLibrary.joints(context)
	var rest: Dictionary = FittedEquipmentLibrary.rig_data.rigs[current_facing].frames[0].joints
	var motion: Dictionary = context.get("weapon_motion",{})
	for index in range(parts.size()):
		var part: Dictionary = parts[index]
		var point := FittedEquipmentLibrary.point(tracked[part.socket]) - padding
		if authored_pose and String(item_definition.slot) in ["chest","legs"]:
			# Whole authored80px layers already contain their animation shift.
			point=FittedEquipmentLibrary.point(pose.joints[part.socket])-padding
		# Keep the live game's already calibrated hand grips, including its shield.
		if part.socket == "hand_right":
			point = FittedEquipmentLibrary.point(context.pose.right_hand)
		elif part.socket == "hand_left":
			point = FittedEquipmentLibrary.point(context.pose.left_hand)
		if String(item_definition.slot)=="weapon" and bool(motion.get("active",false)):
			point=Vector2(motion.primary)-padding
		part_bones[index].position = point - root_point
		part_bones[index].rest = part_bones[index].transform
		var angle_delta := 0.0
		part_sprites[index].texture = FittedEquipmentLibrary.texture(part.file)
		part_sprites[index].offset = -FittedEquipmentLibrary.point(part.pivot)
		part_sprites[index].position = FittedEquipmentLibrary.point(part.get("offset", [0, 0]))
		part_sprites[index].scale = Vector2(float(part.get("widthScale", 1.0)), 1.0)
		if bool(part.get("segmentFit", false)):
			# Longitudinal armor pieces span their actual joint pair with a
			# one-pixel overlap at either end, including crossed walking legs.
			var segment := FittedEquipmentLibrary.point(tracked[part.bone]) - FittedEquipmentLibrary.point(tracked[part.socket])
			angle_delta = segment.angle() - PI * 0.5
			part_sprites[index].scale.y = (segment.length() + 2.0) / part_sprites[index].texture.get_height()
		elif String(item_definition.slot) != "shield" and part.get("bone") != null:
			var current := FittedEquipmentLibrary.point(tracked[part.bone]) - FittedEquipmentLibrary.point(tracked[part.socket])
			var reference := FittedEquipmentLibrary.point(rest[part.bone]) - FittedEquipmentLibrary.point(rest[part.socket])
			angle_delta = wrapf(current.angle() - reference.angle(), -PI, PI)
			angle_delta = clampf(angle_delta, -float(part.rotationLimit), float(part.rotationLimit))
		# A bulky weapon may lean outwards while its grip stays exactly on the
		# hand. This is a rest orientation, not a positional socket workaround.
		part_sprites[index].rotation = angle_delta + float(part.get("carryRotation", part.get("restRotation", 0.0)))
		if String(item_definition.slot)=="weapon" and bool(motion.get("active",false)):
			part_sprites[index].rotation=float(motion.rotation)
		if String(item_definition.slot) == "weapon":
			var file:=String(part.file)
			var pivot:=FittedEquipmentLibrary.point(part.pivot)
			var profile: Dictionary=context.get("weapon_profile",{})
			if bool(motion.get("active",false)) and String(profile.get("family",""))=="bow":
				var bow:=bow_source(profile,motion)
				file=bow.file
				pivot=bow.pivot
			var fitted := FittedEquipmentLibrary.native_part(file,pivot, part_sprites[index].position, part_sprites[index].rotation, part_sprites[index].scale)
			part_sprites[index].texture = fitted.texture
			part_sprites[index].offset = fitted.origin
			part_sprites[index].position = Vector2.ZERO
			part_sprites[index].rotation = 0.0
			part_sprites[index].scale = Vector2.ONE
	if String(item_definition.slot) == "legs":
		# Sort complete legs, not every thigh behind every shin. A raised rear
		# foot must remain behind the planted leg when the stride crosses.
		var order := range(parts.size())
		order.sort_custom(func(a: int, b: int) -> bool:
			return _leg_depth(parts[a], tracked) < _leg_depth(parts[b], tracked))
		for index: int in order:
			part_skeleton.move_child(part_bones[index], -1)
	visible = true
	if String(item_definition.slot)=="chest" and bool(motion.get("active",false)):
		visible=false # The same source art is rendered by the articulated torso.

func _leg_depth(part: Dictionary, tracked: Dictionary) -> float:
	if part.socket == "pelvis":
		return 10000.0
	var side := String(part.socket).get_slice("_", 1)
	return FittedEquipmentLibrary.point(tracked["foot_" + side]).y * 100.0 + float(part.z)
