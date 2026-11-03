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
	check(visual.sample_at_seconds(1.2).frame==60,"runtime native frame follows shared tick clock")
	check(visual.visual.texture.get_size()==Vector2(336,288),"runtime uses clean native padded frames")
	check(visual.sample_at_seconds(2.4).phase=="complete" and not visual.visible,"runtime cast ends after recovery")
	var rig=load("res://scripts/dev_tools/golem_titan_casting_skeleton.gd").new()
	rig.glow_enabled=true
	root.add_child(rig)
	check(rig.bones.size()==17,"casting has actual17-bone hierarchy")
	check(rig.skin.material is ShaderMaterial,"casting scene installs purple charge material")
	for time in [0.0,0.3,0.6,0.9,1.2,1.8,2.4]:
		rig.sample_at_seconds(time)
		check((rig.bones.body as Bone2D).transform==Transform2D.IDENTITY,"root/legs remain planted at"+str(time))
		for side in ["right","left"]:
			var bone: Bone2D=rig.bones["fist_"+side]
			var delta := Vector2(20,15)
			check(absf(bone.global_transform.basis_xform(delta).length()-delta.length())<0.0001,"whole fist/thumb volume preserved"+side+str(time))
	rig.sample_at_seconds(1.2)
	check(is_equal_approx(rig.lift,1.0),"raise/roar peaks at two combat ticks")
	check((rig.bones.jaw as Bone2D).position.y>(rig.bones.jaw as Bone2D).rest.origin.y,"jaw opens on its own bone")
	rig.sample_at_seconds(2.4)
	check(is_zero_approx(rig.lift),"neutral after recovery")
	for scene in ["TitanDarkBolt","TitanShadowEruption"]:
		var effect=load("res://scenes/Effects/"+scene+".tscn").instantiate()
		root.add_child(effect)
		effect.position=Vector2(112,208)
		check(not effect.visible,"effect starts hidden"+scene)
		effect.sample_at_seconds(0.5)
		check(effect.visible and effect.position==Vector2(112,208),"warning remains on captured tile"+scene)
		effect.sample_at_seconds(1.8)
		check(effect.position==Vector2(112,208),"impact never retargets"+scene)
		effect.sample_at_seconds(3.0)
		check(not effect.visible,"effect ends"+scene)
		effect.sample_at_seconds(NAN)
		check(not effect.visible,"invalid clock hidden"+scene)
		effect.queue_free()
	visual.queue_free()
	rig.queue_free()
	print("[Dark magic] ",checks," checks; ",failures," failures")
	quit(0 if failures==0 else 1)
