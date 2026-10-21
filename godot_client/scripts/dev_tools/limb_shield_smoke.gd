extends SceneTree
## Regression for disappearing anatomy, severed armor segments and grip drift.
var checks := 0
var failures: Array[String] = []
func _initialize() -> void:
	_run.call_deferred()
func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("[Limb/shield regression] ", label)
func _run() -> void:
	await process_frame
	var actor := ActorSprite.new().configure(Vector2(32,32), Color.BLUE, "limb_regression")
	root.add_child(actor)
	actor.set_process(false)
	actor.set_skin("peasant")
	var poses := 0
	for material: String in ["Bronze", "Iron"]:
		actor.set_equipment({"chest":{"name":material + " Platebody"},"legs":{"name":material + " Platelegs"}})
		for direction: String in CharacterSpriteLibrary.DIRECTIONS:
			for action: String in ["idle", "walk"]:
				var animation := CharacterSpriteLibrary.animation_name(action, direction)
				actor.animated_sprite.play(animation)
				actor.animated_sprite.pause()
				for index in actor.animated_sprite.sprite_frames.get_frame_count(animation):
					actor.animated_sprite.frame = index
					actor.attachment_rig.sync_pose()
					var context := actor.attachment_rig._fitted_context()
					var pose := FittedEquipmentLibrary.frame(context)
					var joints := FittedEquipmentLibrary.joints(context)
					var image := FittedEquipmentLibrary.base_texture(pose, {"chest":true,"legs":true}, context).get_image()
					poses += 1
					for side: String in ["left", "right"]:
						for segment: Array in [["hip_","knee_"],["knee_","foot_"],["shoulder_","elbow_"],["elbow_","hand_"]]:
							var a := FittedEquipmentLibrary.point(joints[segment[0]+side])
							var b := FittedEquipmentLibrary.point(joints[segment[1]+side])
							for step in range(13):
								var pixel := Vector2i(a.lerp(b, float(step)/12.0).round())
								_check(image.get_pixelv(pixel).a > 0.99, "%s %s %d: empty %s %s" % [material,animation,index,segment[0],side])
					var legs: FittedEquipmentVisual = actor.attachment_rig.get_equipped_visual("legs")
					_check(legs.parts.size()==7, direction + ": missing near/far leg armor")
					for part_index in legs.parts.size():
						var part: Dictionary = legs.parts[part_index]
						if not bool(part.get("segmentFit",false)):
							continue
						var artwork := legs.part_sprites[part_index]
						var length := FittedEquipmentLibrary.point(joints[part.bone]).distance_to(FittedEquipmentLibrary.point(joints[part.socket]))
						_check(is_equal_approx(artwork.scale.y*artwork.texture.get_height(), length+2), "Armor does not span joint with overlap")
					_check(actor.animated_sprite.scale.is_equal_approx(Vector2(0.75,0.75)), "Armor resized the player")
	for name: String in ["Bronze Kiteshield","Bronze Square Shield","Iron Kiteshield","Iron Square Shield"]:
		actor.set_equipment({"shield":{"name":name},"chest":{"name":"Bronze Platebody"}})
		var shield: FittedEquipmentVisual = actor.attachment_rig.get_equipped_visual("shield")
		for direction: String in CharacterSpriteLibrary.DIRECTIONS:
			for action: String in ["idle","walk"]:
				var animation := CharacterSpriteLibrary.animation_name(action,direction)
				actor.animated_sprite.play(animation)
				actor.animated_sprite.pause()
				for index in actor.animated_sprite.sprite_frames.get_frame_count(animation):
					actor.animated_sprite.frame = index
					actor.attachment_rig.sync_pose()
					var part: Dictionary = shield.parts[0]
					var sprite := shield.part_sprites[0]
					var grip := FittedEquipmentLibrary.point(part.pivot)
					_check(FittedEquipmentLibrary.point(part.gripCenter).is_equal_approx(grip), name+": unregistered handle center")
					_check(sprite.texture.get_image().get_pixelv(Vector2i(grip.round())).a>0.99, name+": hand attaches to empty air")
					_check(absf(wrapf(sprite.global_rotation-actor.animated_sprite.global_rotation,-PI,PI)) < 0.001, name+": unwanted shield rotation")
					_check(shield.part_bones[0].global_position.distance_to(actor.attachment_rig.get_socket("left_hand").global_position)<0.001, name+": handle detached from left hand")
	actor.set_equipment({})
	_check(actor.animated_sprite.self_modulate.a==1.0, "Unequipping did not restore original character")
	actor.free()
	var report := {"status":"pass" if failures.is_empty() else "fail","checks":checks,"armored_poses":poses,"shield_poses":288,"errors":failures}
	var out := FileAccess.open("res://data/limb_shield_validation.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "))
	print("[Limb/shield regression] ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
