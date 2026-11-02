extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void:
	run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("[Player motion FAIL] ",message)
func run() -> void:
	var actor := ActorSprite.new().configure(Vector2(32,32),Color.BLUE,"motion_regression")
	root.add_child(actor)
	actor.set_skin("peasant")
	actor.set_process(false)
	actor.set_equipment({"weapon":{"name":"Bronze Warmaul"},"chest":{"name":"Bronze Platebody"},"legs":{"name":"Bronze Platelegs"}})
	check(actor.animated_sprite.sprite_frames.has_animation(&"attack_south"),"equipped Bronze Warmaul has a real attack clip")
	check(actor.attachment_rig.has_method("get_weapon_motion"),"rig exposes one resolved weapon/body pose")
	if actor.attachment_rig.has_method("get_weapon_motion"):
		var pose: Dictionary = actor.attachment_rig.get_weapon_motion()
		check(bool(pose.get("active",false)) and bool(pose.get("two_handed",false)),"warmaul ready pose uses both arms")
		check(Vector2(pose.right_hand).distance_to(Vector2(pose.left_hand)) >= 5.0,"two hands have separated visible grips")
		check(Vector2(pose.secondary).distance_to(Vector2(pose.left_hand)) < 0.01,"support hand follows actual shaft grip")
		var weapon: Node=actor.attachment_rig.get_equipped_visual("weapon")
		var profile: Dictionary=weapon.get_weapon_profile("south")
		var support: Vector2=Vector2(pose.primary)+(Vector2(profile.support_grip)-Vector2(profile.pivot)).rotated(float(pose.rotation))*float(profile.source_scale)
		check(support.distance_to(Vector2(pose.left_hand))<0.01,"rendered weapon rotation puts its real second grip in the support hand")
		actor.play_attack(Vector2.DOWN)
		actor.animated_sprite.pause()
		var count := actor.animated_sprite.sprite_frames.get_frame_count(&"attack_south")
		check(count >= 6 and not actor._fallback_attack,"attack plays authored family frames rather than idle lunge")
		var first: Vector2 = actor.attachment_rig.get_weapon_motion().primary
		actor.animated_sprite.frame = 3
		actor.attachment_rig.sync_pose()
		check(first.distance_to(actor.attachment_rig.get_weapon_motion().primary)>1.0,"attack changes the hand/body pose")
	# Every tier must resolve the same Bronze family clock and physical grips.
	var source_frames:=CharacterSpriteLibrary.get_frames("peasant")
	var source_names:=source_frames.get_animation_names()
	for tier: String in ["Bronze","Iron","Steel"]:
		for family: String in ["dagger","shortsword","longsword","mace","warmaul","bow","crossbow","magic-staff","magic-wand","pickaxe"]:
			var name:=tier+" "+family.replace("-"," ").capitalize()
			actor.set_equipment({"weapon":{"name":name},"chest":{"name":tier+" Platebody"},"legs":{"name":tier+" Platelegs"},"cape":{"name":tier+" Cape"}})
			for direction: String in CharacterSpriteLibrary.DIRECTIONS:
				var clip:=CharacterSpriteLibrary.animation_name("attack",direction)
				actor.animated_sprite.play(clip)
				actor.animated_sprite.pause()
				check(actor.animated_sprite.sprite_frames.get_frame_count(clip)==8 and not actor.animated_sprite.sprite_frames.get_animation_loop(clip),name+" attack clock "+direction)
				for frame in range(8):
					actor.animated_sprite.frame=frame
					actor.attachment_rig.sync_pose()
					var motion:=actor.attachment_rig.get_weapon_motion()
					check(motion.get("template","")=="bronze/"+family,name+" shared Bronze template")
					check(bool(motion.get("active",false)),name+" active posed body")
					var torso:=actor.animated_sprite.get_node("ArmorMotionTorso") as Sprite2D
					check(torso.visible and torso.texture.get_image().get_used_rect().has_area(),name+" complete torso")
					var head:=actor.animated_sprite.get_node("ArmorHeadForeground") as Sprite2D
					check(head.visible and actor.attachment_rig.get_socket("back").get_index()<head.get_index(),name+" cape below complete head")
					var held:=actor.attachment_rig.get_equipped_visual("weapon")
					var profile: Dictionary=held.get_weapon_profile(direction)
					var primary: Vector2=motion.primary
					var grip:=Vector2(motion.left_hand) if family=="bow" else Vector2(motion.right_hand)
					check(primary.distance_to(grip)<0.01,name+" primary palm remains on held item")
					if bool(motion.two_handed) and family!="bow":
						var support:=primary+(Vector2(profile.support_grip)-Vector2(profile.pivot)).rotated(motion.rotation)*float(profile.source_scale)
						check(support.distance_to(motion.left_hand)<0.01,name+" supporting palm remains on shaft")
					for side: String in ["right","left"]:
						for part: String in ["Upper","Forearm","Hand"]:
							var limb:=actor.animated_sprite.get_node("ArmorMotion"+part+"_"+side) as Sprite2D
							check(limb.visible and limb.texture.get_image().get_used_rect().has_area(),name+" supplied "+side+" "+part)
							check(limb.scale==Vector2.ONE and is_zero_approx(limb.rotation),name+" native rigid "+side+" "+part)
			actor._process(2.0)
			actor.cancel_action()
			actor.attachment_rig.sync_pose()
			check(not String(actor.animated_sprite.animation).begins_with("attack_"),name+" returns to locomotion")
	check(source_frames.get_animation_names()==source_names,"equipping leaves shared source animation cache unchanged")
	actor.set_equipment({})
	check(not actor.animated_sprite.sprite_frames.has_animation(&"attack_south"),"unequipping removes actor-local weapon clock")
	check(actor.animated_sprite.self_modulate.a==1.0,"unequipping restores complete original body")
	actor.free()
	print("[Player motion checks] ",checks)
	print("[Player motion] ",failures," failures")
	quit(0 if failures==0 else 1)
