extends Node2D
## Externally sampled spell visuals. AoE warns its tile; single bolt has no ground marker.
const TICK := GameTickConfig.TICK_DURATION_SECONDS
const WARNINGS := [preload("res://Assets/Effects/TitanDarkMagic/warning-0.png"),preload("res://Assets/Effects/TitanDarkMagic/warning-1.png"),preload("res://Assets/Effects/TitanDarkMagic/warning-2.png"),preload("res://Assets/Effects/TitanDarkMagic/warning-3.png")]
const ORB := preload("res://Assets/Effects/TitanDarkMagic/void-orb.png")
const ERUPTION := preload("res://Assets/Effects/TitanDarkMagic/void-eruption.png")
@export_enum("single","aoe") var mode := "aoe"
var age := -1.0
var launch_point := Vector2.ZERO

func _init() -> void:
	visible=false
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST

func sample_at_seconds(seconds: float) -> void:
	age=seconds
	visible=is_finite(age) and age>=0.0 and age<4.2*TICK
	queue_redraw()

func _draw() -> void:
	if age<0.0 or not is_finite(age): return
	var release := 2.0*TICK
	var impact := release+TICK if mode=="single" else release
	if mode=="aoe" and age<impact:
		var warning := mini(3,int(clampf(age/release,0,0.999)*4.0))
		draw_texture(WARNINGS[warning],Vector2(-24,-52))
	if mode=="single":
		if age>=release and age<impact:
			var progress := clampf((age-release)/TICK,0.0,1.0)
			var point := launch_point.lerp(Vector2(0,-10),progress)
			# Native sprite and a short continuous spell trail; endpoint is locked.
			for i in range(4,0,-1):
				var tail := launch_point.lerp(Vector2(0,-10),maxf(0.0,progress-float(i)*0.045))
				draw_circle(tail.round(),float(6-i),Color(0.43,0.10,0.70,0.12))
			draw_texture(ORB,point.round()-Vector2(24,24),Color(0.75,0.70,1.0))
		elif age>=impact and age<impact+TICK:
			var p := (age-impact)/TICK
			var radius := 3.0+11.0*sin(p*PI)
			draw_circle(Vector2(0,-2),radius,Color(0.12,0.035,0.19,1.0-p))
			draw_arc(Vector2(0,-2),radius,0,TAU,32,Color(0.69,0.26,1.0,1.0-p),2,false)
		return
	if age<release or age>=release+TICK*2.0: return
	var phase := (age-release)/TICK
	var energy := smoothstep(0.0,1.0,phase) if phase<1.0 else 1.0-smoothstep(1.0,2.0,phase)
	# The spectral column comes through a floor occlusion plane. Per-row flow
	# animates its wisps without scaling or stretching native pixels.
	var shift := roundi((1.0-energy)*68.0)
	for y in 72:
		var local_y := y-70+shift
		if local_y>0: continue
		var flow := roundi(sin(float(y)*0.21+age*12.0)*energy)
		draw_texture_rect_region(ERUPTION,Rect2(Vector2(-24+flow,local_y),Vector2(48,1)),Rect2(0,y,48,1),Color(0.83,0.75,1.0,0.6+energy*0.4))
