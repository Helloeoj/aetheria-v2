class_name CharacterWeaponMotion
extends RefCounted
## Shared Bronze-authored motion, independent of item tier and texture palette.
const PATH := "res://data/bronze_weapon_animations.json"
const TWO_HANDS := ["warmaul","bow","magic-staff","pickaxe"]
static var catalog: Dictionary = {}

static func enabled() -> bool:
	return true

static func family_for_name(item_name: String) -> String:
	var name := item_name.to_lower().replace(" ","-")
	for family: String in ["magic-staff","magic-wand","shortsword","longsword","crossbow","warmaul","pickaxe","dagger","mace","bow"]:
		if name.ends_with(family):
			return family
	return ""

static func definition(family: String) -> Dictionary:
	if catalog.is_empty():
		catalog = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return catalog.get("families",{}).get(family,{})

static func install_attacks(source: SpriteFrames, family: String) -> SpriteFrames:
	var clip := definition(family)
	if clip.is_empty() or not enabled():
		return source
	# The skin cache is shared. Each equipped actor gets its own attack clock.
	var result := source.duplicate() as SpriteFrames
	for direction: String in CharacterSpriteLibrary.DIRECTIONS:
		var idle := CharacterSpriteLibrary.animation_name("idle",direction)
		var attack := CharacterSpriteLibrary.animation_name("attack",direction)
		if result.has_animation(attack):
			result.remove_animation(attack)
		result.add_animation(attack)
		result.set_animation_loop(attack,false)
		result.set_animation_speed(attack,8.0/float(clip.duration))
		for _frame in range(8):
			result.add_frame(attack,source.get_frame_texture(idle,0))
	return result

static func sample(context: Dictionary, profile: Dictionary, shield: bool) -> Dictionary:
	var family := String(profile.get("family",""))
	var clip := definition(family)
	if clip.is_empty() or not enabled():
		return {}
	var attack := String(context.action)=="attack"
	var two := family in TWO_HANDS or (family=="crossbow" and not shield)
	var result := {"active":attack or two,"family":family,"template":"bronze/"+family,"two_handed":two,"is_attack":attack,"frame":int(context.frame),"torso_shift":Vector2.ZERO,"rotation":float(profile.get("carry_rotation",0.0))}
	if not result.active:
		return result
	var joints := FittedEquipmentLibrary.source_joints(context)
	var rest:=FittedEquipmentLibrary.motion_rest_joints(context)
	var upper_shift:=FittedEquipmentLibrary.motion_upper_shift(context)
	for name: String in ["chest","neck","head","back","shoulder_right","shoulder_left","elbow_right","elbow_left","hand_right","hand_left"]:
		var location:=FittedEquipmentLibrary.point(rest.get(name,rest.chest))+upper_shift
		joints[name]=[location.x,location.y]
	result["upper_shift"]=upper_shift
	result["head_offset"]=FittedEquipmentLibrary.motion_head_offset(context)+upper_shift
	var direction := String(context.direction)
	var index := CharacterSpriteLibrary.DIRECTIONS.find(direction)
	var raw_forward := Vector2.DOWN.rotated(-index*PI/4.0)
	var forward := Vector2(raw_forward.x,raw_forward.y*0.45)
	var lateral := Vector2(raw_forward.y,-raw_forward.x*0.5)
	var grip_axis := (lateral+forward*0.35).normalized()
	if family=="magic-staff" and direction in ["east","west"]:
		grip_axis=forward.normalized()
	if family=="warmaul" and not attack:
		# Carry the heavy head outside the body at waist height. The old
		# lateral axis pointed it into the face in profile and into the feet.
		var outward: float=signf(raw_forward.x) if absf(raw_forward.x)>0.1 else (-1.0 if direction=="north" else 1.0)
		grip_axis=Vector2(outward,-0.2).normalized()
	var chest := FittedEquipmentLibrary.point(joints.chest)
	var primary := FittedEquipmentLibrary.point(joints.hand_right)
	var left := FittedEquipmentLibrary.point(joints.hand_left)
	var pivot: Vector2 = profile.get("pivot",Vector2.ZERO)
	var support: Vector2 = profile.get("support_grip",pivot+Vector2(0,-9))
	if family=="warmaul" and not attack:
		support=pivot+Vector2(0,-13) # Shaft just below the head, with room for both hands.
	result["support_grip"]=support
	var support_delta := (support-pivot)*float(profile.get("source_scale",1.0))
	var angle := float(profile.get("carry_rotation",0.0))
	if attack and family=="dagger":
		angle=Vector2.UP.angle_to(forward)
	if family=="crossbow":
		primary=chest-forward.normalized()*4.0+Vector2(0,7)
		angle=support_delta.angle_to(forward)
	var control: Array = clip["keys"][clampi(int(context.frame),0,7)] if attack else [0,0,0,0]
	var sign := 1.0 if grip_axis.x>=0.0 else -1.0
	if two:
		if family=="bow":
			primary = chest+forward.normalized()*9.0+lateral*3.0+Vector2(0,2)
			var draw_axis:=FittedEquipmentLibrary.point(joints.shoulder_right)-FittedEquipmentLibrary.point(joints.shoulder_left)
			if direction in ["east","west"]:
				draw_axis=-forward
			angle=support_delta.angle_to(draw_axis)
		elif family!="crossbow":
			var carry_maul:=family=="warmaul" and not attack
			primary = chest-grip_axis*(6.5 if carry_maul else 4.0)+Vector2(0,8 if carry_maul else 6)
			angle = support_delta.angle_to(grip_axis)
	if attack:
		primary += forward*float(control[2])+Vector2(0,float(control[1]))
		angle += deg_to_rad(float(control[0]))*sign
		result.torso_shift = (forward*float(control[3])).round()
		primary += result.torso_shift
		result.head_offset+=result.torso_shift
	for joint: String in ["chest","neck","head","back","shoulder_right","shoulder_left","hand_right","hand_left","elbow_right","elbow_left"]:
		var point := FittedEquipmentLibrary.point(joints.get(joint,joints.chest))+Vector2(result.torso_shift)
		joints[joint]=[point.x,point.y]
	var secondary := primary+support_delta.rotated(angle)
	if family=="bow" and attack:
		var pull: float = [0.0,1.0,3.0,5.0,5.0,0.0,0.0,0.0][clampi(int(context.frame),0,7)]
		secondary += support_delta.rotated(angle).normalized()*pull
		result["bow_pull"] = pull
	# Fit the rigid two-grip item inside BOTH actual source-arm annuli.
	# Hidden arms may borrow another contour, so bare metadata alone cannot
	# supply the lengths used by the renderer.
	var parts:=PlayerArticulatedBody.source_parts(context)
	if two:
		var delta:=secondary-primary
		var primary_side:="left" if family=="bow" else "right"
		var secondary_side:="right" if family=="bow" else "left"
		primary=fit_grips(primary,delta,joints,parts.arms,primary_side,secondary_side)
		secondary=primary+delta
		left=primary if family=="bow" else secondary
	var right := secondary if family=="bow" else primary
	if not two:
		left = FittedEquipmentLibrary.point(joints.hand_left)
		var shoulder:=FittedEquipmentLibrary.point(joints.shoulder_right)
		var limits:=arm_limits(parts.arms.right)
		var delta:=primary-shoulder
		if delta.length()<0.001:
			delta=Vector2.DOWN
		primary=shoulder+delta.normalized()*clampf(delta.length(),limits.x,limits.y)
		right=primary
	# Keep the physical support point exact after snapping the primary grip.
	var snap := primary.round()-primary
	primary+=snap
	secondary+=snap
	right+=snap
	if two:
		left+=snap
	result.merge({"primary":primary,"secondary":secondary,"right_hand":right,"left_hand":left,"rotation":angle,"joints":joints,"weapon_behind_head":attack and int(context.frame) in [1,2]},true)
	result.joints.hand_right=[result.right_hand.x,result.right_hand.y]
	result.joints.hand_left=[result.left_hand.x,result.left_hand.y]
	return result

