extends SceneTree
## Captures the EXISTING F7 preview inside the actual game, never another scene.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var destination := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--audit-output="):
			destination = argument.trim_prefix("--audit-output=")
	if destination.is_empty():
		printerr("Pass --audit-output=<absolute directory>")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(destination)
	var scene := (load("res://scenes/EastOutskirtsLayered.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var game: Node = scene.get_node("Combat")
	game.set_physics_process(false)
	var preview: Variant = game.get("sprite_preview")
	preview._select_skin(preview.skin_ids.find("peasant"))
	preview.show_preview()
	preview.set_process(false)
	preview.actor.set_process(false)
	await process_frame
	var actor: ActorSprite = preview.actor
	var sprite: AnimatedSprite2D = actor.animated_sprite
	if "--audit-all-items" in OS.get_cmdline_user_args():
		await _audit_all_items(actor, destination)
		quit()
		return
	var support_root := destination.get_base_dir().path_join("support")
	var tracks := {}
	var modes := ["Bronze", "Iron", "Bronze limbs", "Bronze shield", "Bronze square", "Iron shield", "Iron square", "Adamantite shield"]
	var candidate_only := "--audit-candidate-only" in OS.get_cmdline_user_args()
	if candidate_only or "--audit-platebody-only" in OS.get_cmdline_user_args():
		modes = ["Bronze limbs"]
	for mode: String in modes:
		var loadout := {}
		if mode in ["Bronze", "Iron", "Bronze limbs"]:
			var material := "Iron" if mode == "Iron" else "Bronze"
			for slot: String in ["chest", "legs"]:
				loadout[slot] = {"name": material + (" Platebody" if slot == "chest" else " Platelegs")}
			if mode != "Bronze limbs":
				loadout.head = {"name": material + " Helmet"}
				loadout.weapon = {"name": material + " Longsword"}
				loadout.shield = {"name": material + " Kiteshield"}
		elif mode != "Adamantite shield":
			loadout.shield = {"name": ("Iron" if mode.begins_with("Iron") else "Bronze") + (" Square Shield" if mode.ends_with("square") else " Kiteshield")}
		else:
			loadout.shield = {"name": "Adamantite Kiteshield"}
		actor.set_equipment(loadout)
		for direction: String in ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"]:
			if candidate_only and direction != "west":
				continue
			for index in range(9 if mode in ["Bronze", "Iron", "Bronze limbs"] else 1):
				if candidate_only and index != 3:
					continue
				var animation := CharacterSpriteLibrary.animation_name("idle" if index == 0 else "walk", direction)
				sprite.play(animation)
				sprite.pause()
				sprite.frame = maxi(0, index - 1)
				actor.attachment_rig.sync_pose()
				if mode == "Bronze limbs":
					var context := actor.attachment_rig._fitted_context()
					var pose := FittedEquipmentLibrary.frame(context)
					var prefix := support_root.path_join(direction)
					DirAccess.make_dir_recursive_absolute(prefix)
					if not tracks.has(direction):
						tracks[direction] = {}
					tracks[direction][str(index)] = FittedEquipmentLibrary.joints(context)
					for variant: String in ["chest", "legs", "chestLegs"]:
						var flags := {"chest":variant != "legs", "legs":variant != "chest"}
						FittedEquipmentLibrary.base_texture(pose,flags,context).get_image().save_png(prefix.path_join(str(index)+"-"+variant+".png"))
					for side: String in ["left","right"]:
						FittedEquipmentLibrary.forearm_texture(context,side).get_image().save_png(prefix.path_join(str(index)+"-arm-"+side+".png"))
						FittedEquipmentLibrary.hand_texture(context,side).get_image().save_png(prefix.path_join(str(index)+"-grip-"+side+".png"))
				await process_frame
				await RenderingServer.frame_post_draw
				var screenshot := root.get_texture().get_image()
				var foot := actor.get_global_transform_with_canvas().origin
				var rect := Rect2i(Vector2i(foot) - Vector2i(115, 160), Vector2i(230, 190))
				var path := "%s/%s_%s_%d.png" % [destination, mode.to_lower().replace(" ", "-"), direction, index]
				screenshot.get_region(rect).save_png(path)
		print("[Equipment visual audit] ", mode)
	var output := FileAccess.open(support_root.path_join("joints.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify(tracks,"  "))
	print("[Equipment visual audit] Saved actual game captures to ", destination)
	quit()

func _capture_actor(actor: ActorSprite, destination: String, label: String, direction: String, index: int) -> void:
	var sprite := actor.animated_sprite
	sprite.play(CharacterSpriteLibrary.animation_name("idle" if index == 0 else "walk", direction))
	sprite.pause()
	sprite.frame = maxi(0, index - 1)
	actor.attachment_rig.sync_pose()
	await process_frame
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	var foot := actor.get_global_transform_with_canvas().origin
	var rect := Rect2i(Vector2i(foot) - Vector2i(115, 160), Vector2i(230, 190))
	screenshot.get_region(rect).save_png("%s/%s_%s_%d.png" % [destination, label, direction, index])

func _audit_all_items(actor: ActorSprite, destination: String) -> void:
	# Use this game's existing F7 ActorSprite and real visual registry. All
	# single items at eight facings, then complete armor through all 72 poses.
	for item: Dictionary in FittedEquipmentLibrary.item_data.values():
		actor.set_equipment({String(item.slot):{"name":String(item.name)}})
		for direction: String in CharacterSpriteLibrary.DIRECTIONS:
			await _capture_actor(actor, destination, item.id, direction, 0)
		print("[Equipment visual audit] Item ", item.name)
	for material: String in ["Bronze", "Iron", "Steel"]:
		var loadout := {"chest":{"name":material+" Platebody"},"legs":{"name":material+" Platelegs"}}
		actor.set_equipment(loadout)
		for direction: String in CharacterSpriteLibrary.DIRECTIONS:
			for index in range(9):
				await _capture_actor(actor,destination,material.to_lower()+"-limbs",direction,index)
		loadout.head={"name":material+" Helmet"}
		loadout.weapon={"name":material+" Longsword"}
		loadout.shield={"name":material+" Kiteshield"}
		loadout.cape={"name":material+" Cape"}
		loadout.neck={"name":material+" Necklace"}
		actor.set_equipment(loadout)
		for direction: String in CharacterSpriteLibrary.DIRECTIONS:
			for index in [0,3,7]:
				await _capture_actor(actor,destination,material.to_lower()+"-full",direction,index)
		print("[Equipment visual audit] Complete set ",material)
	print("[Equipment visual audit] 696 existing-game captures saved to ",destination)
