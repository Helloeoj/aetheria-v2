class_name PlayerArticulatedBody
extends RefCounted
## Native source contours are posed as rigid upper/forearm/hand pieces.
## The torso and complete legs remain independent; no limb image is stretched.
static var sources: Dictionary = {}
static var image_keys: Dictionary = {}
var visual: AnimatedSprite2D
var torso: Sprite2D
var shoulders: Sprite2D
var lower: Sprite2D
var arm_sprites: Dictionary = {}
var near_sides: Array[String] = []
var hand_targets: Dictionary = {}

func configure(parent: AnimatedSprite2D) -> void:
	visual=parent
	torso=make_sprite("ArmorMotionTorso")
	shoulders=make_sprite("ArmorMotionShoulders")
	lower=make_sprite("ArmorMotionLowerBody")
	for side: String in ["right","left"]:
		arm_sprites[side]={}
		for part: String in ["upper","forearm","hand"]:
			arm_sprites[side][part]=make_sprite("ArmorMotion"+part.capitalize()+"_"+side)

func make_sprite(label: String) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name=label
	sprite.centered=false
	sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.visible=false
	visual.add_child(sprite)
	return sprite

func hide() -> void:
	torso.visible=false
	shoulders.visible=false
	lower.visible=false
	for side: String in arm_sprites:
		for part: Sprite2D in arm_sprites[side].values():
			part.visible=false

func ordered_arms(near: bool, include_hands := true) -> Array:
	var result: Array=[]
	for side: String in ["left","right"]:
		if near_sides.has(side)==near:
			result.append_array([arm_sprites[side].upper,arm_sprites[side].forearm])
			if include_hands:
				result.append(arm_sprites[side].hand)
	return result

func ordered_hands(near: bool) -> Array:
	var result: Array=[]
	for side: String in ["left","right"]:
		if near_sides.has(side)==near:
			result.append(arm_sprites[side].hand)
	return result

func ordered_arm_part(near: bool, part: String) -> Array:
	var result: Array=[]
	for side: String in ["left","right"]:
		if near_sides.has(side)==near:
			result.append(arm_sprites[side][part])
	return result

static func source_parts(context: Dictionary) -> Dictionary:
	var idle: Dictionary=FittedEquipmentLibrary.rig_data.rigs[String(context.direction)].frames[0]
	var armored: bool=not context.get("body_pose",{}).is_empty()
	var material:=String(context.get("chest_item_id","bronze-platebody")).get_slice("-",0)
	var source_key:="replacement-v1/%s/chest/%s/0.png" % [material,String(context.direction)] if armored else String(idle.original)
	var cache_key:=source_key+"/idle/"+str(armored)
	if not sources.has(cache_key):
		var image:=FittedEquipmentLibrary.texture(source_key).get_image()
		var hand_masks: Dictionary={}
		if armored:
			# The chest export clips some palms at its lower boundary. Restore
			# only bounded original flesh/ink, never another tier's metal.
			image=image.duplicate() as Image
			var full_path:="replacement-v1/source/%s/0.png" % String(context.direction)
			var full:=FittedEquipmentLibrary.texture(full_path).get_image()
			var rest:=FittedEquipmentLibrary.motion_rest_joints(context)
			for side: String in ["right","left"]:
				var pixels:=PlayerArmArt._hand_pixels(full,FittedEquipmentLibrary.point(rest["hand_"+side]))
				hand_masks[side]=pixels
				for pixel: Vector2i in pixels:
					if image.get_pixelv(pixel).a==0.0:
						image.set_pixelv(pixel,full.get_pixelv(pixel))
		var mask: Image=FittedEquipmentLibrary.head_texture(idle).get_image() if not armored else null
		var hidden: Array=FittedEquipmentLibrary.armor_arm_rigs.get("directions",{}).get(String(context.direction),{}).get("hidden",[]) if armored else []
		sources[cache_key]=PlayerArmArt.split(image,FittedEquipmentLibrary.motion_rest_joints(context),armored,mask,hand_masks,hidden)
		var limbs: Dictionary=sources[cache_key].arms
		for side: String in ["right","left"]:
			var donor: String="left" if side=="right" else "right"
			var arm: Dictionary=limbs[side]
			var other: Dictionary=limbs[donor]
			var length:=Vector2(arm.shoulder).distance_to(arm.elbow)+Vector2(arm.elbow).distance_to(arm.wrist)
			var other_length:=Vector2(other.shoulder).distance_to(other.elbow)+Vector2(other.elbow).distance_to(other.wrist)
			if length<other_length*0.8:
				# A foreshortened far arm cannot supply an extended two-hand
				# pose. Reuse the complete native contour and its real pivots.
				limbs[side]=other.duplicate()
				limbs[side].borrowed=true
	sources[cache_key]["_cache_key"]=cache_key
	return sources[cache_key]

