extends SceneTree
## Run with Godot --headless --path godot_client --script res://scripts/dev_tools/sprite_integration_smoke.gd
## Import the project first with --headless --editor --import.

const SCREEN_DIRECTIONS := {
	"south": Vector2(0, 1), "south-east": Vector2(1, 1),
	"east": Vector2(1, 0), "north-east": Vector2(1, -1),
	"north": Vector2(0, -1), "north-west": Vector2(-1, -1),
	"west": Vector2(-1, 0), "south-west": Vector2(-1, 1)
}

var checks := 0
var failures: Array[String] = []
var catalog: Dictionary
var skins: Dictionary
var directions: Array
var capture_directory := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture_directory = argument.trim_prefix("--capture-dir=")
	if not capture_directory.is_empty():
		_check(DisplayServer.get_name() != "headless", "Screenshot capture requires a graphical Godot run.")
		DirAccess.make_dir_recursive_absolute(capture_directory)
	catalog = CharacterSpriteLibrary.get_catalog()
	skins = catalog.get("skins", {})
	directions = catalog.get("directions", [])
	_test_catalog()
	_test_actor()
	await _test_scene("res://scenes/EastOutskirtsLayered.tscn", true)
	await _test_scene("res://scenes/main.tscn", false)
	if failures.is_empty():
		print("[Sprite smoke] PASS: %d checks, %d skins, 8 directions, both game scenes." % [checks, skins.size()])
		quit(0)
	else:
		printerr("[Sprite smoke] FAIL: %d of %d checks failed." % [failures.size(), checks])
		quit(1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("[Sprite smoke] " + label)


func _test_catalog() -> void:
	_check(int(catalog.get("schema_version", 0)) == 1, "Catalog schema must be version 1.")
	_check(not skins.is_empty(), "Supplied catalog must contain character skins.")
	_check(directions.size() == 8, "Catalog must describe eight directions.")
	var authored_frame_count := 0
	for skin_id: String in skins:
		var skin: Dictionary = skins[skin_id]
		var rotations: Dictionary = skin.get("rotations", {})
		var animations: Dictionary = skin.get("animations", {})
		var frames := CharacterSpriteLibrary.get_frames(skin_id)
		_check(frames != null, skin_id + " has no SpriteFrames resource.")
		if frames == null:
			continue
		for direction: String in SCREEN_DIRECTIONS:
			var rotation_path := String(rotations.get(direction, ""))
			_check(ResourceLoader.exists(rotation_path, "Texture2D"), "%s/%s rotation is missing." % [skin_id, direction])
			for role: String in ["idle", "walk"]:
				var animation := StringName(role + "_" + direction)
				_check(frames.has_animation(animation), "%s has no %s." % [skin_id, animation])
				if not frames.has_animation(animation):
					continue
				var role_data: Dictionary = animations.get(role, {})
				var authored: Array = role_data.get("directions", {}).get(direction, [])
				_check(frames.get_frame_count(animation) == maxi(1, authored.size()), "%s/%s has the wrong frame count." % [skin_id, animation])
				if frames.get_frame_count(animation) > 0:
					var expected := String(authored[0]) if not authored.is_empty() else rotation_path
					_check(frames.get_frame_texture(animation, 0).resource_path == expected, "%s/%s uses a different facing instead of the exact authored rotation." % [skin_id, animation])
		for role: String in animations:
			var role_data: Dictionary = animations[role]
			var authored_directions: Dictionary = role_data.get("directions", {})
			for direction: String in authored_directions:
				var paths: Array = authored_directions[direction]
				var animation := StringName(role + "_" + direction)
				_check(not paths.is_empty(), "%s/%s has an empty authored clip." % [skin_id, animation])
				_check(frames.has_animation(animation), "%s/%s authored clip was not built." % [skin_id, animation])
				if frames.has_animation(animation):
					_check(frames.get_frame_count(animation) == paths.size(), "%s/%s lost authored frames." % [skin_id, animation])
					_check(is_equal_approx(frames.get_animation_speed(animation), float(role_data.get("fps", 10.0))), "%s/%s has the wrong playback rate." % [skin_id, animation])
					_check(frames.get_animation_loop(animation) == bool(role_data.get("loop", role != "attack")), "%s/%s has the wrong loop setting." % [skin_id, animation])
				for path: String in paths:
					authored_frame_count += 1
					_check(ResourceLoader.exists(path, "Texture2D"), "Authored frame is missing: " + path)
				if frames.has_animation(animation):
					for index in mini(paths.size(), frames.get_frame_count(animation)):
						_check(frames.get_frame_texture(animation, index).resource_path == String(paths[index]), "%s/%s frame %d is out of order." % [skin_id, animation, index])
	for monster_name: String in catalog.get("monster_skins", {}):
		var skin_id := CharacterSpriteLibrary.skin_for_monster(monster_name)
		_check(skins.has(skin_id), "Monster mapping has no imported skin: " + monster_name)
	_check(skins.has(CharacterSpriteLibrary.default_player_skin()), "Default player skin is missing.")
	_check(skins.has(CharacterSpriteLibrary.skin_for_player(true)), "Equipped player base skin is missing.")
	print("[Sprite smoke] Catalog verified: %d skins, %d authored animation frames." % [skins.size(), authored_frame_count])


func _test_actor() -> void:
	var actor := ActorSprite.new().configure(Vector2(32, 32), Color.BLUE, "sprite_smoke")
	root.add_child(actor)
	actor.set_process(false)
	for skin_id: String in skins:
		actor.set_skin(skin_id)
		_check(actor.skin_id == skin_id, "Actor could not select " + skin_id)
		_check(actor.animated_sprite != null, skin_id + " has no visible AnimatedSprite2D.")
		_check(actor.get_health_bar_offset().y < 0.0, skin_id + " health bar must sit above the feet.")
		if actor.animated_sprite == null:
			continue
		for direction: String in SCREEN_DIRECTIONS:
			var vector: Vector2 = SCREEN_DIRECTIONS[direction]
			actor._process(2.0)
			actor.update_visual_motion(Vector2.ZERO)
			actor.face_direction(vector)
			_check(actor.facing == direction, "%s facing resolver did not choose %s." % [skin_id, direction])
			_check(actor.animated_sprite.animation == StringName("idle_" + direction), "%s did not idle toward %s." % [skin_id, direction])
			actor.update_visual_motion(vector)
			_check(actor.animated_sprite.animation == StringName("walk_" + direction), "%s did not walk toward %s." % [skin_id, direction])
			actor.update_visual_motion(Vector2.ZERO)
			actor.play_attack(vector)
			var expected := StringName("attack_" + direction)
			if not actor.animated_sprite.sprite_frames.has_animation(expected):
				expected = StringName("idle_" + direction)
			_check(actor.animated_sprite.animation == expected, "%s attack toward %s used another direction." % [skin_id, direction])
			_check(actor.facing == direction, "%s attack changed its requested facing." % skin_id)
		actor._process(2.0)
		var original_modulate := actor.animated_sprite.modulate
		actor.set_targeted(true)
		_check(actor.targeted, skin_id + " did not become targeted.")
		_check(actor.animated_sprite.modulate == original_modulate, skin_id + " target marker tinted the character artwork.")
		actor.set_targeted(false)
		_check(not actor.targeted, skin_id + " target marker did not clear.")
		actor.play_hurt()
		actor._process(1.0)
		actor.set_dead(true)
		_check(actor.dead, skin_id + " did not enter death state.")
		_check(not actor.animated_sprite.is_playing(), skin_id + " kept animating while dead.")
		actor.set_dead(false)
		_check(not actor.dead, skin_id + " did not recover when revived.")
	actor.free()
	print("[Sprite smoke] Actor facings, movement, attack fallbacks, targeting, and death verified.")


func _test_scene(scene_path: String, is_map: bool) -> void:
	var scene := load(scene_path) as PackedScene
	_check(scene != null, "Game scene could not be loaded: " + scene_path)
	if scene == null:
		return
	var container := scene.instantiate()
	root.get_node("SceneTravel").set("_player",null)
	root.add_child(container)
	var game: Variant = container.get_node("Combat") if is_map else container
	game.set_physics_process(false)
	await process_frame
	while is_map and (game.grid_adapter == null or not game.grid_adapter.completed):
		await physics_frame
	var player_sprite: ActorSprite = game.actor_sprites.get(game.player.entity_id)
	_check(player_sprite != null, scene_path + " did not spawn the player sprite.")
	if player_sprite == null:
		container.free()
		return
	player_sprite.set_process(false)
	_check(player_sprite.skin_id == CharacterSpriteLibrary.default_player_skin(), scene_path + " has the wrong default player skin.")
	var player_actor: CombatActor = game.combat.actors.get(game.player.entity_id)
	_check(player_actor != null, scene_path + " did not register the player for combat.")
	if player_actor == null:
		container.free()
		return
	var preview: Variant = game.sprite_preview
	_check(preview != null and preview.skin_ids.size() == skins.size(), scene_path + " viewer does not list every imported skin.")
	if preview != null:
		preview.set_process(false)
		preview.actor.set_process(false)
		_press_key(KEY_F7)
		_check(preview.visible, scene_path + " F7 did not open the viewer through viewport input.")
		_press_key(KEY_F7, true)
		_check(preview.visible, scene_path + " F7 autorepeat closed the viewer.")
		game.movement_controller.holding.right = true
		var paused_position := player_sprite.position
		game._physics_process(1.0)
		_check(player_sprite.position == paused_position, scene_path + " simulation moved while the sprite viewer was open.")
		var peasant_index: int = preview.skin_ids.find("peasant")
		preview._select_skin(peasant_index)
		preview.equipment_picker.select(1)
		preview._change_equipment(1)
		_check(preview.actor.skin_id == "peasant" and preview.actor.attachment_rig.get_equipped_visual("weapon") != null, scene_path + " viewer equipment picker did not attach a separate sword.")
		_check(player_sprite.attachment_rig.get_equipped_visual("weapon") == null, scene_path + " preview equipment changed the actual player's gear.")
		preview.socket_check.button_pressed = true
		_check(preview.actor.attachment_rig.debug_sockets, scene_path + " viewer did not enable the attachment skeleton overlay.")
		preview.equipment_picker.select(0)
		preview._change_equipment(0)
		_check(preview.actor.attachment_rig.get_equipped_visual("weapon") == null, scene_path + " viewer equipment picker did not remove the sword.")
		preview.socket_check.button_pressed = false
		for index in preview.skin_ids.size():
			preview.action_picker.select(0)
			preview._select_skin(index)
			_check(preview.actor.skin_id == preview.skin_ids[index], "Viewer failed to select " + preview.skin_ids[index])
			for direction_index in preview.DIRECTIONS.size():
				preview.actor._process(2.0)
				preview.direction_picker.select(direction_index)
				preview._change_direction(direction_index)
				_check(preview.actor.facing == preview.DIRECTIONS[direction_index], "Viewer selected the wrong direction for " + preview.actor.skin_id)
			preview.action_picker.select(1)
			preview._change_action(1)
			preview._process(0.1)
			_check(String(preview.actor.animated_sprite.animation).begins_with("walk_"), "Viewer could not preview walking for " + preview.actor.skin_id)
			preview.action_picker.select(2)
			preview._change_action(2)
			var attack := StringName("attack_" + String(preview.actor.facing))
			var expected := attack if preview.actor.animated_sprite.sprite_frames.has_animation(attack) else StringName("idle_" + String(preview.actor.facing))
			_check(preview.actor.animated_sprite.animation == expected, "Viewer could not preview the matching attack for " + preview.actor.skin_id)
			preview.action_picker.select(0)
			preview._change_action(0)
			preview.direction_picker.select(2)
			preview._change_direction(2)
			_check(preview.actor.facing == "east" and preview.actor.animated_sprite.animation == &"idle_east", "Viewer could not immediately switch attack to idle and turn for " + String(preview.actor.skin_id))
			preview.action_picker.select(2)
			preview._change_action(2)
			preview.direction_picker.select(4)
			preview.action_picker.select(1)
			preview._change_action(1)
			_check(preview.actor.facing == "north" and preview.actor.animated_sprite.animation == &"walk_north", "Viewer could not immediately switch attack to walking and turn for " + String(preview.actor.skin_id))
		if is_map and not capture_directory.is_empty():
			var sword_index: int = preview.skin_ids.find("peasant")
			if sword_index >= 0:
				preview.skin_list.select(sword_index)
				preview.action_picker.select(0)
				preview.direction_picker.select(1)
				preview.actor._process(2.0)
				preview._select_skin(sword_index)
				preview.equipment_picker.select(1)
				preview._change_equipment(1)
				for target_check: CheckButton in preview.find_children("*", "CheckButton", true, false):
					target_check.button_pressed = true
			await _capture("sprite-viewer.png")
		_press_key(KEY_ESCAPE)
		_check(not preview.visible, scene_path + " Escape did not close the viewer through viewport input.")
		_check(game.movement_controller.get_move_vector().is_zero_approx(), scene_path + " viewer close left movement keys held.")
		_press_key(KEY_F7)
		_check(preview.visible, scene_path + " F7 did not reopen the viewer.")
		_press_key(KEY_F7)
		_check(not preview.visible, scene_path + " F7 did not close the viewer.")
		var titan_index: int = preview.skin_ids.find("golem_titan")
		_check(titan_index >= 0, "Viewer cannot select the Golem Titan.")
		if titan_index >= 0:
			_press_key(KEY_F7)
			preview.skin_list.select(titan_index)
			preview._select_skin(titan_index)
			var before_spawn_count: int = game.actor_sprites.size()
			preview._spawn_selected()
			var spawned_id := "monster_%d" % (int(game.next_monster_number) - 1)
			var spawned_sprite: ActorSprite = game.actor_sprites.get(spawned_id)
			_check(not preview.visible and game.actor_sprites.size() == before_spawn_count + 1, scene_path + " viewer spawn did not close and create a creature.")
			_check(spawned_sprite != null and spawned_sprite.skin_id == "golem_titan", scene_path + " viewer spawned the wrong selected creature.")
			game._despawn_monster(spawned_id)
	_press_key(KEY_F5)
	_check(game.spawn_menu.visible, scene_path + " F5 did not open the monster menu.")
	_press_key(KEY_PAGEDOWN)
	_check(game.spawn_menu.page_index == 1, scene_path + " spawn menu did not advance a page.")
	await process_frame
	_press_key(KEY_PAGEUP)
	_check(game.spawn_menu.page_index == 0, scene_path + " spawn menu did not return to its first page.")
	for index in 20:
		_press_key(KEY_PAGEDOWN)
	_check(game.spawn_menu.page_index == ceili(float(game.spawn_menu.db.size()) / game.spawn_menu.PAGE_SIZE) - 1, scene_path + " spawn menu did not clamp to its final page.")
	await process_frame
	if is_map and not capture_directory.is_empty():
		await _capture("sprite-spawn-menu.png")
	_press_key(KEY_F5)
	_check(not game.spawn_menu.visible, scene_path + " F5 did not close the monster menu.")
	var movement_start := Vector2(player_actor.x,player_actor.y)
	if game.world.grid != null:
		var grid: HiddenGrid = game.world.grid
		var base := grid.cell_at(movement_start)
		var found := false
		for y in range(-8,9):
			for x in range(-8,9):
				var cell := base+Vector2i(x,y)
				var clear := grid.walkable(cell)
				for step: Vector2i in HiddenGrid.DIRECTIONS:
					clear = clear and grid.connected(cell,cell+step)
				if clear and not grid.path(movement_start,grid.center(cell)).is_empty():
					movement_start = grid.center(cell)
					found = true
					break
			if found: break
		_check(found,scene_path + " has a reachable open fixture for all eight facings.")
	for direction: String in SCREEN_DIRECTIONS:
		# Each facing starts at rest: ordinary turns now wait for tile arrival.
		player_actor.x = movement_start.x
		player_actor.y = movement_start.y
		game.player.x = movement_start.x
		game.player.y = movement_start.y
		game.world.grid_travellers.erase(player_actor.entity_id)
		game._update_sprite_position(player_actor.entity_id)
		var vector: Vector2 = SCREEN_DIRECTIONS[direction]
		game.movement_controller.holding = {"up": vector.y < 0.0, "down": vector.y > 0.0, "left": vector.x < 0.0, "right": vector.x > 0.0}
		var start := player_sprite.position
		game._physics_process(1.0 / 120.0)
		var displacement := player_sprite.position - start
		_check(not displacement.is_zero_approx(), "%s player could not move %s from its starting area." % [scene_path, direction])
		_check(player_sprite.facing == direction, "%s moving %s faces the wrong way." % [scene_path, direction])
		_check(player_sprite.animated_sprite.animation == StringName("walk_" + direction), "%s moving %s ends the frame without its walk animation." % [scene_path, direction])
	game._reset_held_movement()
	for frame in range(60):
		game._physics_process(1.0 / 120.0)
	player_sprite._process(1.0)
	_check(String(player_sprite.animated_sprite.animation).begins_with("idle_"), scene_path + " did not settle to idle after movement stopped.")
	game.player.set_skill_level("attack",100)
	game.player.give_and_equip("Iron Longsword")
	game._physics_process(0.0)
	_check(player_sprite.skin_id == CharacterSpriteLibrary.default_player_skin(), scene_path + " equipping changed the player's base artwork.")
	_check(player_sprite.attachment_rig.get_equipped_visual("weapon") != null, scene_path + " did not attach the independent Iron Longsword.")
	game.player.unequip_slot("weapon")
	game._physics_process(0.0)
	_check(player_sprite.skin_id == CharacterSpriteLibrary.default_player_skin(), scene_path + " did not remove the sword appearance after unequipping.")
	_check(player_sprite.attachment_rig.get_equipped_visual("weapon") == null, scene_path + " unequipping left a weapon attached.")
	var database: Dictionary = game._active_monster_database()
	_check(not database.is_empty(), scene_path + " has no active spawnable monsters.")
	for monster_id: int in database:
		game.spawn_monster_by_id(monster_id)
		var entity_id := "monster_%d" % (int(game.next_monster_number) - 1)
		var monster_sprite: ActorSprite = game.actor_sprites.get(entity_id)
		var template: Dictionary = database[monster_id]
		_check(monster_sprite != null, "Monster did not spawn: " + String(template.get("name", "")))
		if monster_sprite != null:
			_check(monster_sprite.skin_id == CharacterSpriteLibrary.skin_for_monster(String(template.get("name", ""))), "Monster spawned with the wrong skin: " + String(template.get("name", "")))
		game._despawn_monster(entity_id)
		_check(not game.actor_sprites.has(entity_id) and not game.combat.actors.has(entity_id), "Despawn left a monster in the active world: " + entity_id)
	await create_timer(0.4).timeout
	if not database.is_empty():
		game.spawn_monster_by_id(int(database.keys()[0]))
		var entity_id := "monster_%d" % (int(game.next_monster_number) - 1)
		var monster_sprite: ActorSprite = game.actor_sprites.get(entity_id)
		var monster_actor: CombatActor = game.combat.actors.get(entity_id)
		game._set_target(entity_id)
		_check(monster_sprite.targeted, scene_path + " did not display its target marker.")
		monster_actor.x = player_actor.x + 1.0
		monster_actor.y = player_actor.y
		monster_actor.hp = 10000
		monster_actor.max_hp = 10000
		game._update_sprite_position(entity_id)
		player_actor.attack_cooldown_seconds = 0.0
		player_actor.requires_line_of_sight = false
		player_actor.attack_style = "slash"
		player_actor.min_damage = 1
		player_actor.max_damage = 1
		player_actor.attack_range = 2.0
		game._start_auto_chase() # Target selection alone deliberately does not attack.
		game.combat.random.seed = 42
		var events: Array[Dictionary] = game.combat.process_realtime(game.world, 1.0 / 60.0)
		var attack_occurred := false
		for event: Dictionary in events:
			if String(event.get("type", "")) == "entity_hit" and String(event.get("attacker_id", "")) == game.player.entity_id:
				attack_occurred = true
		_check(attack_occurred, scene_path + " combat did not produce a player attack event.")
		game._handle_combat_events(events)
		_check(player_sprite.facing == "east", scene_path + " combat attack did not face its target.")
		if is_map and not capture_directory.is_empty():
			await _capture("sprite-gameplay.png")
		var death_events: Array[Dictionary] = [{"type": "entity_died", "entity_id": entity_id}]
		game._handle_combat_events(death_events)
		_check(not game.actor_sprites.has(entity_id) and not game.combat.actors.has(entity_id), scene_path + " death did not remove the monster from the active world.")
		_check(game.player.current_target.is_empty(), scene_path + " death left a stale target.")
		_check(monster_sprite.dead and monster_sprite.collision_layer == 0 and monster_sprite.collision_mask == 0, scene_path + " death fade retained an active collision body.")
		var fade_deadline := Time.get_ticks_msec()+2000
		while is_instance_valid(monster_sprite) and Time.get_ticks_msec() < fade_deadline:
			await process_frame
		_check(not is_instance_valid(monster_sprite), scene_path + " death fade did not free the monster sprite.")
	container.free()
	await process_frame
	print("[Sprite smoke] Game scene verified: " + scene_path)


func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	var output_path := capture_directory.path_join(filename)
	_check(capture != null and not capture.is_empty(), "Viewport screenshot was empty: " + filename)
	if capture != null and not capture.is_empty():
		_check(capture.save_png(output_path) == OK, "Could not write screenshot: " + output_path)


func _press_key(code: Key, echo: bool = false) -> void:
	var press := InputEventKey.new()
	press.keycode = code
	press.physical_keycode = code
	press.pressed = true
	press.echo = echo
	root.push_input(press)
	var release := InputEventKey.new()
	release.keycode = code
	release.physical_keycode = code
	release.pressed = false
	root.push_input(release)
