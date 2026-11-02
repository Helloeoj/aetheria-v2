extends SceneTree
## Independent original face samples: equipping a torso must not cut the jaw.
var failures := 0
var weapon_failures := {}

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		if failures < 12:
			printerr("[Equipment identity FAIL] ", message)

static func covers_face(weapon: Sprite2D, head: Sprite2D) -> bool:
	var art := weapon.texture.get_image()
	var original := head.texture.get_image()
	for y in range(art.get_height()):
		for x in range(art.get_width()):
			if art.get_pixel(x,y).a == 0.0:
				continue
			var pixel := Vector2i(head.to_local(weapon.to_global(weapon.offset + Vector2(x+0.5,y+0.5))).floor())
			if pixel.x < 0 or pixel.y < 0 or pixel.x >= original.get_width() or pixel.y >= original.get_height():
				continue
			var color := original.get_pixelv(pixel)
			if color.a > 0.0 and color.r > 0.55 and color.r > color.g * 1.2 and color.g > color.b * 1.05:
				return true
	return false

func component_count(image: Image) -> int:
	var remaining := {}
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x,y).a > 0.0:
				remaining[Vector2i(x,y)] = true
	var count := 0
	while not remaining.is_empty():
		count += 1
		var pending := [remaining.keys()[0]]
		remaining.erase(pending[0])
		while not pending.is_empty():
			var pixel: Vector2i = pending.pop_back()
			for dy in range(-1,2):
				for dx in range(-1,2):
					var next := pixel + Vector2i(dx,dy)
					if remaining.has(next):
						remaining.erase(next)
						pending.append(next)
	return count

func _run() -> void:
	var crossbow_path := "sprites/iron/crossbow/south-west/weapon.png"
	var fitted := FittedEquipmentLibrary.native_part(crossbow_path,Vector2(9,8),Vector2.ZERO,PI/4,Vector2.ONE)
	check(component_count(FittedEquipmentLibrary.texture(crossbow_path).get_image()) == 1, "crossbow source fixture must be connected")
	check(component_count(fitted.texture.get_image()) == 1, "native rotation disconnects crossbow limbs or bowstring")
	var palette := {}
	var source_weapon := FittedEquipmentLibrary.texture(crossbow_path).get_image()
	for y in range(source_weapon.get_height()):
		for x in range(source_weapon.get_width()):
			palette[source_weapon.get_pixel(x,y)] = true
	var rotated: Image = fitted.texture.get_image()
	for y in range(rotated.get_height()):
		for x in range(rotated.get_width()):
			if rotated.get_pixel(x,y).a > 0.0:
				check(palette.has(rotated.get_pixel(x,y)), "native weapon rotation changed a palette color")
	var actor := ActorSprite.new().configure(Vector2(32,32), Color.BLUE, "identity")
	root.add_child(actor)
	actor.set_process(false)
	actor.set_skin("peasant")
	actor.set_equipment({"chest":{"name":"Iron Platebody"}, "legs":{"name":"Iron Platelegs"}})
	actor.animated_sprite.play(&"walk_south")
	actor.animated_sprite.pause()
	actor.animated_sprite.frame = 0
	actor.attachment_rig.sync_pose()
	var head := actor.animated_sprite.get_node("ArmorHeadForeground") as Sprite2D
	var source := FittedEquipmentLibrary.texture("original/south/1.png").get_image()
	for sample: Vector2i in [Vector2i(39,38), Vector2i(40,38), Vector2i(42,37), Vector2i(41,39)]:
		check(source.get_pixelv(sample).a > 0.0, "original chin sample must be opaque")
		check(head.texture.get_image().get_pixelv(sample) == source.get_pixelv(sample), "equipped torso cuts or recolors original chin at " + str(sample))
	for direction: String in CharacterSpriteLibrary.DIRECTIONS:
		for pose: Dictionary in FittedEquipmentLibrary.rig_data.rigs[direction].frames:
			var original := FittedEquipmentLibrary.texture(pose.original).get_image()
			var restored := FittedEquipmentLibrary.head_texture(pose).get_image()
			for arg: String in OS.get_cmdline_user_args():
				if arg.begins_with("--head-output="):
					var destination := arg.trim_prefix("--head-output=").path_join(direction)
					DirAccess.make_dir_recursive_absolute(destination)
					restored.save_png(destination.path_join(str(pose.index) + ("-idle" if pose.clip == "idle" else "") + ".png"))
			var center: Vector2 = FittedEquipmentLibrary.point(pose.joints.head)
			for y in range(restored.get_height()):
				for x in range(restored.get_width()):
					var color := restored.get_pixel(x,y)
					if y < center.y - 5 and original.get_pixel(x,y).a > 0.0:
						check(color == original.get_pixel(x,y), "head restoration changed original hair silhouette: " + String(pose.original) + "/" + str(Vector2i(x,y)))
					if color.a > 0.0:
						check(color == original.get_pixel(x,y), "head restoration changed original RGBA: " + String(pose.original))
					# Original cheek/jaw skin below the old horizontal cut.
					var expected := original.get_pixel(x,y)
					if y >= center.y and y <= float(pose.joints.neck[1]) + 1 and absf(x-center.x) <= 8 and expected.a > 0.0 and expected.r > 0.55 and expected.r > expected.g * 1.2 and expected.g > expected.b * 1.05:
						check(color == expected, "original face pixel missing: " + String(pose.original) + "/" + str(Vector2i(x,y)))
	var diagonal: Dictionary = FittedEquipmentLibrary.rig_data.rigs["north-east"].frames[1]
	check(FittedEquipmentLibrary.head_texture(diagonal).get_image().get_pixel(29,30).a == 0.0, "original robe triangle remains behind north-east hair")
	diagonal = FittedEquipmentLibrary.rig_data.rigs["north-west"].frames[1]
	check(FittedEquipmentLibrary.head_texture(diagonal).get_image().get_pixel(48,30).a == 0.0, "original robe triangle remains behind north-west hair")
	for item: Dictionary in FittedEquipmentLibrary.item_data.values():
		if item.slot != "weapon":
			continue
		var material: String = item.material
		for armored: bool in [false,true]:
			var gear := {"weapon":{"name":String(item.name)}}
			if armored:
				gear.merge({"chest":{"name":material+" Platebody"},"legs":{"name":material+" Platelegs"},"cape":{"name":material+" Cape"}})
			actor.set_equipment(gear)
			for direction: String in ["south","south-east","south-west","east"]:
				for frame in range(-1,8):
					actor.animated_sprite.play(CharacterSpriteLibrary.animation_name("idle" if frame<0 else "walk",direction))
					actor.animated_sprite.pause()
					actor.animated_sprite.frame = maxi(0,frame)
					actor.attachment_rig.sync_pose()
					# Use the original face mask even in unarmored mode.
					var pose := FittedEquipmentLibrary.frame(actor.attachment_rig._fitted_context())
					head.texture = FittedEquipmentLibrary.head_texture(pose)
					var weapon := actor.attachment_rig.get_equipped_visual("weapon") as FittedEquipmentVisual
					var overlap := covers_face(weapon.part_sprites[0],head)
					if overlap:
						var failure_key := String(item.name)+"/"+direction
						weapon_failures[failure_key] = int(weapon_failures.get(failure_key,0))+1
					check(not overlap, "weapon intersects original face: "+String(item.name)+"/"+direction+"/"+str(frame)+"/armor="+str(armored))
	actor.free()
	if not weapon_failures.is_empty():
		print("[Weapon face failures] ",weapon_failures)
	print("[Equipment identity] ", failures, " failures")
	quit(0 if failures == 0 else 1)
