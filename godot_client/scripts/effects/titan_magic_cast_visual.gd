extends Node2D
## Runtime view of the user-selected33-frame raised-fist roar. Root is the Titan's existing feet.
const CHARGE_SHADER := preload("res://shaders/titan_magic_charge.gdshader")
static var frames: Array[Texture2D]=[]
var visual: Sprite2D
var lift := 0.0
var current_sample: Dictionary={"phase":"inactive","frame":0}

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	if frames.is_empty():
		for i in 33: frames.append(_without_floor_matte(load("res://Assets/Characters/GolemTitanMagicCast/frames/%03d.png" % i)))
	visual=Sprite2D.new()
	visual.offset=Vector2(0,-112)
	visual.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var charge := ShaderMaterial.new()
	charge.shader=CHARGE_SHADER
	charge.set_shader_parameter("canvas_height",256.0)
	charge.set_shader_parameter("source_y_offset",0.0)
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
		var index := mini(32,floori(time/duration*33.0+0.0000001))
		visual.texture=frames[index]
		lift=smoothstep(0.0,windup,time) if time<=windup else 1.0-smoothstep(windup,duration,time)
		(visual.material as ShaderMaterial).set_shader_parameter("charge",lift)
		current_sample={"phase":"charging" if time<windup else "release","frame":index}
	queue_redraw()
	return current_sample.duplicate()

func _without_floor_matte(texture: Texture2D) -> Texture2D:
	# Some source frames contain a single flat brown ground oval. Key only its
	# large connected component; similarly colored stone shading stays intact.
	var image := texture.get_image()
	var seen := PackedByteArray()
	seen.resize(256*256)
	var matte := Color8(69,59,51)
	for y in range(190,256):
		for x in 256:
			var start := y*256+x
			if seen[start] or image.get_pixel(x,y)!=matte: continue
			var pending: Array[int]=[start]
			var component: Array[int]=[]
			seen[start]=1
			while not pending.is_empty():
				var cell: int=pending.pop_back()
				component.append(cell)
				var at := Vector2i(cell%256,cell/256)
				for step: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
					var next := at+step
					if next.x<0 or next.x>=256 or next.y<190 or next.y>=256: continue
					var index := next.y*256+next.x
					if not seen[index] and image.get_pixelv(next)==matte:
						seen[index]=1
						pending.append(index)
			if component.size()>512:
				for cell: int in component: image.set_pixel(cell%256,cell/256,Color.TRANSPARENT)
	return ImageTexture.create_from_image(image)
