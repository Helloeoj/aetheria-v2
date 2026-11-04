extends SceneTree
var failures: Array[String]=[]
var checks:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures.append(label)
func run() -> void:
	var actor:=ActorSprite.new().configure(Vector2(32,32),Color.BLUE,"style_motion")
	root.add_child(actor)
	actor.set_skin("peasant")
	actor.set_process(false)
	var bronze: Dictionary={}
	for tier: String in ["Bronze","Iron","Steel"]:
		for family: String in ["longsword","warmaul"]:
			actor.set_equipment({"weapon":{"name":tier+" "+family.capitalize()},"chest":{"name":tier+" Platebody"},"legs":{"name":tier+" Platelegs"}})
			var signatures: Array[String]=[]
			for option: String in CharacterWeaponMotion.definition(family).styles:
				var trace: Array=[]
				for direction: String in CharacterSpriteLibrary.DIRECTIONS:
					actor.cancel_action()
					actor.play_attack(Vector2.DOWN.rotated(-CharacterSpriteLibrary.DIRECTIONS.find(direction)*PI/4),option)
					actor.animated_sprite.pause()
					check(not actor._fallback_attack,family+" uses real attack clock")
					for frame in range(8):
						actor.animated_sprite.frame=frame
						actor.attachment_rig.sync_pose()
						var pose:=actor.attachment_rig.get_weapon_motion()
						check(pose.combat_option==option,"resolved selected option")
						trace.append([direction,frame,pose.primary,pose.left_hand,pose.rotation])
						var context:=actor.attachment_rig._fitted_context()
						var parts:=PlayerArticulatedBody.source_parts(context)
						for side: String in ["right","left"]:
							var arm: Dictionary=parts.arms[side]
							var shoulder:=FittedEquipmentLibrary.point(pose.joints["shoulder_"+side])
							var wrist: Vector2=pose[side+"_hand"]
							var upper: float=arm.shoulder.distance_to(arm.elbow)
							var lower: float=arm.elbow.distance_to(arm.wrist)
							check(shoulder.distance_to(wrist)<=upper+lower+1.5,option+" reachable "+direction+" "+side+" "+str(frame))
				var signature:=str(trace)
				check(not signature in signatures,family+" distinct style "+option)
				signatures.append(signature)
				var key:=family+"/"+option
				if tier=="Bronze": bronze[key]=signature
				else: check(bronze[key]==signature,tier+" exactly reuses Bronze "+key)
	check(CharacterWeaponMotion.style_for("longsword","stab")=="lunge","existing Stab input selects Lunge")
	actor.free()
	print(JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
