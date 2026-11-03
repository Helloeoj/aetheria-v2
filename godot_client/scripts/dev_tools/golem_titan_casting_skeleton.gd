extends Node2D
## Dedicated casting skeleton: unchanged source, rigid stone surfaces,
## complete fists, explicit elbows/wrists and jaw; anchored legs/blue bindings.
const SOURCE := "res://Assets/Characters/GolemTitanApproved/idle/00.png"
const RIGHT_HAND := [Vector2(18,177),Vector2(31,173),Vector2(35,169),Vector2(47,169),Vector2(56,163),Vector2(63,162),Vector2(69,166),Vector2(72,173),Vector2(69,178),Vector2(68,180),Vector2(67,188),Vector2(61,195),Vector2(56,201),Vector2(49,205),Vector2(33,206),Vector2(23,202),Vector2(18,197),Vector2(15,188),Vector2(16,182)]
const LEFT_HAND := [Vector2(187,169),Vector2(195,169),Vector2(202,173),Vector2(210,174),Vector2(218,175),Vector2(227,180),Vector2(234,184),Vector2(239,189),Vector2(240,196),Vector2(237,202),Vector2(230,207),Vector2(223,211),Vector2(213,210),Vector2(206,208),Vector2(198,205),Vector2(193,201),Vector2(189,197),Vector2(184,194),Vector2(182,190),Vector2(181,183),Vector2(181,179),Vector2(184,174)]
const LEFT_ARM := [Vector2(20,116),Vector2(37,119),Vector2(46,128),Vector2(64,127),Vector2(68,134),Vector2(71,144),Vector2(67,153),Vector2(72,164),Vector2(76,182),Vector2(69,199),Vector2(52,208),Vector2(27,208),Vector2(14,196),Vector2(10,183),Vector2(11,168),Vector2(9,151),Vector2(8,143),Vector2(11,130),Vector2(13,121)]
const HEAD := [Vector2(128,20),Vector2(149,37),Vector2(160,57),Vector2(156,84),Vector2(146,99),Vector2(128,104),Vector2(110,100),Vector2(100,85),Vector2(96,57),Vector2(108,38)]
const JAW := [Vector2(117,91),Vector2(139,91),Vector2(142,98),Vector2(135,103),Vector2(122,102),Vector2(114,97)]
var skeleton: Skeleton2D
var bones: Dictionary={}
var skin: Polygon2D
var lift := 0.0
@export var glow_enabled := false
var draw_joint_surfaces := true
var _built := false

func _ready() -> void:
	_build()
	sample_at_seconds(0.0)

func _bone(name_: String,parent_: String,point: Vector2) -> void:
	var bone := Bone2D.new()
	bone.name=name_
	bone.set_autocalculate_length_and_angle(false)
	bone.length=12
	if parent_.is_empty():
		skeleton.add_child(bone)
		bone.position=point
	else:
		var parent: Bone2D=bones[parent_]
		parent.add_child(bone)
		bone.position=point-parent.global_position+global_position
	bone.rest=bone.transform
	bones[name_]=bone

func _inside(point: Vector2,polygon: Array) -> bool:
	return Geometry2D.is_point_in_polygon(point,PackedVector2Array(polygon))

func _hand(point: Vector2,polygon: Array) -> bool:
	if _inside(point,polygon): return true
	for i in polygon.size():
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point,polygon[i],polygon[(i+1)%polygon.size()]))<=1.0:
			return true
	return false

func _owner(point: Vector2,color: Color) -> String:
	var cyan := color.g>color.r+0.078 and color.b>color.r+0.078
	var ice := color.g>0.66 and color.b>0.72 and color.b>=color.r*0.98
	var binding_zone := point.y>=195.0 or (point.x>=55.0 and point.x<=90.0) or (point.x>=170.0 and point.x<=208.0)
	if point.y>=169.0 and binding_zone and (cyan or ice): return "body"
	if _hand(point,RIGHT_HAND): return "fist_right"
	if _hand(point,LEFT_HAND): return "fist_left"
	if point.x<80.0 and _hand(point,LEFT_ARM): return "forearm_right"
	if point.x>176.0 and _hand(Vector2(256.0-point.x,point.y),LEFT_ARM): return "forearm_left"
	if _inside(point,JAW): return "jaw"
	if _hand(point,HEAD): return "head"
	return "body"

