extends SceneTree
## Integration checks against the real ActorSprite, inventory and game scenes.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("[Fitted equipment] " + label)

func _run() -> void:
	await process_frame
	FittedEquipmentLibrary.initialize()
	var actor := ActorSprite.new().configure(Vector2(32,32), Color.BLUE, "fitted_smoke")
	root.add_child(actor)
	actor.set_process(false)
	actor.set_skin("peasant")
	var game_data := root.get_node("GameData")
	var player: Variant = load("res://scripts/player_state.gd").new("Fitted smoke")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CharacterAttachmentRig.EQUIPMENT_PATH))
	var poses := 0
	for item: Dictionary in FittedEquipmentLibrary.item_data.values():
		var name := String(item.name)
		var slot := String(item.slot)
		_check(not game_data.get_item_by_name(name).is_empty(), name + " is absent from the real gameplay catalog")
		_check(catalog.items.has(name), name + " is absent from the visual registry")
		player.give_and_equip(name)
		var inventory_slot := "ring1" if slot == "ring" else slot
		_check(String(player.equipment[inventory_slot].get("name", "")) == name, name + " could not be equipped through PlayerState")
		player.unequip_slot(inventory_slot)
		actor.set_equipment({slot:{"name":name}})
		var node := actor.attachment_rig.get_equipped_visual(slot)
		if slot == "ring":
			_check(node == null, "Ring created a visible node")
			continue
		_check(node is FittedEquipmentVisual, name + " did not use an independent fitted item scene")
		if node == null:
			continue
		for direction: String in CharacterSpriteLibrary.DIRECTIONS:
			for action: String in ["idle", "walk"]:
				var animation := CharacterSpriteLibrary.animation_name(action, direction)
				actor.animated_sprite.play(animation)
				actor.animated_sprite.pause()
				for frame in actor.animated_sprite.sprite_frames.get_frame_count(animation):
					actor.animated_sprite.frame = frame
					poses += 1
					_check(node.current_facing == direction, name + " has a stale facing")
					_check(not node.part_sprites.is_empty(), name + " has no independent parts")
					for sprite: Sprite2D in node.part_sprites:
						_check(sprite.texture != null, name + " has a missing texture")
						_check(sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, name + " lost pixel filtering")
					if slot in ["weapon", "shield"]:
						var socket_name := "right_hand" if slot == "weapon" else "left_hand"
						_check(actor.attachment_rig.get_socket(socket_name).is_ancestor_of(node), name + " attached to the wrong hand")
						_check(node.part_bones[0].global_position.distance_to(node.global_position) < 0.01, name + " grip moved away from its live hand socket")
					if slot in ["head", "chest", "legs"]:
						_check(actor.animated_sprite.self_modulate.a == 0.0, name + " left the robe/hair source visible")
	actor.set_equipment({})
	_check(actor.animated_sprite.self_modulate.a == 1.0, "Unequipping armor did not restore original artwork")
	for material: String in ["Bronze", "Iron", "Steel"]:
		var loadout := {}
		for suffix: String in ["Helmet", "Platebody", "Platelegs", "Cape", "Necklace", "Ring"]:
			var definition: Dictionary = game_data.get_item_by_name(material + " " + suffix)
			loadout[String(definition.slot)] = definition
		loadout.weapon = game_data.get_item_by_name(material + " Longsword")
		loadout.shield = game_data.get_item_by_name("Adamantite Kiteshield")
		actor.set_equipment(loadout)
		_check(actor.attachment_rig.get_equipped_visual("shield") is EquipmentVisual2D, "Existing adamantite shield path was replaced")
		_check(actor.skin_id == "peasant", "Fitted loadout replaced the character skin")
		var chest := actor.attachment_rig.get_equipped_visual("chest")
		var neck := actor.attachment_rig.get_equipped_visual("neck")
		_check(chest.get_parent() == neck.get_parent() and neck.get_index() > chest.get_index(), "Necklace is behind chest armor")
	actor.free()
	for path: String in ["res://scenes/main.tscn", "res://scenes/EastOutskirtsLayered.tscn"]:
		var scene := (load(path) as PackedScene).instantiate()
		root.add_child(scene)
		var game: Variant = scene.get_node("Combat") if path.contains("EastOutskirts") else scene
		game.set_physics_process(false)
		await process_frame
		var preview: Variant = game.sprite_preview
		preview._select_skin(preview.skin_ids.find("peasant"))
		preview._armor_preset("Bronze")
		_check(preview.actor.attachment_rig.get_equipped_visual("chest") != null, path + " F7 bronze preset failed")
		preview._armor_preset("Iron")
		_check(preview.actor.attachment_rig.get_equipped_visual("legs") != null, path + " F7 iron preset failed")
		preview._armor_preset("Steel")
		_check(preview.actor.attachment_rig.get_equipped_visual("chest") is FittedEquipmentVisual, path + " F7 steel preset failed")
		game.player.give_and_equip("Bronze Platebody")
		game._refresh_player_actor_from_player()
		var live: ActorSprite = game.actor_sprites.get(game.player.entity_id)
		_check(live.attachment_rig.get_equipped_visual("chest") != null, path + " real inventory equip did not display bronze armor")
		scene.free()
		await process_frame
	var report := {"status":"pass" if failures.is_empty() else "fail","checks":checks,"item_pose_checks":poses,"items":FittedEquipmentLibrary.item_data.size(),"errors":failures}
	var out := FileAccess.open("res://data/fitted_equipment_validation.json", FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "))
	print("[Fitted equipment smoke] ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
