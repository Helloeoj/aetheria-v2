extends SceneTree
## Focused equipment-attachment contract checks.
## Godot --headless --path godot_client --script res://scripts/dev_tools/attachment_smoke.gd

const SOCKET_NAMES := ["right_hand", "left_hand", "head", "chest", "waist", "back"]
const SWORD_EQUIPMENT := {"weapon": {"name": "Iron Longsword"}}

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var actor := _make_actor("attachment_test")
	var other := _make_actor("attachment_other")
	await process_frame
	_test_pose_coverage(actor)
	_test_equipment(actor, other)
	_test_lifecycle(actor)
	actor.free()
	other.free()
	if failures.is_empty():
		print("[Attachment smoke] PASS: %d checks, all 72 peasant poses, independent equipment and lifecycle." % checks)
		quit(0)
	else:
		printerr("[Attachment smoke] FAIL: %d of %d checks failed." % [failures.size(), checks])
		quit(1)


func _make_actor(id: String) -> ActorSprite:
	var actor := ActorSprite.new().configure(Vector2(32, 32), Color.BLUE, id)
	root.add_child(actor)
	actor.set_process(false)
	actor.set_skin("peasant")
	actor.animated_sprite.pause()
	return actor


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("[Attachment smoke] " + label)


func _test_pose_coverage(actor: ActorSprite) -> void:
	var rig = actor.attachment_rig
	_check(rig is Skeleton2D, "Peasant equipment rig must be a Skeleton2D.")
	_check(rig.get_parent() == actor.animated_sprite, "Rig must inherit the character visual's transform and tint.")
	_check(rig.get_bone_count() > 0, "Peasant rig has no registered Bone2D nodes.")
	var visited: Dictionary = {}
	for direction: String in CharacterSpriteLibrary.DIRECTIONS:
		for action: String in ["idle", "walk"]:
			var animation := CharacterSpriteLibrary.animation_name(action, direction)
			actor.animated_sprite.play(animation)
			actor.animated_sprite.pause()
			# Do not call sync_pose: these checks exercise the real sprite signals.
			for frame in actor.animated_sprite.sprite_frames.get_frame_count(animation):
				actor.animated_sprite.frame = frame
				var texture := actor.animated_sprite.sprite_frames.get_frame_texture(animation, frame)
				var path := texture.resource_path
				visited[path] = true
				_check(rig.current_frame_path == path, "%s frame %d did not synchronize its attachment pose." % [animation, frame])
				for socket_name: String in SOCKET_NAMES:
					var socket = rig.get_socket(socket_name)
					_check(socket is Marker2D, "%s has no %s marker." % [path, socket_name])
					var point := _pose_point(rig.current_pose, socket_name)
					_check(point.size() >= 2, "%s has no authored %s coordinates." % [path, socket_name])
					if socket == null or point.size() < 2:
						continue
					var expected_local := Vector2(float(point[0]), float(point[1])) - texture.get_size() * 0.5 + actor.animated_sprite.offset
					var expected_global := actor.animated_sprite.to_global(expected_local)
					_check(socket.global_position.distance_to(expected_global) < 0.01, "%s/%s is offset from its PNG-space anchor." % [path, socket_name])
	_check(visited.size() == 72, "Expected 72 distinct peasant poses; checked %d." % visited.size())
	# Both idle clips use frame 0. Changing only the animation must refresh poses.
	actor.animated_sprite.play(&"idle_south")
	actor.animated_sprite.pause()
	var south_path: String = rig.current_frame_path
	actor.animated_sprite.play(&"idle_north")
	actor.animated_sprite.pause()
	_check(rig.current_frame_path != south_path, "Changing facing at frame 0 left the old socket pose.")
	_check(rig.current_frame_path == actor.animated_sprite.sprite_frames.get_frame_texture(&"idle_north", 0).resource_path, "Animation-only change did not select the north pose.")


func _pose_point(pose: Dictionary, socket_name: String) -> Array:
	# Accept direct or nested coordinates while the data schema is extensible.
	var sockets: Dictionary = pose.get("sockets", pose)
	var value: Variant = sockets.get(socket_name, [])
	if value is Dictionary:
		value = value.get("position", [])
	return value if value is Array else []


