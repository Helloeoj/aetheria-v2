extends SceneTree
var preview: Variant
var destination := ""
var families: Array[String]=["warmaul","pickaxe","bow"]
var directions: Array[String]=["south","south-east"]
var tier := "Bronze"
var selected_frames: Array[int]=[]
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--motion-output="):
			destination=argument.trim_prefix("--motion-output=")
		elif argument.begins_with("--motion-families="):
			families.assign(argument.trim_prefix("--motion-families=").split(","))
		elif argument.begins_with("--motion-directions="):
			directions.assign(argument.trim_prefix("--motion-directions=").split(","))
		elif argument.begins_with("--motion-tier="):
			tier=argument.trim_prefix("--motion-tier=")
		elif argument.begins_with("--motion-frames="):
			for value: String in argument.trim_prefix("--motion-frames=").split(",",false): selected_frames.append(int(value))
	if destination.is_empty():
		quit(1)
		return
	root.size=Vector2i(1280,720)
	root.mode=Window.MODE_MINIMIZED
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	preview=load("res://scripts/sprite_preview.gd").new()
	root.add_child(preview)
	preview._select_skin(preview.skin_ids.find("peasant"))
	preview.show_preview()
	preview._change_review_zoom(2)
	preview._set_review_paused(true)
	for family: String in families:
		var name:=tier+" "+family.replace("-"," ").capitalize()
		for armored: bool in [false,true]:
			var gear:={"weapon":{"name":name}}
			if armored:
				gear.merge({"chest":{"name":tier+" Platebody"},"legs":{"name":tier+" Platelegs"},"cape":{"name":tier+" Cape"}})
			preview.actor.set_equipment(gear)
			preview.review_equipment=gear.duplicate(true)
			var folder:=destination.path_join(family+("-armor" if armored else "-bare"))
			DirAccess.make_dir_recursive_absolute(folder)
			for direction: String in directions:
				preview.direction_picker.select(CharacterSpriteLibrary.DIRECTIONS.find(direction))
				for action: String in ["idle","walk","attack"]:
					var sprite: AnimatedSprite2D=preview.actor.animated_sprite
					var clip:=CharacterSpriteLibrary.animation_name(action,direction)
					if not sprite.sprite_frames.has_animation(clip):
						printerr("Missing ",name," ",clip)
						quit(1)
						return
					sprite.play(clip)
					sprite.pause()
					preview.action_picker.select(["idle","walk","attack"].find(action))
					for frame in range(sprite.sprite_frames.get_frame_count(clip)):
						if not selected_frames.is_empty() and frame not in selected_frames: continue
						sprite.frame=frame
						preview.actor.attachment_rig.sync_pose()
						var error: Error=await preview.capture_review_frame(folder.path_join("%s-%s-%02d.png" % [direction,action,frame]))
						if error!=OK:
							printerr("Capture failed: ",error)
							quit(1)
							return
			print("[Motion review] ",family," armored=",armored)
	preview.free()
	print("[Motion review] Complete")
	quit()
