extends SceneTree
## Import first, then run --headless --path godot_client --script res://scripts/dev_tools/goblin_worker_warrior_animation_smoke.gd.
## Optional graphical -- --capture-dir=ABS writes real Camera2D zoom 1/4 lab captures.
## Catches installed packs being omitted from the live catalog or stuck on rotation fallbacks.

const BASE_CATALOG := "res://data/character_sprites.json"
const SKINS := ["goblin_worker", "goblin_warrior"]
const ANIMATED_SKINS := ["goblin_scout", "goblin_worker", "goblin_warrior"]
const DIRECTIONS: Array[String] = ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"]
const VECTORS: Array[Vector2] = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(1, -1), Vector2(0, -1), Vector2(-1, -1), Vector2(-1, 0), Vector2(-1, 1)]
const FRAME_COUNTS := {"idle": 5, "walk": 8, "attack": 12}
const RATES := {"idle": 6.0, "walk": 9.0, "attack": 10.0}
const HEIGHTS := {"goblin_worker": 44.0, "goblin_warrior": 46.0}
const FOOT_Y := {"goblin_worker": 53.0, "goblin_warrior": 52.0}
const MONSTERS := {"goblin_worker": "Goblin Worker", "goblin_warrior": "Goblin Warrior"}
## Original rotation PNG bytes are an independent preservation fixture, not regenerated expectations.
const ORIGINAL_ROTATION_SHA256 := {
	"goblin_worker": [
		"f929dfbd350c4b63f14fe4e7310a27c66b934cfc186fe776be1cc2914964ae26",
		"abf428d082b5afa70d5cb3ef731a0734f9bf56e044bddb82e88e90fd34cf4f27",
		"13638ff50d1fd1705d9fef87a1d5229944b060beecd7a2375ba0f3e0062a7f8d",
		"ab4732386bc0a63fdf6a3771c726fea86938185c130fdfa5b1da94b7781b6e73",
		"1107555f579fff98bb94f58afaea94552d5ee85a78880c712d37c2e201829cba",
		"99998640c003ac54ca5cecc4ac61e323107cb5f30d1628cf7b671db3c4f22ff8",
		"738d8f1d1baa5e5dfd87831306181df5bf07895d42f0de0688a33cdeab8b0514",
		"246d17550cc735412fdcf5e5c0a0529783c5df12b5ad8379919c50ff4731fcba"
	],
	"goblin_warrior": [
		"8ce5059db8a204d60a7d6b300c4f8a7b836ed952536e4b7dfdedb603879ebef9",
		"3e2df748b72b81a30d3ff87f7a720a449328db8335116e74a3b46d127b40e94a",
		"8bb3908a4f6da895c5e404b44f1450045e142a45790c2572df233697546e8fa4",
		"cc5b58af6c145cdeb8a82ebf6933e96ffeada1e2da0b0bc270e7a8de59618d3a",
		"759341085f16d5dc7df4386c3a7695fa2d3977bed027d108fd96db2a4e82eff6",
		"cdb66cae57c1cf15e9e1a43bb844231ad54c15a9972ecae9aabeec9cba51c194",
		"2e0e3d0923988187cf4580a052439053538273aaa83bce7a86508b96cf679361",
		"c0671380342e34d31e9e8f69dae8314939231cba89f1450ca8c012f57716cd59"
	]
}

