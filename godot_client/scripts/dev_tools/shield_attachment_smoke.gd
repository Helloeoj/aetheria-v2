extends SceneTree
## Godot --headless --path godot_client --script res://scripts/dev_tools/shield_attachment_smoke.gd

const SHIELD_NAME := "Adamantite Kiteshield"
const PAIR := {"weapon": {"name": "Iron Longsword"}, "shield": {"name": SHIELD_NAME}}
const SHIELD_ONLY := {"shield": {"name": SHIELD_NAME}}
const SWORD_ONLY := {"weapon": {"name": "Iron Longsword"}}
const TEXTURE_DIRECTORY := "res://Assets/Equipment/adamantite_kiteshield/"

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_test_inventory_rules()
	var actor := _make_actor("shield_test")
	var other := _make_actor("shield_other")
	_test_all_poses(actor)
	_test_independent_equipment(actor, other)
	actor.free()
	other.free()
	await _test_scene("res://scenes/EastOutskirtsLayered.tscn", true)
	await _test_scene("res://scenes/main.tscn", false)
	if failures.is_empty():
		print("[Shield attachment smoke] PASS: %d checks, all 72 poses, 8 shield directions, both game scenes and preview isolation." % checks)
		quit(0)
	else:
		printerr("[Shield attachment smoke] FAIL: %d of %d checks failed." % [failures.size(), checks])
		quit(1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("[Shield attachment smoke] " + label)


func _make_actor(id: String) -> ActorSprite:
	var actor := ActorSprite.new().configure(Vector2(32, 32), Color.BLUE, id)
	root.add_child(actor)
	actor.set_process(false)
	actor.set_skin("peasant")
	actor.animated_sprite.pause()
	actor.set_equipment(PAIR)
	return actor


func _test_inventory_rules() -> void:
	var item: Dictionary = root.get_node("GameData").get_item(106)
	_check(String(item.get("name", "")) == SHIELD_NAME, "Item 106 must resolve to the existing Adamantite Kiteshield.")
	_check(item.get("slot", "") == "shield", "Adamantite Kiteshield must use the shield equipment slot.")
	_check(item.get("type", "") == "Armor", "Shield visual registration changed the gameplay item type.")
	# Load after autoload initialization: SceneTree --script entrypoints are
	# parsed before the GameData singleton is available to dependent scripts.
	var player: Variant = load("res://scripts/player_state.gd").new("Shield smoke")
	player.give_and_equip("Iron Longsword")
	player.give_and_equip(106)
	_check(player.equipment["weapon"].get("name", "") == "Iron Longsword", "Equipping shield removed the one-handed sword.")
	_check(player.equipment["shield"].get("name", "") == SHIELD_NAME, "Item 106 could not be equipped through the real inventory API.")
	player.give_and_equip("Iron Warmaul")
	_check(player.equipment["shield"].is_empty(), "Two-handed weapon did not unequip the shield.")
	_check(int(player.backpack.get(SHIELD_NAME, 0)) == 1, "Two-handed weapon did not return the shield to the backpack.")
	var shield_count := int(player.backpack.get(SHIELD_NAME, 0))
	var result: String = player.equip_item(SHIELD_NAME)
	_check(result.contains("two-handed"), "Shield equip did not report the two-handed restriction.")
	_check(player.equipment["shield"].is_empty(), "Blocked shield equip mutated the shield slot.")
	_check(int(player.backpack.get(SHIELD_NAME, 0)) == shield_count, "Blocked shield equip consumed the shield.")
	player.unequip_slot("weapon")
	player.equip_item(SHIELD_NAME)
	_check(player.equipment["shield"].get("name", "") == SHIELD_NAME, "Shield could not be equipped after removing the two-handed weapon.")


func _test_all_poses(actor: ActorSprite) -> void:
	var rig = actor.attachment_rig
	var shield: Node2D = rig.get_equipped_visual("shield")
	_check(shield != null, "Shield has no independent equipment instance.")
	if shield == null:
		return
	var artwork := shield.get_node_or_null("Artwork") as Sprite2D
	_check(artwork != null, "Directional shield has no Artwork Sprite2D.")
	if artwork == null:
		return
	_check(shield.has_method("set_attachment_facing"), "Shield has no facing update API.")
	_check(rig.get_socket("left_hand").is_ancestor_of(shield), "Shield is not attached below the left-hand marker.")
	_check(artwork.scale.is_equal_approx(Vector2(0.5, 0.5)), "Shield must scale at display time without resizing the source PNG.")
	_check(not artwork.centered, "Shield Artwork must use its authored grip pivot.")
	_check(artwork.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Shield is not using nearest-neighbor sampling.")
	_check(not artwork.flip_h and not artwork.flip_v, "Shield directions must use original art without mirroring.")
	var visited: Dictionary = {}
	var textures: Dictionary = {}
	for direction: String in CharacterSpriteLibrary.DIRECTIONS:
		for action: String in ["idle", "walk"]:
			var animation := CharacterSpriteLibrary.animation_name(action, direction)
			actor.animated_sprite.play(animation)
			actor.animated_sprite.pause()
			for frame in actor.animated_sprite.sprite_frames.get_frame_count(animation):
				actor.animated_sprite.frame = frame
				var character_texture := actor.animated_sprite.sprite_frames.get_frame_texture(animation, frame)
				visited[character_texture.resource_path] = true
				var label := "%s frame %d" % [animation, frame]
				_check(String(shield.get("current_facing")) == direction, label + " did not set the shield facing immediately.")
				_check(artwork.texture != null, label + " has no shield texture.")
				if artwork.texture == null:
					continue
				_check(artwork.texture.resource_path == TEXTURE_DIRECTORY + direction + ".png", label + " selected the wrong source direction.")
				_check(artwork.texture.get_size() == Vector2(68, 68), label + " changed the native shield image dimensions.")
				if textures.has(direction):
					_check(artwork.texture == textures[direction], label + " animated the direction images during walking.")
				else:
					textures[direction] = artwork.texture
				_check(shield.global_position.distance_to(rig.get_socket("left_hand").global_position) < 0.01, label + " moved the grip away from the left hand.")
				_check(absf(angle_difference(artwork.global_rotation, actor.animated_sprite.global_rotation)) < 0.001, label + " added the hand socket's grip rotation to the directional art.")
				_check(actor.skin_id == "peasant", label + " replaced the original peasant skin.")
	_check(visited.size() == 72, "Shield tracks must cover all 72 distinct peasant PNG poses.")
	_check(textures.size() == 8, "Shield must retain eight distinct directional textures.")
	actor.animated_sprite.play(&"idle_south")
	actor.animated_sprite.pause()
	actor.animated_sprite.play(&"idle_north")
	actor.animated_sprite.pause()
	_check(String(shield.get("current_facing")) == "north", "Changing only facing at frame 0 left a stale shield direction.")
	_check(artwork.texture.resource_path == TEXTURE_DIRECTORY + "north.png", "Animation-only change did not switch to the north artwork.")


func _test_independent_equipment(actor: ActorSprite, other: ActorSprite) -> void:
	var rig = actor.attachment_rig
	var sword: Node2D = rig.get_equipped_visual("weapon")
	var shield: Node2D = rig.get_equipped_visual("shield")
	var other_shield: Node2D = other.attachment_rig.get_equipped_visual("shield")
	_check(sword != null and shield != null and sword != shield, "Sword and shield must coexist as independent nodes.")
	_check(other_shield != null and other_shield != shield, "Characters share the same shield node.")
	if sword == null or shield == null or other_shield == null:
		return
	other.animated_sprite.play(&"idle_north")
	other.animated_sprite.pause()
	var artwork := shield.get_node("Artwork") as Sprite2D
	var other_artwork := other_shield.get_node("Artwork") as Sprite2D
	_check(artwork.texture == other_artwork.texture, "Separate shield nodes do not share their texture resources.")
	for _iteration in 20:
		actor.set_equipment(PAIR)
	_check(rig.get_equipped_visual("weapon") == sword, "Refreshing shield equipment recreated the sword.")
	_check(rig.get_equipped_visual("shield") == shield, "Refreshing equipment recreated the shield.")
	actor.set_equipment(SWORD_ONLY)
	_check(rig.get_equipped_visual("shield") == null, "Removing shield left it equipped.")
	_check(rig.get_equipped_visual("weapon") == sword, "Removing shield removed or recreated the sword.")
	_check(other.attachment_rig.get_equipped_visual("shield") == other_shield, "Removing one shield affected another character.")
	actor.set_equipment(PAIR)
	var restored_shield: Node2D = rig.get_equipped_visual("shield")
	actor.set_equipment(SHIELD_ONLY)
	_check(rig.get_equipped_visual("weapon") == null, "Removing sword left it equipped.")
	_check(rig.get_equipped_visual("shield") == restored_shield, "Removing sword removed or recreated the shield.")
	actor.set_equipment({})
	_check(rig.get_equipped_visual("shield") == null, "Unequipping all equipment retained the shield.")


func _test_scene(scene_path: String, is_map: bool) -> void:
	var packed := load(scene_path) as PackedScene
	_check(packed != null, "Could not load game scene: " + scene_path)
	if packed == null:
		return
	var container := packed.instantiate()
	root.add_child(container)
	var game: Variant = container.get_node("Combat") if is_map else container
	game.set_physics_process(false)
	await process_frame
	var actor: ActorSprite = game.actor_sprites.get(game.player.entity_id)
	_check(actor != null, scene_path + " did not spawn its player.")
	if actor == null:
		container.free()
		return
	actor.set_process(false)
	actor.animated_sprite.pause()
	game.player.give_and_equip("Iron Longsword")
	game.player.give_and_equip(106)
	game._refresh_player_actor_from_player()
	var rig = actor.attachment_rig
	var live_sword: Node2D = rig.get_equipped_visual("weapon")
	var live_shield: Node2D = rig.get_equipped_visual("shield")
	_check(actor.skin_id == "peasant", scene_path + " used a combined equipment skin.")
	_check(live_sword != null and live_shield != null, scene_path + " inventory equip did not show both items.")
	var preview: Variant = game.sprite_preview
	preview.set_process(false)
	preview.actor.set_process(false)
	var peasant_index: int = preview.skin_ids.find("peasant")
	_check(peasant_index >= 0, scene_path + " preview has no peasant.")
	_check(preview.shield_picker is OptionButton, scene_path + " F7 preview has no shield picker.")
	if peasant_index >= 0:
		preview.show_preview()
		preview._select_skin(peasant_index)
		preview.equipment_picker.select(1)
		preview._change_equipment(1)
		preview.shield_picker.select(1)
		preview._change_shield(1)
		_check(preview.actor.attachment_rig.get_equipped_visual("weapon") != null, scene_path + " preview shield selection lost its sword.")
		_check(preview.actor.attachment_rig.get_equipped_visual("shield") != null, scene_path + " preview did not equip the selected shield.")
		_check(rig.get_equipped_visual("weapon") == live_sword and rig.get_equipped_visual("shield") == live_shield, scene_path + " preview changed the live player's equipment.")
		preview.shield_picker.select(0)
		preview._change_shield(0)
		_check(preview.actor.attachment_rig.get_equipped_visual("shield") == null, scene_path + " preview did not remove its shield.")
		_check(preview.actor.attachment_rig.get_equipped_visual("weapon") != null, scene_path + " preview shield removal lost its sword.")
		_check(game.player.equipment["shield"].get("name", "") == SHIELD_NAME, scene_path + " preview mutated the live shield slot.")
		preview.hide_preview()
	game.player.unequip_slot("shield")
	game._refresh_player_actor_from_player()
	_check(rig.get_equipped_visual("shield") == null, scene_path + " unequip did not remove the gameplay shield.")
	_check(rig.get_equipped_visual("weapon") == live_sword, scene_path + " unequip removed or recreated the gameplay sword.")
	container.free()
	await process_frame
