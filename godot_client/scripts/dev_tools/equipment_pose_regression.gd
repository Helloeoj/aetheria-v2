extends SceneTree
## Real equipment regression: incorrect rear ordering, foot swaps and drifting soles.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		if failures.size() <= 30:
			printerr("[Equipment pose] " + label)

func _pose(actor: ActorSprite, direction: String, frame: int = -1) -> void:
	actor.animated_sprite.play(CharacterSpriteLibrary.animation_name("idle" if frame < 0 else "walk", direction))
	actor.animated_sprite.pause()
	actor.animated_sprite.frame = maxi(0, frame)
	actor.attachment_rig.sync_pose()

func _staff_gem_overlaps_helmet(first: Sprite2D, second: Sprite2D) -> bool:
	var image := first.texture.get_image()
	var other := second.texture.get_image()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			# The cyan focal gem must clear the head. A far-hand shaft can
			# legitimately pass behind it and be occluded by the helmet.
			if color.a == 0.0 or color.g < 0.55 or color.g < color.r * 1.25 or color.b < color.r * 1.15:
				continue
			var target := Vector2i((second.to_local(first.to_global(first.offset + Vector2(x + 0.5, y + 0.5))) - second.offset).floor())
			if target.x >= 0 and target.y >= 0 and target.x < other.get_width() and target.y < other.get_height() and other.get_pixelv(target).a > 0.0:
				return true
	return false

func _native_neighbors_touch(first: Image, second: Image, first_offset := Vector2i.ZERO) -> bool:
	for y in range(first.get_height()):
		for x in range(first.get_width()):
			if first.get_pixel(x, y).a == 0.0:
				continue
			for yy in range(maxi(0, y + first_offset.y - 1), mini(second.get_height(), y + first_offset.y + 2)):
				for xx in range(maxi(0, x + first_offset.x - 1), mini(second.get_width(), x + first_offset.x + 2)):
					if second.get_pixel(xx, yy).a > 0.0:
						return true
	return false

