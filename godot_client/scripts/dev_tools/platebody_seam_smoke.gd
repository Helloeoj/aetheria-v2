extends SceneTree
## Head-to-chest continuity across all 72 original animation poses.
var checks := 0
var failures: Array[String] = []
func _initialize() -> void:
	_run.call_deferred()
func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("[Platebody seams] ",message)
func _run() -> void:
	await process_frame
	var actor := ActorSprite.new().configure(Vector2(32,32),Color.BLUE,"platebody_seam_regression")
	root.add_child(actor)
	actor.set_process(false)
	actor.set_skin("peasant")
	var poses := 0
	for material: String in ["Bronze","Iron","Steel"]:
		actor.set_equipment({"chest":{"name":material+" Platebody"},"legs":{"name":material+" Platelegs"}})
		for direction: String in CharacterSpriteLibrary.DIRECTIONS:
			for action: String in ["idle","walk"]:
				var animation := CharacterSpriteLibrary.animation_name(action,direction)
				actor.animated_sprite.play(animation)
				actor.animated_sprite.pause()
				for index in actor.animated_sprite.sprite_frames.get_frame_count(animation):
					actor.animated_sprite.frame = index
					actor.attachment_rig.sync_pose()
					poses += 1
					var context := actor.attachment_rig._fitted_context()
					var pose := FittedEquipmentLibrary.frame(context)
					var joints := FittedEquipmentLibrary.joints(context)
					var body := FittedEquipmentLibrary.base_texture(pose,{"chest":true,"legs":true},context).get_image()
					body.convert(Image.FORMAT_RGBA8)
					var chest: FittedEquipmentVisual = actor.attachment_rig.get_equipped_visual("chest")
					var collar_found := false
					for n in chest.parts.size():
						var part: Dictionary = chest.parts[n]
						if String(part.name)!="neck-gorget":
							continue
						collar_found = true
						var sprite := chest.part_sprites[n]
						_check(sprite.scale.is_equal_approx(Vector2.ONE) and is_zero_approx(sprite.rotation), "Collar stretched or rotated")
						var image := sprite.texture.get_image()
						image.convert(Image.FORMAT_RGBA8)
						var location := Vector2i((FittedEquipmentLibrary.point(joints[part.socket])-FittedEquipmentLibrary.point(part.pivot)).round())
						body.blend_rect(image,Rect2i(Vector2i.ZERO,image.get_size()),location)
					_check(collar_found,animation+str(index)+": missing independent collar")
					body.blend_rect(FittedEquipmentLibrary.texture(pose.head).get_image(),Rect2i(0,0,80,80),Vector2i.ZERO)
					var a := FittedEquipmentLibrary.point(joints.head)
					var b := FittedEquipmentLibrary.point(joints.neck)
					for step in range(41):
						for width in range(-1,2):
							var pixel := Vector2i((a.lerp(b,float(step)/40.0)+Vector2(width,0)).round())
							_check(body.get_pixelv(pixel).a>0.99,animation+str(index)+": transparent neck pixel "+str(pixel))
	actor.free()
	var report := {"status":"pass" if failures.is_empty() else "fail","poses":poses,"facings":8,"tiers":3,"checks":checks,"errors":failures}
	var file := FileAccess.open("res://data/platebody_seam_validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("[Platebody seams] ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