func _test_equipment(actor: ActorSprite, other: ActorSprite) -> void:
	# The real sword now has directional textures. Resource sharing is checked
	# at the same facing; pose coverage above deliberately ends facing north.
	for subject: ActorSprite in [actor, other]:
		subject.animated_sprite.play(&"idle_south")
		subject.animated_sprite.pause()
	actor.set_equipment(SWORD_EQUIPMENT)
	other.set_equipment(SWORD_EQUIPMENT)
	var rig = actor.attachment_rig
	var sword: Node2D = rig.get_equipped_visual("weapon")
	var other_sword: Node2D = other.attachment_rig.get_equipped_visual("weapon")
	_check(actor.skin_id == "peasant", "Equipping a sword replaced the character's skin.")
	_check(sword != null, "Equipped Iron Longsword has no independent visual.")
	_check(other_sword != null and other_sword != sword, "Two actors must own independent equipment instances.")
	if sword == null or other_sword == null:
		return
	_check(rig.get_socket("right_hand").is_ancestor_of(sword), "Sword is not attached beneath the right-hand socket.")
	var first_texture := _find_texture(sword)
	_check(first_texture != null and first_texture == _find_texture(other_sword), "Independent swords should share the same texture resource.")
	for _repetition in 20:
		actor.set_equipment(SWORD_EQUIPMENT)
	_check(rig.get_equipped_visual("weapon") == sword, "Repeated equipment refresh recreated the sword.")
	other.set_equipment({})
	_check(other.attachment_rig.get_equipped_visual("weapon") == null, "Unequipping did not clear the equipment lookup.")
	_check(rig.get_equipped_visual("weapon") == sword, "Unequipping one actor removed another actor's sword.")
	other.set_equipment(SWORD_EQUIPMENT)
	_check(other.attachment_rig.get_equipped_visual("weapon") != sword, "Re-equipping reused another actor's instance.")
	actor.set_socket_debug(true)
	_check(rig.debug_sockets, "Socket debug display could not be enabled.")
	actor.set_socket_debug(false)
	_check(not rig.debug_sockets, "Socket debug display could not be disabled.")


func _find_texture(node: Node) -> Texture2D:
	if node is Sprite2D and node.texture != null:
		return node.texture
	for child in node.get_children():
		var texture := _find_texture(child)
		if texture != null:
			return texture
	return null


func _test_lifecycle(actor: ActorSprite) -> void:
	var rig = actor.attachment_rig
	actor.set_skin("peasant")
	actor.cancel_action()
	actor.face_direction(Vector2.DOWN)
	actor.animated_sprite.pause()
	var hand: Marker2D = rig.get_socket("right_hand")
	var sword: Node2D = rig.get_equipped_visual("weapon")
	if hand == null or sword == null:
		_check(false, "Lifecycle checks require an equipped right-hand sword.")
		return
	var hand_before := hand.global_position
	var sword_before := sword.global_position
	actor.position += Vector2(31, 19)
	_check(hand.global_position.is_equal_approx(hand_before + Vector2(31, 19)), "Hand socket did not follow actor translation.")
	_check(sword.global_position.is_equal_approx(sword_before + Vector2(31, 19)), "Sword did not follow actor translation.")
	var original_sword_scale := sword.global_scale
	actor.scale = Vector2(2, 2)
	# The hierarchy check plus this distance check catches accidental top-level nodes.
	_check(hand.global_position.distance_to(actor.global_position) > 0.1, "Scaled socket collapsed to the actor origin.")
	_check(sword.global_scale.is_equal_approx(original_sword_scale * 2.0), "Sword did not inherit the actor's 2x scale.")
	actor.scale = Vector2.ONE
	actor.play_attack(Vector2.DOWN)
	actor.animated_sprite.pause()
	var start := sword.global_position
	actor._process(ActorSprite.FALLBACK_ATTACK_SECONDS * 0.5)
	# CharacterVisual.position is in actor coordinates, so compare directly.
	var displacement := actor.animated_sprite.position
	_check(displacement.length() > 0.1, "Peasant fallback attack did not lunge.")
	_check(sword.global_position.is_equal_approx(start + displacement), "Sword separated from the hand during the fallback lunge.")
	actor.cancel_action()
	_check(actor.animated_sprite.position.is_zero_approx(), "Cancelling attack did not reset the visual displacement.")
	actor.play_hurt()
	actor._process(ActorSprite.HURT_FLASH_SECONDS * 0.5)
	_check(actor.animated_sprite.modulate.g < 1.0, "Hurt flash did not reach the parent visual.")
	_check(actor.animated_sprite.is_ancestor_of(sword) and sword.modulate == Color.WHITE, "Sword would not inherit the parent hurt/death tint.")
	actor.set_dead(true)
	_check(not actor.animated_sprite.is_playing(), "Dead peasant continued animating.")
	_check(actor.animated_sprite.position.is_zero_approx(), "Death retained attack displacement.")
	_check(actor.animated_sprite.modulate == Color(0.55, 0.55, 0.55), "Death tint did not reach the parent visual.")
	_check(rig.get_equipped_visual("weapon") == sword, "Death unexpectedly replaced equipment.")
	actor.set_dead(false)
	actor.animated_sprite.pause()
	_check(actor.animated_sprite.modulate == Color.WHITE, "Reviving did not clear the death tint.")
	actor.set_skin("golem_titan")
	actor.animated_sprite.pause()
	_check(not rig.visible, "Unsupported skin left the peasant rig visible.")
	actor.set_skin("peasant")
	actor.animated_sprite.pause()
	_check(rig.visible, "Returning to peasant did not restore the rig.")
	_check(rig.get_equipped_visual("weapon") != null, "Returning to peasant lost equipped sword state.")
	actor.set_equipment({})
	_check(rig.get_equipped_visual("weapon") == null, "Removing equipment retained an equipped sword.")
