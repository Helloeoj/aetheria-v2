extends SceneTree
## Actual F7 actor/rig renders for complete cape and weapon loadouts.
var preview: Variant
var destination := ""
var kind := "weapons"
var material := "Iron"
var item_type := ""
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--outfit-output="):
			destination = arg.trim_prefix("--outfit-output=")
		if arg.begins_with("--outfit-kind="):
			kind = arg.trim_prefix("--outfit-kind=")
		if arg.begins_with("--review-material="):
			material = arg.trim_prefix("--review-material=")
		if arg.begins_with("--review-type="):
			item_type = arg.trim_prefix("--review-type=")
	if destination.is_empty() or kind not in ["weapons", "capes"]:
		printerr("Pass --outfit-output=<directory> --outfit-kind=weapons|capes [--review-material=Iron]")
		quit(1)
		return
	root.size = Vector2i(1280,720)
	if "--outfit-minimized" in OS.get_cmdline_user_args():
		root.mode = Window.MODE_MINIMIZED
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	preview = (load("res://scripts/sprite_preview.gd") as GDScript).new()
	root.add_child(preview)
	preview._select_skin(preview.skin_ids.find("peasant"))
	preview.show_preview()
	preview._change_review_zoom(2)
	preview._set_review_paused(true)
	FittedEquipmentLibrary.initialize()
	for item: Dictionary in FittedEquipmentLibrary.item_data.values():
		if item.slot != ("weapon" if kind == "weapons" else "cape") or (material != "all" and item.material != material):
			continue
		if not item_type.is_empty() and not String(item.id).ends_with("-" + item_type):
			continue
		for armored: bool in [false, true]:
			var gear := {String(item.slot):{"name":String(item.name)}}
			if armored:
				gear.merge({"chest":{"name":item.material + " Platebody"}, "legs":{"name":item.material + " Platelegs"}})
				if kind == "weapons":
					gear.cape = {"name":item.material + " Cape"}
			preview.actor.set_equipment(gear)
			preview.review_equipment = gear.duplicate(true)
			var folder := destination.path_join(item.id + ("-armor" if armored else "-bare"))
			DirAccess.make_dir_recursive_absolute(folder)
			for direction: String in CharacterSpriteLibrary.DIRECTIONS:
				for index in range(9):
					var sprite: AnimatedSprite2D = preview.actor.animated_sprite
					sprite.play(CharacterSpriteLibrary.animation_name("idle" if index == 0 else "walk", direction))
					sprite.pause()
					sprite.frame = maxi(0,index - 1)
					preview.actor.attachment_rig.sync_pose()
					preview.action_picker.select(0 if index == 0 else 1)
					preview._refresh_review_frame()
					var result: Error = await preview.capture_review_frame(folder.path_join("%s-%d.png" % [direction,index]))
					if result != OK:
						failures += 1
						printerr("[Outfit review] Export failed: ",folder," ",direction,"/",index)
			print("[Outfit review] ",item.id," armored=",armored)
	preview.free()
	print("[Outfit review] ", failures, " export failures")
	quit(0 if failures == 0 else 1)
