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