static func arm_limits(arm: Dictionary) -> Vector2:
	var upper:=maxf(3.0,Vector2(arm.elbow).distance_to(arm.shoulder))
	var lower:=maxf(3.0,Vector2(arm.wrist).distance_to(arm.elbow))
	return Vector2(absf(upper-lower)+0.1,upper+lower-0.1)

static func fit_grips(desired: Vector2, delta: Vector2, joints: Dictionary, arms: Dictionary, first_side: String, second_side: String) -> Vector2:
	var first:=FittedEquipmentLibrary.point(joints["shoulder_"+first_side])
	var second:=FittedEquipmentLibrary.point(joints["shoulder_"+second_side])-delta
	var a:=arm_limits(arms[first_side])
	var b:=arm_limits(arms[second_side])
	var candidates: Array[Vector2]=[desired]
	for entry: Array in [[first,a],[second,b]]:
		var center: Vector2=entry[0]
		var axis: Vector2=(desired-center).normalized() if desired.distance_to(center)>0.001 else Vector2.DOWN
		for radius: float in [entry[1].x,entry[1].y]:
			candidates.append(center+axis*radius)
	var separation:=second-first
	var distance:=separation.length()
	# Include the balanced point even when conservative reach margins or
	# native-pixel snapping leave the two outer circles just short of contact.
	candidates.append(first+separation*(a.y/(a.y+b.y)))
	if distance>0.001:
		var axis:=separation/distance
		for ar: float in [a.x,a.y]:
			for br: float in [b.x,b.y]:
				if distance>ar+br or distance<absf(ar-br):
					continue
				var along:=(ar*ar-br*br+distance*distance)/(2.0*distance)
				var height:=sqrt(maxf(0.0,ar*ar-along*along))
				candidates.append(first+axis*along+axis.orthogonal()*height)
				candidates.append(first+axis*along-axis.orthogonal()*height)
	var best:=desired
	var best_score:=INF
	for candidate: Vector2 in candidates:
		for y in range(-1,2):
			for x in range(-1,2):
				var point:=candidate.round()+Vector2(x,y)
				var da:=point.distance_to(first)
				var db:=point.distance_to(second)
				var ea:=maxf(a.x-da,0)+maxf(da-a.y,0)
				var eb:=maxf(b.x-db,0)+maxf(db-b.y,0)
				var excess:=ea*ea+eb*eb
				var score:=excess*10000.0+point.distance_squared_to(desired)
				if score<best_score:
					best=point
					best_score=score
	return best
