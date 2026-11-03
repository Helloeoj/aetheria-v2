extends Node2D
## Runtime view of the17-bone native bake. Root is the Titan's existing feet.
const CHARGE_SHADER := preload("res://shaders/titan_magic_charge.gdshader")
static var frames: Array[Texture2D]=[]
var visual: Sprite2D
var lift := 0.0
var current_sample: Dictionary={"phase":"inactive","frame":0}

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	if frames.is_empty():
		for i in 120: frames.append(load("res://Assets/Characters/GolemTitanMagicCast/frames/%03d.png" % i))
	visual=Sprite2D.new()
	visual.offset=Vector2(0,-112)
	visual.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var charge := ShaderMaterial.new()
	charge.shader=CHARGE_SHADER
	charge.set_shader_parameter("canvas_height",288.0)
	charge.set_shader_parameter("source_y_offset",16.0)
	visual.material=charge
	add_child(visual)
	sample_at_seconds(-1.0)

func sample_at_seconds(time: float) -> Dictionary:
	var windup := GameTickConfig.TICK_DURATION_SECONDS*2.0
	var duration := windup*2.0
	visible=is_finite(time) and time>=0.0 and time<duration
	if not visible:
		lift=0.0
		current_sample={"phase":"complete" if is_finite(time) and time>=duration else "inactive","frame":0}
	else:
		var index := mini(119,floori(time/duration*120.0+0.0000001))
		visual.texture=frames[index]
		lift=smoothstep(0.0,windup,time) if time<=windup else 1.0-smoothstep(windup,duration,time)
		(visual.material as ShaderMaterial).set_shader_parameter("charge",lift)
		current_sample={"phase":"charging" if time<windup else "release","frame":index}
	queue_redraw()
	return current_sample.duplicate()

func _draw() -> void:
	if lift<=0.001: return
	# Same forward kinematics as the source bones, solely for attached VFX sockets.
	for right in [true,false]:
		var sign_ := 1.0 if right else -1.0
		var elbow := Vector2(52 if right else 204,122)
		var wrist := Vector2(43 if right else 212,170)
		var fist := Vector2(43 if right else 212,187)
		var a := deg_to_rad(sign_*160.0*lift)
		var b := deg_to_rad(-sign_*100.0*lift)
		var hand := (elbow+(wrist-elbow).rotated(a)+(fist-wrist).rotated(a+b)-Vector2(128,240)).round()
		draw_arc(hand,25,0,TAU,40,Color(0.61,0.18,1.0,0.7*lift),2,false)
		draw_arc(hand,29,0.3,TAU-0.4,36,Color(0.72,0.35,1.0,0.35*lift),1,false)
