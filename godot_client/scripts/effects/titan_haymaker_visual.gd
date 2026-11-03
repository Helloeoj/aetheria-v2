extends Node2D
## Physical punch presentation only. Root is the actor's existing foot anchor.
const DIRECTORY := "res://Assets/Characters/GolemTitanHaymaker/"
var visual: Sprite2D
var timeline: Dictionary
var frames: Array[Texture2D]=[]
var current_sample: Dictionary={"phase":"inactive","frame":0}

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	timeline=JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY+"manifest.json"))
	for i in int(timeline.frame_count): frames.append(load(DIRECTORY+"frames/%03d.png" % i))
	visual=Sprite2D.new()
	visual.offset=Vector2(float(timeline.native_canvas[0]),float(timeline.native_canvas[1]))*0.5-Vector2(float(timeline.foot_anchor[0]),float(timeline.foot_anchor[1]))
	visual.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(visual)
	sample_at_seconds(-1.0)

func sample_at_seconds(time: float) -> Dictionary:
	var duration := float(timeline.duration_ms)/1000.0
	visible=is_finite(time) and time>=0.0 and time<duration
	if not visible:
		current_sample={"phase":"complete" if is_finite(time) and time>=duration else "inactive","frame":0}
	else:
		var elapsed := time*1000.0
		var frame := 0
		for milliseconds in timeline.durations_ms:
			if elapsed<float(milliseconds): break
			elapsed-=float(milliseconds)
			frame+=1
		frame=mini(frame,frames.size()-1)
		visual.texture=frames[frame]
		var contact := float(timeline.contact_ms)/1000.0
		current_sample={"phase":"windup" if time<contact else "recovery","frame":frame}
	return current_sample.duplicate()
