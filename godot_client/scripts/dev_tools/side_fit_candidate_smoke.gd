extends SceneTree
## Approved ONE-POSE art is present in normal equipment data, without a flag.
var checks := 0
var failures: Array[String] = []
func _initialize() -> void:
	_run.call_deferred()
func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("[Side fit candidate] ",message)
func _run() -> void:
	await process_frame
	FittedEquipmentLibrary.initialize()
	_check(FittedEquipmentLibrary.item_data["bronze-platebody"].get("poseViews", {}).has("west"), "Approved pose is missing from normal equipment data")
	var actor := ActorSprite.new().configure(Vector2(32,32),Color.BLUE,"candidate_socket_check")
	root.add_child(actor)
	actor.set_process(false)
	actor.set_skin("peasant")
	actor.set_equipment({"chest":{"name":"Bronze Platebody"},"legs":{"name":"Bronze Platelegs"}})
	var authored_poses := 0
	var visited := 0
	for direction: String in CharacterSpriteLibrary.DIRECTIONS:
		for action: String in ["idle","walk"]:
			var animation := CharacterSpriteLibrary.animation_name(action,direction)
			actor.animated_sprite.play(animation)
			actor.animated_sprite.pause()
			for index in actor.animated_sprite.sprite_frames.get_frame_count(animation):
				actor.animated_sprite.frame = index
				actor.attachment_rig.sync_pose()
				visited += 1
				var expected := direction=="west" and action=="walk" and index==2
				_check(actor.animated_sprite.scale.is_equal_approx(Vector2(0.75,0.75)),"Player scale changed")
				var reconstruction := Image.create(80,80,false,Image.FORMAT_RGBA8)
				var collar_overlap := Image.create(80,80,false,Image.FORMAT_RGBA8)
				var context := actor.attachment_rig._fitted_context()
				var joints := FittedEquipmentLibrary.joints(context)
				for slot: String in ["chest","legs"]:
					var node: FittedEquipmentVisual = actor.attachment_rig.get_equipped_visual(slot)
					_check(node.authored_pose==expected,"Pose override leaked or did not activate: "+animation+str(index))
					if not expected:
						continue
					for n in node.parts.size():
						var part: Dictionary = node.parts[n]
						var sprite := node.part_sprites[n]
						_check(sprite.scale.is_equal_approx(Vector2.ONE),"Authored armor was stretched")
						_check(is_zero_approx(sprite.rotation),"Authored plate was spuriously rotated")
						var target := Vector2(context.origin) - Vector2(context.padding) + FittedEquipmentLibrary.point(joints[part.socket])
						var world_target := actor.animated_sprite.to_global(target)
						_check(node.part_bones[n].global_position.distance_to(world_target)<0.001,"Part detached from "+String(part.socket))
						var texture_image := sprite.texture.get_image()
						texture_image.convert(Image.FORMAT_RGBA8)
						var destination := Vector2i((FittedEquipmentLibrary.point(joints[part.socket])-FittedEquipmentLibrary.point(part.pivot)).round())
						reconstruction.blend_rect(texture_image,Rect2i(Vector2i.ZERO,texture_image.get_size()),destination)
						if String(part.name)=="neck-gorget":
							collar_overlap.blend_rect(texture_image,Rect2i(Vector2i.ZERO,texture_image.get_size()),destination)
				if expected:
					authored_poses += 1
					var path := FittedEquipmentLibrary.ROOT + "candidates/bronze-side-fit-v3/armor-with-collar-native.png"
					var armor := Image.load_from_file(ProjectSettings.globalize_path(path))
					armor.convert(Image.FORMAT_RGBA8)
					_check(reconstruction.get_data()==armor.get_data(),"Independent pieces did not reassemble exactly")
					var head := FittedEquipmentLibrary.texture(FittedEquipmentLibrary.frame(context).head).get_image()
					for y in range(80):
						for x in range(80):
							if head.get_pixel(x,y).a>0 and collar_overlap.get_pixel(x,y).a==0:
								_check(reconstruction.get_pixel(x,y).a==0,"Character head pixels baked into armor")
	_check(authored_poses==1,"Candidate must replace exactly one pose")
	_check(visited==72,"Did not check all original player poses")
	actor.free()
	var report := {"status":"pass" if failures.is_empty() else "fail","checks":checks,"original_poses_checked":visited,"candidate_poses":authored_poses,"errors":failures}
	var out := FileAccess.open("res://data/side_fit_candidate_validation.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "))
	print("[Side fit candidate] ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
