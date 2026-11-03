extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("[Dark magic FAIL] ",label)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var visual: Node=(load("res://scenes/Effects/TitanMagicCast.tscn") as PackedScene).instantiate()
	root.add_child(visual)
	check(not visual.visible,"runtime cast starts hidden")
	check(visual.sample_at_seconds(1.2).frame==16,"runtime native frame follows shared tick clock")
	check(visual.visual.texture.get_size()==Vector2(256,256),"runtime uses user-selected native256px frames")
	check(visual.sample_at_seconds(2.4).phase=="complete" and not visual.visible,"runtime cast ends after recovery")
	for frame in [3,11,18]:
		visual.sample_at_seconds((float(frame)+0.5)*2.4/33.0)
		var at := Vector2i(125 if frame==18 else 123,62)
		var tongue: Color=visual.visual.texture.get_image().get_pixelv(at)
		check(tongue.a>0.99 and tongue.r>0.9 and tongue.g<0.2,"tongue stays opaque red in source frame"+str(frame))
	visual.sample_at_seconds(6.5*2.4/33.0)
	check(visual.visual.texture.get_image().get_pixel(122,174).a<0.01,"background beneath waist armor stays transparent")
	var remaining_matte := 0
	for frame in 33:
		visual.sample_at_seconds((float(frame)+0.5)*2.4/33.0)
		var image: Image=visual.visual.texture.get_image()
		for y in range(156,228):
			for x in range(100,156):
				if image.get_pixel(x,y) in [Color8(130,130,125),Color8(134,141,105)]: remaining_matte+=1
	check(remaining_matte==0,"no flat gray background colors remain beneath waist across all33 frames")
	for scene in ["TitanDarkBolt","TitanShadowEruption"]:
		var effect=load("res://scenes/Effects/"+scene+".tscn").instantiate()
		root.add_child(effect)
		effect.position=Vector2(112,208)
		check(not effect.visible,"effect starts hidden"+scene)
		effect.sample_at_seconds(0.5)
		check(effect.visible and effect.position==Vector2(112,208),"effect root remains at supplied position"+scene)
		effect.sample_at_seconds(1.8)
		check(effect.position==Vector2(112,208),"impact never retargets"+scene)
		effect.sample_at_seconds(3.0)
		check(not effect.visible,"effect ends"+scene)
		effect.sample_at_seconds(NAN)
		check(not effect.visible,"invalid clock hidden"+scene)
		effect.queue_free()
	visual.queue_free()
	print("[Dark magic] ",checks," checks; ",failures," failures")
	quit(0 if failures==0 else 1)