func sync(context: Dictionary, flags: Dictionary) -> void:
	var motion: Dictionary=context.weapon_motion
	var pose:=FittedEquipmentLibrary.frame(context)
	var parts:=source_parts(context)
	var cache_key:=String(parts._cache_key)
	var origin: Vector2=context.origin-context.padding
	var shift: Vector2=Vector2(motion.torso_shift)+Vector2(motion.upper_shift)
	pose_image(torso,parts.torso,cache_key+"/torso",Vector2.ZERO,origin+shift,0.0)
	pose_image(shoulders,parts.shoulders,cache_key+"/shoulders",Vector2.ZERO,origin+shift,0.0)
	if not bool(flags.get("legs",false)):
		var lower_key:="moving_lower/"+String(pose.original)
		if not sources.has(lower_key):
			var original:=FittedEquipmentLibrary.texture(pose.original).get_image()
			var split:=PlayerArmArt.split(original,pose.joints,false,FittedEquipmentLibrary.head_texture(pose).get_image())
			var lower_image:=PlayerArmArt.lower_body(split.lower,pose.joints)
			# Retain the original belt overlap; moving upper sections cannot
			# uncover a transparent band across the actual player's waist.
			var waist:=int(pose.joints.pelvis[1])
			for y in range(maxi(0,waist-2),mini(80,waist+1)):
				for x in range(80):
					if split.torso.get_pixel(x,y).a>0.0:
						lower_image.set_pixel(x,y,split.torso.get_pixel(x,y))
			sources[lower_key]=lower_image
		pose_image(lower,sources[lower_key],lower_key,Vector2.ZERO,origin,0.0)
	var direction:=String(context.direction)
	near_sides=[]
	if direction=="south":
		near_sides=["right","left"]
	elif direction in ["south-east","east","north-east"]:
		near_sides=["right"]
	elif direction in ["south-west","west","north-west"]:
		near_sides=["left"]
	if bool(motion.get("two_handed",false)):
		# Both bent forearms cross in front of the torso to reach the same
		# held item. Facing alone cannot put the supporting palm behind it.
		near_sides=["right","left"]
	for side: String in ["right","left"]:
		var arm: Dictionary=parts.arms[side]
		var shoulder:=FittedEquipmentLibrary.point(motion.joints["shoulder_"+side])
		var wrist: Vector2=motion[side+"_hand"]
		var upper_vector: Vector2=arm.elbow-arm.shoulder
		var lower_vector: Vector2=arm.wrist-arm.elbow
		var elbow:=solve_elbow(shoulder,wrist,upper_vector.length(),lower_vector.length(),side,direction)
		var upper_angle:=upper_vector.angle_to(elbow-shoulder)
		var lower_angle:=lower_vector.angle_to(wrist-elbow)
		pose_image(arm_sprites[side].upper,arm.upper,cache_key+"/"+side+"/upper",arm.shoulder,origin+shoulder,upper_angle)
		pose_image(arm_sprites[side].forearm,arm.forearm,cache_key+"/"+side+"/forearm",arm.elbow,origin+elbow,lower_angle)
		pose_image(arm_sprites[side].hand,arm.hand,cache_key+"/"+side+"/hand",arm.wrist,origin+wrist,lower_angle)
		hand_targets[side]=origin+wrist

func solve_elbow(shoulder: Vector2, wrist: Vector2, upper: float, forearm: float, side: String, direction: String) -> Vector2:
	upper=maxf(upper,3.0)
	forearm=maxf(forearm,3.0)
	var delta:=wrist-shoulder
	var distance:=clampf(delta.length(),absf(upper-forearm)+0.01,upper+forearm-0.01)
	var axis:=delta.normalized() if delta.length()>0.001 else Vector2.DOWN
	var cosine:=clampf((upper*upper+distance*distance-forearm*forearm)/(2.0*upper*distance),-1.0,1.0)
	var sign:=1.0 if side=="right" else -1.0
	if direction in ["north","north-east","north-west"]:
		sign=-sign
	return (shoulder+axis*upper*cosine+axis.orthogonal()*upper*sqrt(maxf(0,1-cosine*cosine))*sign).round()

func pose_image(sprite: Sprite2D, image: Image, key: String, pivot: Vector2, target: Vector2, angle: float) -> void:
	var bounds:=image.get_used_rect()
	if not bounds.has_area():
		sprite.visible=false
		return
	if not image_keys.has(key):
		var resource_key:="motion/"+key
		FittedEquipmentLibrary.textures[resource_key]=ImageTexture.create_from_image(image.get_region(bounds))
		image_keys[key]={"file":resource_key,"origin":Vector2(bounds.position)}
	var entry: Dictionary=image_keys[key]
	var fitted:=FittedEquipmentLibrary.native_part(entry.file,pivot-Vector2(entry.origin),Vector2.ZERO,snappedf(angle,PI/90.0),Vector2.ONE)
	sprite.texture=fitted.texture
	sprite.offset=fitted.origin
	sprite.position=target.round()
	sprite.scale=Vector2.ONE
	sprite.rotation=0.0
	sprite.visible=true