func _build() -> void:
	if _built: return
	_built=true
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	skeleton=Skeleton2D.new()
	add_child(skeleton)
	_bone("body","",Vector2.ZERO)
	_bone("spine","body",Vector2(128,125))
	_bone("neck","spine",Vector2(128,102))
	_bone("head","neck",Vector2(128,80))
	_bone("jaw","head",Vector2(128,94))
	for side: String in ["right","left"]:
		var right := side=="right"
		_bone("shoulder_"+side,"spine",Vector2(65 if right else 191,100))
		_bone("upper_arm_"+side,"shoulder_"+side,Vector2(56 if right else 200,113))
		_bone("elbow_"+side,"upper_arm_"+side,Vector2(52 if right else 204,122))
		_bone("forearm_"+side,"elbow_"+side,Vector2(52 if right else 204,122))
		_bone("wrist_"+side,"forearm_"+side,Vector2(43 if right else 212,170))
		_bone("fist_"+side,"wrist_"+side,Vector2(43 if right else 212,187))
	var source_texture := load(SOURCE) as Texture2D
	var source := source_texture.get_image()
	source.convert(Image.FORMAT_RGBA8)
	skin=Polygon2D.new()
	skin.texture=source_texture
	skin.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(skin)
	skin.skeleton=skin.get_path_to(skeleton)
	if glow_enabled:
		var charge_material := ShaderMaterial.new()
		charge_material.shader=load("res://shaders/titan_magic_charge.gdshader")
		skin.material=charge_material
	var vertices := PackedVector2Array()
	var triangles: Array[PackedInt32Array]=[]
	var indexes: Dictionary={}
	var vertex_owners: Array[String]=[]
	for y in 256:
		for x in 256:
			var color := source.get_pixel(x,y)
			if color.a<0.01: continue
			var owner := _owner(Vector2(x+0.5,y+0.5),color)
			var face := PackedInt32Array()
			for delta: Vector2 in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
				var point := Vector2(x,y)+delta
				var key := owner+":"+str(point)
				if not indexes.has(key):
					indexes[key]=vertices.size()
					vertices.append(point)
					vertex_owners.append(owner)
				face.append(indexes[key])
			triangles.append(PackedInt32Array([face[0],face[1],face[2]]))
			triangles.append(PackedInt32Array([face[0],face[2],face[3]]))
	skin.polygon=vertices
	skin.uv=vertices
	skin.polygons=triangles
	for name_: String in bones:
		var weights := PackedFloat32Array()
		weights.resize(vertices.size())
		for index in vertices.size():
			if vertex_owners[index]==name_: weights[index]=1.0
		skin.add_bone(skeleton.get_path_to(bones[name_]),weights)

func sample_at_seconds(seconds: float) -> void:
	_build()
	for bone: Bone2D in bones.values(): bone.apply_rest()
	var windup := GameTickConfig.TICK_DURATION_SECONDS*2.0
	var t := clampf(seconds,0.0,windup*2.0)
	lift=smoothstep(0.0,windup,t) if t<=windup else 1.0-smoothstep(windup,windup*2.0,t)
	(bones.head as Bone2D).position.y-=6.0*lift
	(bones.jaw as Bone2D).position.y+=8.0*lift
	for side: String in ["right","left"]:
		var sign_ := 1.0 if side=="right" else -1.0
		(bones["forearm_"+side] as Bone2D).rotation=deg_to_rad(sign_*160.0*lift)
		(bones["wrist_"+side] as Bone2D).rotation=deg_to_rad(-sign_*100.0*lift)
	if skin.material is ShaderMaterial:
		(skin.material as ShaderMaterial).set_shader_parameter("charge",lift)
	queue_redraw()

func _draw() -> void:
	if not _built or lift<=0.001: return
	if draw_joint_surfaces:
		for side: String in ["right","left"]:
			draw_circle(to_local((bones["elbow_"+side] as Bone2D).global_position),8,Color("24211d"))
			draw_circle(to_local((bones["wrist_"+side] as Bone2D).global_position),6,Color("38312a"))
		var mouth := to_local((bones.head as Bone2D).global_position)+Vector2(0,16)
		var cavity := PackedVector2Array([mouth+Vector2(-14,-7),mouth+Vector2(-8,-11),mouth+Vector2(8,-11),mouth+Vector2(14,-7),mouth+Vector2(15,3),mouth+Vector2(8,10),mouth+Vector2(-8,10),mouth+Vector2(-15,3)])
		draw_colored_polygon(cavity,Color("100b17"))
	if glow_enabled:
		for side: String in ["right","left"]:
			var hand := to_local((bones["fist_"+side] as Bone2D).global_position)
			draw_arc(hand,25,0,TAU,40,Color(0.61,0.18,1.0,0.7*lift),2,false)
			draw_arc(hand,29,0.3,TAU-0.4,36,Color(0.72,0.35,1.0,0.35*lift),1,false)
