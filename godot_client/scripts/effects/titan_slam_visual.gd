extends Node2D
var visual: Sprite2D
var frames: Array[Texture2D] = []
var durations: Array = []
func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/golem_titan_approved_animations.json"))
	durations = data.animations.attack.durations_ms
	for i in 18: frames.append(load("res://Assets/Characters/GolemTitanApproved/attack/%02d.png" % i))
	visual = Sprite2D.new()
	visual.offset = Vector2(0, -112)
	add_child(visual)
	sample_at_seconds(-1)
func sample_at_seconds(age: float) -> void:
	visible = age >= 0.0 and age < 2.4
	if not visible: return
	# Preserve the approved motion, aligning its contact to the shared tick.
	var source := age / 1.2 * 1.02 if age <= 1.2 else 1.02 + (age - 1.2) / 1.2 * 1.29
	var frame := 0
	for duration: Variant in durations:
		if source * 1000.0 < float(duration): break
		source -= float(duration) / 1000.0
		frame += 1
	visual.texture = frames[mini(frame, 17)]