func _run() -> void:
	await process_frame
	var actor := ActorSprite.new().configure(Vector2(32, 32), Color.BLUE, "equipment_pose")
	root.add_child(actor)
	actor.set_process(false)
	actor.set_skin("peasant")
	FittedEquipmentLibrary.initialize()
	var original_pixels := {}
	for direction: String in CharacterSpriteLibrary.DIRECTIONS:
		for source_pose: Dictionary in FittedEquipmentLibrary.rig_data.rigs[direction].frames:
			original_pixels[source_pose.original] = FittedEquipmentLibrary.texture(source_pose.original).get_image().get_data().duplicate()
	for material: String in ["Bronze", "Iron", "Steel"]:
		var gear := {"chest":{"name":material + " Platebody"}, "legs":{"name":material + " Platelegs"}, "weapon":{"name":material + " Longsword"}, "shield":{"name":material + " Kiteshield"}, "cape":{"name":material + " Cape"}}
		actor.set_equipment(gear)
		for direction: String in CharacterSpriteLibrary.DIRECTIONS:
			for frame in range(-1, 8):
				_pose(actor, direction, frame)
				var rig := actor.attachment_rig
				var context := rig._fitted_context()
				var body := actor.animated_sprite.get_node("ArmorUnderbody")
				check(body.texture.get_image().get_used_rect().size == Vector2i.ZERO, "Old torso/legs or procedural limb filler remains underneath replacement armor")
				var head_art := actor.animated_sprite.get_node("ArmorHeadForeground") as Sprite2D
				var chest_art := (rig.get_equipped_visual("chest") as FittedEquipmentVisual).part_sprites[0]
				var head_origin := actor.animated_sprite.to_local(head_art.to_global(head_art.offset))
				var chest_origin := actor.animated_sprite.to_local(chest_art.to_global(chest_art.offset))
				var head_offset := Vector2i((head_origin-chest_origin).round())
				check(head_offset==Vector2i(FittedEquipmentLibrary.point(context.body_pose.headOffset)), "Head does not follow registered source collar")
				check(absi(head_offset.x)<=8 and absi(head_offset.y)<=4,"Head registration exceeds native motion envelope")
				check(_native_neighbors_touch(head_art.texture.get_image(), chest_art.texture.get_image(), head_offset), "Native collar gap leaves the head disconnected: " + material + "/" + direction + "/" + str(frame))
				for socket_name: String in ["right_hand", "left_hand", "back"]:
					var socket := rig.get_socket(socket_name)
					var rear := (socket_name == "right_hand" and direction in ["north", "north-east", "north-west", "west"]) or (socket_name == "left_hand" and direction in ["north", "north-east", "north-west", "east"]) or (socket_name == "back" and not direction.begins_with("north"))
					check(not socket.show_behind_parent, "Replacement body leaves " + socket_name + " behind the invisible source: " + direction)
					check((socket.get_index() < body.get_index()) == rear, "Wrong replacement body occlusion: " + direction + "/" + socket_name)
				check(rig.get_socket("back").get_index()<head_art.get_index(),"Cape draws above the complete character head")
				for slot: String in ["chest", "legs"]:
					var item := rig.get_equipped_visual(slot) as FittedEquipmentVisual
					check(item.authored_pose, "Replacement armor has no authored pose: " + material + "/" + direction + "/" + str(frame) + "/" + slot)
					for sprite: Sprite2D in item.part_sprites:
						check(sprite.scale == Vector2.ONE and is_zero_approx(sprite.rotation), "Armor stretched/rotated to fit the old body")
						check(sprite.texture.get_size() == Vector2(80, 80), "Replacement frame lost its native canvas")
				var weapon := rig.get_equipped_visual("weapon") as FittedEquipmentVisual
				check(weapon.part_bones[0].global_position.distance_to(rig.get_socket("right_hand").global_position) < 0.01, "Weapon hilt detached from the hand")
				var before := weapon.part_sprites[0]
				actor.set_equipment(gear)
				check(weapon.part_sprites[0] == before, "Refreshing equipment rebuilt an unchanged pose")
	# Individual slots and mixed material loadouts must retain the other slots.
	for gear: Dictionary in [{"chest":{"name":"Iron Platebody"}}, {"legs":{"name":"Bronze Platelegs"}}, {"head":{"name":"Steel Helmet"}}, {"chest":{"name":"Iron Platebody"}, "legs":{"name":"Steel Platelegs"}}]:
		actor.set_equipment(gear)
		_pose(actor, "south")
		check(actor.animated_sprite.self_modulate.a == 0.0, "Partial armor did not mask the original draw")
		for slot: String in gear:
			check(actor.attachment_rig.get_equipped_visual(slot) != null, "Mixing armor slots lost a piece")
	actor.set_equipment({"chest":{"name":"Iron Platebody"}})
	_pose(actor, "north-west", 4)
	var underbody := actor.animated_sprite.get_node("ArmorUnderbody") as Sprite2D
	check(underbody.texture.get_image().get_pixel(31, 51).a == 0.0, "Chest-only replacement leaks the old low-swinging hand")
	actor.set_equipment({"legs":{"name":"Iron Platelegs"}})
	_pose(actor, "north-west", 4)
	var bare_hand := actor.animated_sprite.get_node("ArmorForearm_left") as Sprite2D
	check(bare_hand.visible and bare_hand.texture.get_image().get_pixel(31, 51).a > 0.0, "Legs-only replacement hides the upper body's low-swinging hand")
	for path: String in original_pixels:
		check(FittedEquipmentLibrary.texture(path).get_image().get_data() == original_pixels[path], "Masking armor permanently mutated shared source pixels: " + path)
	actor.set_equipment({"head":{"name":"Iron Helmet"}, "chest":{"name":"Iron Platebody"}, "legs":{"name":"Iron Platelegs"}, "weapon":{"name":"Iron Magic Staff"}})
	for direction: String in ["east", "west"]:
		for frame in range(-1, 8):
			_pose(actor, direction, frame)
			var staff := actor.attachment_rig.get_equipped_visual("weapon") as FittedEquipmentVisual
			var helmet := actor.attachment_rig.get_equipped_visual("head") as FittedEquipmentVisual
			check(not _staff_gem_overlaps_helmet(staff.part_sprites[0], helmet.part_sprites[0]), "Side-facing staff gem cuts into the helmet: " + direction + "/" + str(frame))
	actor.set_equipment({"weapon":{"name":"Iron Longsword"}})
	_pose(actor, "west")
	check(actor.attachment_rig.get_socket("right_hand").show_behind_parent, "Unarmored rear hand lost original body occlusion")
	check(actor.animated_sprite.self_modulate.a == 1.0, "Removing armor did not restore the original character")
	actor.set_skin("goblin_scout")
	check(not actor.attachment_rig.get_equipped_visual("weapon").is_visible_in_tree(), "Unsupported skin shows stale equipment")
	actor.free()
	print("[Equipment pose regression] checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