var checks := 0
var failures: Array[String] = []
var capture_directory := ""
var completions: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("[Worker/Warrior animation smoke] user:// = " + OS.get_user_data_dir())
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture_directory = argument.trim_prefix("--capture-dir=")
	var base: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASE_CATALOG))
	_check(base is Dictionary, "Original base catalog must parse.")
	if base is Dictionary:
		_test_preservation(base)
		var ready_skins: Array[String] = []
		for skin_id: String in SKINS:
			var previous_failures := failures.size()
			_test_clips(skin_id)
			if failures.size() == previous_failures:
				ready_skins.append(skin_id)
		# Exercise complete packs even while another pack is missing; the total stays RED.
		if not ready_skins.is_empty():
			await _test_live_actors(ready_skins)
			await _test_game_integration(ready_skins)
	if not capture_directory.is_empty():
		_check(capture_directory.is_absolute_path(), "Capture directory must be absolute.")
		_check(DisplayServer.get_name() != "headless", "Captures require graphical Godot.")
		if failures.is_empty():
			_check(DirAccess.make_dir_recursive_absolute(capture_directory) == OK, "Could not create capture directory.")
			await _capture_lab()
	if failures.is_empty():
		print("[Worker/Warrior animation smoke] PASS: %d checks; each skin 24 clips/200 frames; live frame advancement and EastOutskirts spawn/motion/combat verified." % checks)
		quit(0)
	else:
		printerr("[Worker/Warrior animation smoke] FAIL: %d of %d checks failed." % [failures.size(), checks])
		quit(1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("[Worker/Warrior animation smoke] " + label)


func _test_preservation(base: Dictionary) -> void:
	var effective := CharacterSpriteLibrary.get_catalog()
	_check(effective.size() == base.size(), "Overlay changed base top-level keys.")
	for key: String in base:
		if key != "skins":
			_check(effective.get(key) == base[key], "Overlay changed base field: " + key)
	var original_skins: Dictionary = base.get("skins", {})
	var effective_skins: Dictionary = effective.get("skins", {})
	_check(effective_skins.size() == original_skins.size(), "Overlay added or removed skins.")
	for skin_id: String in original_skins:
		var original: Dictionary = original_skins[skin_id]
		var skin: Dictionary = effective_skins.get(skin_id, {})
		if skin_id not in ANIMATED_SKINS:
			_check(skin == original, "Overlay changed another skin: " + skin_id)
			continue
		_check(skin.size() == original.size(), "Overlay changed skin keys: " + skin_id)
		for key: String in original:
			if key not in ["animations", "frame_sizes", "coverage"]:
				_check(skin.get(key) == original[key], "Overlay changed %s/%s." % [skin_id, key])
		for path: String in original.get("frame_sizes", {}):
			_check(skin.get("frame_sizes", {}).get(path) == original["frame_sizes"][path], "Original rotation dimensions changed: " + path)
		var old_coverage: Dictionary = original.get("coverage", {})
		var coverage: Dictionary = skin.get("coverage", {})
		_check(coverage.size() == old_coverage.size(), "Overlay changed coverage keys: " + skin_id)
		for key: String in old_coverage:
			if key != "animated_directions":
				_check(coverage.get(key) == old_coverage[key], "Overlay changed original coverage: %s/%s." % [skin_id, key])
	for skin_id: String in SKINS:
		var skin := CharacterSpriteLibrary.get_skin(skin_id)
		var native_size: Array = skin.get("size", [])
		_check(native_size.size() == 2 and is_equal_approx(float(native_size[0]), 56.0) and is_equal_approx(float(native_size[1]), 56.0), skin_id + " base canvas must remain 56x56.")
		_check(is_equal_approx(float(skin.get("display_height", 0)), float(HEIGHTS[skin_id])), skin_id + " display height changed.")
		var foot: Array = skin.get("foot_position", [])
		_check(foot.size() == 2 and is_equal_approx(float(foot[0]), 28.0) and is_equal_approx(float(foot[1]), float(FOOT_Y[skin_id])), skin_id + " original feet anchor changed.")
		_check(CharacterSpriteLibrary.skin_for_monster(MONSTERS[skin_id]) == skin_id, skin_id + " monster mapping changed.")
		for index in DIRECTIONS.size():
			var rotation_path := "res://Assets/Characters/%s/rotations/%s.png" % [skin_id, DIRECTIONS[index]]
			_check(skin.get("rotations", {}).get(DIRECTIONS[index], "") == rotation_path, skin_id + " original rotation path changed.")
			_check(FileAccess.get_sha256(rotation_path) == ORIGINAL_ROTATION_SHA256[skin_id][index], "Original rotation PNG bytes changed: " + rotation_path)
	_check(CharacterSpriteLibrary.default_player_skin() == String(base.get("defaults", {}).get("player", "")), "Default player changed.")


func _test_clips(skin_id: String) -> void:
	var skin := CharacterSpriteLibrary.get_skin(skin_id)
	var definitions: Dictionary = skin.get("animations", {})
	var dimensions: Dictionary = skin.get("frame_sizes", {})
	var coverage: Dictionary = skin.get("coverage", {}).get("animated_directions", {})
	var frames := CharacterSpriteLibrary.get_frames(skin_id)
	_check(definitions.size() == 3, skin_id + " must define exactly idle, walk and attack.")
	_check(frames.get_animation_names().size() == 24, skin_id + " must build exactly 24 directional clips.")
	var total := 0
	var paths_seen: Dictionary = {}
	for role: String in FRAME_COUNTS:
		var definition: Dictionary = definitions.get(role, {})
		var by_direction: Dictionary = definition.get("directions", {})
		_check(by_direction.size() == 8, skin_id + "/" + role + " must contain eight exact directions.")
		_check(is_equal_approx(float(definition.get("fps", 0)), float(RATES[role])), skin_id + "/" + role + " catalog FPS incorrect.")
		_check(bool(definition.get("loop", role == "attack")) == (role != "attack"), skin_id + "/" + role + " catalog loop incorrect.")
		_check(coverage.get(role, []) == DIRECTIONS, skin_id + "/" + role + " coverage must list canonical eight directions.")
		for direction: String in DIRECTIONS:
			var paths: Array = by_direction.get(direction, [])
			var animation := StringName(role + "_" + direction)
			var label := skin_id + "/" + role + "/" + direction
			_check(paths.size() == int(FRAME_COUNTS[role]), label + " catalog frame count incorrect.")
			_check(CharacterSpriteLibrary.has_authored_animation(skin_id, role, direction), label + " is using a rotation fallback.")
			_check(frames.has_animation(animation), label + " runtime clip missing.")
			if not frames.has_animation(animation):
				continue
			_check(frames.get_frame_count(animation) == int(FRAME_COUNTS[role]), label + " runtime frame count incorrect.")
			_check(is_equal_approx(frames.get_animation_speed(animation), float(RATES[role])), label + " runtime FPS incorrect.")
			_check(frames.get_animation_loop(animation) == (role != "attack"), label + " runtime loop incorrect.")
			for index in paths.size():
				var path := String(paths[index])
				total += 1
				_check(not paths_seen.has(path), "Reused animation frame path: " + path)
				paths_seen[path] = true
				_check(ResourceLoader.exists(path, "Texture2D"), "Imported frame missing: " + path)
				if index >= frames.get_frame_count(animation):
					continue
				var texture := frames.get_frame_texture(animation, index)
				_check(texture != null and texture.resource_path == path, label + " runtime frame order/path incorrect.")
				if texture == null:
					continue
				var declared: Array = dimensions.get(path, [])
				_check(declared.size() == 2, "Native frame dimensions missing: " + path)
				if declared.size() == 2:
					_check(texture.get_width() == int(declared[0]) and texture.get_height() == int(declared[1]), "Imported/native size mismatch: " + path)
				var image := texture.get_image()
				_check(image != null and not image.is_empty(), "Imported frame pixels unavailable: " + path)
				if image != null and not image.is_empty():
					_check(image.get_format() == Image.FORMAT_RGBA8 and image.detect_alpha() != Image.ALPHA_NONE, "Imported frame must retain RGBA alpha: " + path)
					_check(not image.has_mipmaps(), "Imported frame contains mipmaps: " + path)
	_check(total == 200, skin_id + " must reference exactly 200 authored animation frames.")


func _test_live_actors(ready_skins: Array[String]) -> void:
	var actors: Array[ActorSprite] = []
	for skin_id: String in ready_skins:
		for index in DIRECTIONS.size():
			var actor := ActorSprite.new().configure(Vector2(32, 32), Color.GREEN, skin_id + "_" + DIRECTIONS[index])
			root.add_child(actor)
			actor.set_skin(skin_id)
			actor.face_direction(VECTORS[index])
			completions[actor.entity_id] = 0
			actor.attack_finished.connect(_on_attack_finished.bind(actor.entity_id))
			actors.append(actor)
	var initial_frames: Dictionary = _frame_snapshot(actors)
	await _elapsed_frames(0.24)
	for actor: ActorSprite in actors:
		_check(actor.animated_sprite.animation == StringName("idle_" + actor.facing), actor.entity_id + " idle wiring incorrect.")
		_check(actor.animated_sprite.frame != initial_frames[actor.entity_id], actor.entity_id + " idle remained static across elapsed process frames.")
		actor.update_visual_motion(VECTORS[DIRECTIONS.find(actor.facing)])
	initial_frames = _frame_snapshot(actors)
	var walk_elapsed := 0.0
	var walk_deadline := Time.get_ticks_msec() + 15000
	while walk_elapsed < 0.27 and Time.get_ticks_msec() < walk_deadline:
		for actor: ActorSprite in actors:
			actor.update_visual_motion(VECTORS[DIRECTIONS.find(actor.facing)])
		await process_frame
		walk_elapsed += root.get_process_delta_time()
	_check(walk_elapsed >= 0.27, "Live walk simulation did not progress before its wall-clock timeout.")
	for actor: ActorSprite in actors:
		_check(actor.animated_sprite.animation == StringName("walk_" + actor.facing), actor.entity_id + " walk wiring incorrect.")
		_check(actor.animated_sprite.frame != initial_frames[actor.entity_id], actor.entity_id + " walk remained static across elapsed process frames.")
	await _elapsed_frames(0.28)
	for actor: ActorSprite in actors:
		_check(actor.animated_sprite.animation == StringName("idle_" + actor.facing), actor.entity_id + " did not settle to idle.")
		actor.play_attack(VECTORS[DIRECTIONS.find(actor.facing)])
		_check(not actor._fallback_attack and is_equal_approx(actor._attack_duration, 1.2), actor.entity_id + " attack must use authored 12/10-second clip.")
	await _elapsed_frames(0.35)
	for actor: ActorSprite in actors:
		_check(actor.animated_sprite.animation == StringName("attack_" + actor.facing) and actor.animated_sprite.frame > 0, actor.entity_id + " attack did not visibly advance.")
		_check(completions[actor.entity_id] == 0, actor.entity_id + " attack completed too early.")
		var direction := actor.facing
		actor.face_direction(-VECTORS[DIRECTIONS.find(direction)])
		_check(actor.facing == direction, actor.entity_id + " turned during attack.")
	await _elapsed_frames(1.02)
	for actor: ActorSprite in actors:
		_check(completions[actor.entity_id] == 1, actor.entity_id + " attack completion missing or duplicated.")
		_check(actor.animated_sprite.animation == StringName("idle_" + actor.facing), actor.entity_id + " did not idle after attack.")
		_check_actor_geometry(actor)
		actor.free()
	print("[Worker/Warrior animation smoke] Checked %d live actors for elapsed-frame idle/walk/attack and completion." % actors.size())


func _frame_snapshot(actors: Array[ActorSprite]) -> Dictionary:
	var result: Dictionary = {}
	for actor: ActorSprite in actors:
		result[actor.entity_id] = actor.animated_sprite.frame
	return result


func _elapsed_frames(seconds: float) -> void:
	# Headless load can clamp simulation delta; wall time does not prove an action elapsed.
	var elapsed := 0.0
	var deadline := Time.get_ticks_msec() + 15000
	while elapsed < seconds and Time.get_ticks_msec() < deadline:
		await process_frame
		elapsed += root.get_process_delta_time()
	_check(elapsed >= seconds, "Simulation did not advance %.2f seconds before its wall-clock timeout." % seconds)
	# process_frame fires before node processing: let the counted frame reach every actor.
	await process_frame


func _on_attack_finished(entity_id: String) -> void:
	completions[entity_id] = int(completions.get(entity_id, 0)) + 1


func _check_actor_geometry(actor: ActorSprite) -> void:
	var skin_id := actor.skin_id
	var body := actor.get_node("BodyCollision") as CollisionShape2D
	var shape := body.shape as RectangleShape2D
	_check(actor.animated_sprite.scale.is_equal_approx(Vector2.ONE * float(HEIGHTS[skin_id]) / 56.0), actor.entity_id + " visual scale changed.")
	_check(actor.animated_sprite.offset == Vector2(0, 28.0 - float(FOOT_Y[skin_id])), actor.entity_id + " original anchor changed.")
	_check(actor.animated_sprite.position == Vector2.ZERO, actor.entity_id + " action shifted visual origin.")
	_check(actor.animated_sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, actor.entity_id + " lost nearest filtering.")
	_check(body.position == Vector2.ZERO and shape != null and shape.size == Vector2(24, 24), actor.entity_id + " collision body changed.")
	_check(actor.collision_layer == 2 and actor.collision_mask == 1, actor.entity_id + " collision layers changed.")


func _test_game_integration(ready_skins: Array[String]) -> void:
	var packed := load("res://scenes/EastOutskirtsLayered.tscn") as PackedScene
	_check(packed != null, "Actual EastOutskirts scene could not load.")
	if packed == null:
		return
	var container := packed.instantiate()
	root.get_node("SceneTravel").set("_player", null)
	root.add_child(container)
	var game: Variant = container.get_node("Combat")
	game.set_physics_process(false)
	await process_frame
	var deadline := Time.get_ticks_msec() + 20000
	while (game.grid_adapter == null or not game.grid_adapter.completed) and Time.get_ticks_msec() < deadline:
		await physics_frame
	_check(game.grid_adapter != null and game.grid_adapter.completed, "EastOutskirts grid adoption did not finish.")
	var player_sprite: ActorSprite = game.actor_sprites.get(game.player.entity_id)
	var player_actor: CombatActor = game.combat.actors.get(game.player.entity_id)
	_check(player_sprite != null and player_sprite.skin_id == "peasant", "Actual game default player artwork changed.")
	_check(player_actor != null, "Actual game did not register the player.")
	if player_sprite == null or player_actor == null:
		container.free()
		return
	var database: Dictionary = game._active_monster_database()
	for index in SKINS.size():
		var skin_id: String = SKINS[index]
		if skin_id not in ready_skins:
			continue
		var template_id: int = [15, 29][index]
		_check(database.get(template_id, {}).get("name", "") == MONSTERS[skin_id], skin_id + " template missing from actual spawn menu database.")
		_check(game.spawn_monster_by_id(template_id), skin_id + " actual spawn API failed.")
		var entity_id := "monster_%d" % (int(game.next_monster_number) - 1)
		var sprite: ActorSprite = game.actor_sprites.get(entity_id)
		var actor: CombatActor = game.combat.actors.get(entity_id)
		_check(sprite != null and sprite.skin_id == skin_id and actor != null, skin_id + " spawn did not wire its registered ActorSprite.")
		if sprite == null or actor == null:
			continue
		_check(sprite.animated_sprite.sprite_frames.get_animation_names().size() == 24, skin_id + " actual game spawn did not receive 24 clips.")
		var idle_frame := sprite.animated_sprite.frame
		await _elapsed_frames(0.24)
		_check(String(sprite.animated_sprite.animation).begins_with("idle_") and sprite.animated_sprite.frame != idle_frame, skin_id + " actual game idle remains static.")
		# Feed changed simulation coordinates through the game's real visual-motion bridge.
		var start_x := actor.x
		var start_position := sprite.position
		var walk_frame := -1
		var motion_elapsed := 0.0
		var motion_deadline := Time.get_ticks_msec() + 15000
		while motion_elapsed < 0.27 and Time.get_ticks_msec() < motion_deadline:
			actor.x = start_x + 0.01 + motion_elapsed
			game._update_sprite_position(entity_id)
			if walk_frame < 0:
				walk_frame = sprite.animated_sprite.frame
			await process_frame
			motion_elapsed += root.get_process_delta_time()
		_check(motion_elapsed >= 0.27, skin_id + " actual game simulation did not advance before its timeout.")
		_check(sprite.position.x > start_position.x and sprite.animated_sprite.animation == &"walk_east", skin_id + " actual game position bridge did not choose east walk.")
		_check(sprite.animated_sprite.frame != walk_frame, skin_id + " actual game walk remains static.")
		await _elapsed_frames(0.28)
		_check(sprite.animated_sprite.animation == &"idle_east", skin_id + " actual game did not settle to idle.")
		# A real fixed combat tick produces the event consumed by the game, rather than calling play_attack here.
		actor.x = player_actor.x - 1.0
		actor.y = player_actor.y
		actor.requires_line_of_sight = false
		actor.next_attack_tick = float(game.combat.current_tick)
		actor.aggro_attacker_ids.assign([game.player.entity_id])
		game.player.current_target = entity_id
		player_actor.current_target_id = entity_id
		player_actor.hp = 10000
		player_actor.max_hp = 10000
		game._update_sprite_position(entity_id)
		sprite.cancel_action()
		completions[entity_id] = 0
		sprite.attack_finished.connect(_on_attack_finished.bind(entity_id))
		var events: Array[Dictionary] = game.combat.process_tick(game.world)
		var produced_attack := false
		for event: Dictionary in events:
			if event.get("type", "") == "entity_hit" and event.get("attacker_id", "") == entity_id:
				produced_attack = true
		_check(produced_attack, skin_id + " real combat tick produced no monster attack event.")
		game._handle_combat_events(events)
		_check(sprite.animated_sprite.animation == &"attack_east" and not sprite._fallback_attack, skin_id + " combat event did not play authored attack toward the player.")
		await _elapsed_frames(0.35)
		_check(sprite.animated_sprite.animation == &"attack_east" and sprite.animated_sprite.frame > 0, skin_id + " actual game attack remains static.")
		await _elapsed_frames(1.02)
		_check(completions[entity_id] == 1 and sprite.animated_sprite.animation == &"idle_east", skin_id + " actual game attack did not finish once and return to idle.")
		_check_actor_geometry(sprite)
		_check(player_sprite.skin_id == "peasant", skin_id + " spawning/attacking changed default player artwork.")
		game._despawn_monster(entity_id)
		_check(not game.actor_sprites.has(entity_id) and not game.combat.actors.has(entity_id), skin_id + " fixture despawn left an active actor.")
	container.free()
	await process_frame
	print("[Worker/Warrior animation smoke] Checked actual EastOutskirts public spawns, motion bridge and combat events.")


func _capture_lab() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 1000)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	var lab := Node2D.new()
	viewport.add_child(lab)
	var background := Polygon2D.new()
	background.polygon = PackedVector2Array([Vector2(-1200, -1200), Vector2(1200, -1200), Vector2(1200, 1200), Vector2(-1200, 1200)])
	background.color = Color("292f33")
	lab.add_child(background)
	var camera := Camera2D.new()
	lab.add_child(camera)
	camera.make_current()
	for skin_id: String in SKINS:
		var actors: Array[ActorSprite] = []
		var labels: Array[Label] = []
		for index in range(9):
			var actor := ActorSprite.new().configure(Vector2(32, 32), Color.GREEN, "capture_%d" % index)
			lab.add_child(actor)
			actor.position = Vector2(float(index % 3 - 1) * 100.0, (floorf(float(index) / 3.0) - 1.0) * 75.0 + 15.0)
			actor.set_process(false)
			actor.set_skin("peasant" if index == 0 else skin_id)
			actor.face_direction(Vector2.DOWN if index == 0 else VECTORS[index - 1])
			var label := Label.new()
			label.text = "Player" if index == 0 else DIRECTIONS[index - 1]
			label.position = actor.position + Vector2(-22, 6)
			label.add_theme_font_size_override("font_size", 9)
			lab.add_child(label)
			actors.append(actor)
			labels.append(label)
		for zoom_level in [1, 4]:
			camera.zoom = Vector2.ONE * float(zoom_level)
			camera.force_update_scroll()
			for role: String in FRAME_COUNTS:
				for sample in range(3):
					for index in actors.size():
						var actor := actors[index]
						actor.cancel_action()
						var direction := "south" if index == 0 else DIRECTIONS[index - 1]
						var animation := StringName(role + "_" + direction)
						if not actor.animated_sprite.sprite_frames.has_animation(animation):
							animation = StringName("idle_" + direction)
						actor.animated_sprite.play(animation)
						actor.animated_sprite.pause()
						var count := actor.animated_sprite.sprite_frames.get_frame_count(animation)
						actor.animated_sprite.frame = int(round(float(count - 1) * float(sample) / 2.0))
					await process_frame
					await RenderingServer.frame_post_draw
					var image := viewport.get_texture().get_image()
					_check(image != null and not image.is_empty(), "Lab capture empty.")
					if image != null and not image.is_empty():
						var filename := "%s-%s-zoom%d-sample%d.png" % [skin_id, role, zoom_level, sample]
						_check(image.save_png(capture_directory.path_join(filename)) == OK, "Could not save lab capture: " + filename)
		for actor: ActorSprite in actors:
			actor.free()
		for label: Label in labels:
			label.free()
	viewport.free()
