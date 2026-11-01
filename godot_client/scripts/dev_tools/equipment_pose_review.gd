extends SceneTree
## Actual game ActorSprite, original animation clock, real Godot 4x rendering.
var destination := ""
var viewport: SubViewport
var actors: Array[ActorSprite] = []
const CELL := Vector2i(240, 240)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--pose-output="):
			destination = arg.trim_prefix("--pose-output=")
	if destination.is_empty():
		printerr("Pass --pose-output=<absolute directory>")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(destination)
	viewport = SubViewport.new()
	viewport.size = Vector2i(CELL.x * 9, CELL.y * 8)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.color = Color("1e242d")
	background.size = viewport.size
	viewport.add_child(background)
	for row in range(8):
		for col in range(9):
			var actor := ActorSprite.new().configure(Vector2(32,32), Color.BLUE, "review_" + str(row) + "_" + str(col))
			viewport.add_child(actor)
			actor.set_process(false)
			actor.scale = Vector2(4, 4)
			actor.position = Vector2(col * CELL.x + 120, row * CELL.y + 211)
			actor.set_skin("peasant")
			actors.append(actor)
			var label := Label.new()
			label.text = CharacterSpriteLibrary.DIRECTIONS[row] + (" idle" if col == 0 else " walk " + str(col - 1))
			label.position = Vector2(col * CELL.x + 4, row * CELL.y + 220)
			viewport.add_child(label)
	await process_frame
	for material: String in ["Bronze", "Iron", "Steel"]:
		for mode: String in ["unarmored", "head", "chest", "legs", "armor", "mixed", "full"]:
			var gear := {}
			if mode in ["armor", "full", "mixed"]:
				gear = {"chest":{"name":material+" Platebody"}, "legs":{"name":material+" Platelegs"}}
			elif mode == "head":
				gear = {"head":{"name":material+" Helmet"}}
			elif mode == "chest":
				gear = {"chest":{"name":material+" Platebody"}}
			elif mode == "legs":
				gear = {"legs":{"name":material+" Platelegs"}}
			if mode == "mixed":
				gear.legs.name = "Steel Platelegs" if material != "Steel" else "Bronze Platelegs"
			if mode == "full":
				gear.merge({"head":{"name":material+" Helmet"}, "weapon":{"name":material+" Longsword"}, "shield":{"name":material+" Kiteshield"}, "cape":{"name":material+" Cape"}, "neck":{"name":material+" Necklace"}})
			await _capture(gear, material.to_lower() + "-" + mode)
	# Weapons use all poses too, with and without armor. Every tier shares the
	# same geometry; all three tiers are covered in the headless regression.
	for suffix: String in ["Dagger", "Shortsword", "Longsword", "Mace", "Warmaul", "Bow", "Crossbow", "Magic Staff", "Magic Wand"]:
		for armor: bool in [false, true]:
			var gear := {"weapon":{"name":"Iron " + suffix}}
			if armor:
				gear.merge({"chest":{"name":"Iron Platebody"},"legs":{"name":"Iron Platelegs"},"head":{"name":"Iron Helmet"}})
			await _capture(gear, suffix.to_lower().replace(" ", "-") + ("-armor" if armor else "-bare"))
	print("[Equipment pose review] Actual 4x Godot sheets saved to ", destination)
	actors.clear()
	viewport.free()
	viewport = null
	await process_frame
	quit()

func _capture(gear: Dictionary, label: String) -> void:
	for index in range(actors.size()):
		var actor := actors[index]
		actor.set_equipment(gear)
		actor.animated_sprite.play(CharacterSpriteLibrary.animation_name("idle" if index % 9 == 0 else "walk", CharacterSpriteLibrary.DIRECTIONS[index / 9]))
		actor.animated_sprite.pause()
		actor.animated_sprite.frame = maxi(0, index % 9 - 1)
		actor.attachment_rig.sync_pose()
	await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(destination.path_join(label + ".png"))
	print("[Equipment pose review] ", label)
