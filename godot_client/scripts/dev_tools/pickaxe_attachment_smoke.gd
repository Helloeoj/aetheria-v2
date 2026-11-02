extends SceneTree
## Exercises real attachment registration, facing and existing idle/walk sockets.
const MATERIALS := ["Bronze","Iron","Steel","Blacksteel","Mithril","Adamantite","Runite"]
const DIRECTIONS := ["south","south-east","east","north-east","north","north-west","west","south-west"]
const VECTORS := [Vector2.DOWN,Vector2(1,1),Vector2.RIGHT,Vector2(1,-1),Vector2.UP,Vector2(-1,-1),Vector2.LEFT,Vector2(-1,1)]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		if failures.size() <= 12:
			printerr("[Pickaxe FAIL] ",label)

func _run() -> void:
	create_timer(40).timeout.connect(func() -> void: quit(1))
	var actor := ActorSprite.new().configure(Vector2(32,32),Color.BLUE,"pickaxe_test_only")
	root.add_child(actor)
	actor.set_skin("peasant")
	actor.set_process(false)
	actor.animated_sprite.pause()
	await process_frame
	var game_data := root.get_node("GameData")
	for material: String in MATERIALS:
		var name := material+" Pickaxe"
		actor.set_equipment({"weapon":{"name":name}})
		var held := actor.attachment_rig.get_equipped_visual("weapon")
		check(held is EquipmentVisual2D,name+" is a registered directional attachment")
		check(game_data.get_item_by_name(name).is_empty(),name+" artwork does not invent catalog items")
		if not held is EquipmentVisual2D:
			continue
		check(held.get_parent()==actor.attachment_rig.get_socket("right_hand"),name+" uses the actual right-hand socket")
		check(held.directional_textures.size()==8 and held.grip_positions.size()==8,name+" has eight textures and pivots")
		for index in range(DIRECTIONS.size()):
			var direction: String = DIRECTIONS[index]
			actor.face_direction(VECTORS[index])
			for action: String in ["idle","walk"]:
				var clip := action+"_"+direction
				actor.animated_sprite.animation = clip
				actor.animated_sprite.pause()
				for frame in range(actor.animated_sprite.sprite_frames.get_frame_count(clip)):
					actor.animated_sprite.frame = frame
					actor.attachment_rig.sync_pose()
					var art := held.get_node("Artwork") as Sprite2D
					var socket := actor.attachment_rig.get_socket("right_hand")
					var grip: Vector2 = held.grip_positions[direction]
					var label := name+"/"+direction+"/"+action+"/"+str(frame)
					check(held.visible and held.current_facing==direction and art.texture==held.directional_textures[direction],label+" selects its facing texture")
					check(art.to_global(grip).distance_to(socket.global_position)<0.0001,label+" keeps the grip on the moving hand")
					check(absf(art.global_transform.x.length()-0.75)<0.0001,label+" retains character pixel density")
	actor.set_equipment({})
	check(actor.attachment_rig.get_equipped_visual("weapon")==null,"removing equipment clears the held tool")
	var preview: Variant = load("res://scripts/sprite_preview.gd").new()
	root.add_child(preview)
	preview.set_process(false)
	await process_frame
	for material: String in MATERIALS:
		check(preview.equipment_names.has(material+" Pickaxe"),"existing F7 picker exposes "+material+" Pickaxe")
	preview.queue_free()
	actor.queue_free()
	print("[Pickaxe attachments] ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
