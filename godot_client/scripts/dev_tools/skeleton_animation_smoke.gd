extends SceneTree
## --headless --path godot_client --script res://scripts/dev_tools/skeleton_animation_smoke.gd
## Optional -- --skin=SKIN selects one existing skeleton for staged validation.
## Graphical -- --capture-dir=ABS records normal-speed idle/walk loops and attacks.
## Pixel/frame differences do not establish motion quality; review captured artwork separately.

const BASE_CATALOG := "res://data/character_sprites.json"
const SKINS := ["skeleton_footsoldier", "skeleton_knight", "skeleton_acolyte", "skeleton_captain"]
const ANIMATED_SKINS := ["goblin_scout", "goblin_worker", "goblin_warrior", "skeleton_footsoldier", "skeleton_knight", "skeleton_acolyte", "skeleton_captain"]
const DIRECTIONS: Array[String] = ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"]
const VECTORS: Array[Vector2] = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(1, -1), Vector2(0, -1), Vector2(-1, -1), Vector2(-1, 0), Vector2(-1, 1)]
const FRAME_COUNTS := {"idle": 8, "walk": 8, "attack": 12}
const RATES := {"idle": 4.0, "walk": 9.0, "attack": 10.0}
const NATIVE_SIZES := {"skeleton_footsoldier": Vector2(60, 60), "skeleton_knight": Vector2(60, 60), "skeleton_acolyte": Vector2(56, 56), "skeleton_captain": Vector2(56, 56)}
const HEIGHTS := {"skeleton_footsoldier": 48.0, "skeleton_knight": 52.0, "skeleton_acolyte": 50.0, "skeleton_captain": 56.0}
const FOOT_Y := {"skeleton_footsoldier": 56.0, "skeleton_knight": 56.0, "skeleton_acolyte": 53.0, "skeleton_captain": 54.0}
const MONSTERS := {"skeleton_footsoldier": "Skeleton Footsoldier", "skeleton_knight": "Skeleton Knight", "skeleton_acolyte": "Skeleton Acolyte", "skeleton_captain": "Skeleton Captain"}
const MONSTER_IDS := {"skeleton_footsoldier": 1049, "skeleton_knight": 1050, "skeleton_acolyte": 1052, "skeleton_captain": 1053}
## Original PNG hashes were recorded before any skeleton animation installation.
const ORIGINAL_ROTATION_SHA256 := {
  "skeleton_footsoldier": [
    "598c86bcd50245218d89df892c41984c2880d2c6538b2f063df9595c01ba2719",
    "cff28b1bc12fc812b7b6d7be9d9c896fb08a4a1d2e17871043ed7030241fab7e",
    "ef32b34b484a6494411b8c98d99f717f2918998202b98d47744478603d0e9ec0",
    "37f20f24ccfb193d84dede4fa0f6bcc4172aa7e29016a4d54e7c369ac8812e1d",
    "0ccea68d83e6fa7adf63fe6465a6f87e561e405587ee67a6040ee196792df792",
    "07e6a69db8a5aeadb6fbcfda4b98f5f0b9afec7bd4ab4e0c87c8e95c9f1320cf",
    "8f120201b91d1f9300d0fa621df7a192c5231de6db7600a7859fa0e9849b588c",
    "81cf2fdae0b7da2fd1dcdc5834cc95e4d433bd0fefa7312738ba84520ec4c875"
  ],
  "skeleton_knight": [
    "bf77f2294b99e2085da31f8adfd0d87fe4f8d6d9dbe8c06333e4056d0e4da45b",
    "341269b450786c4590747a41d43ffac2bb32bbe1d4acc82574b4d2620a49aca7",
    "3b2ebe6ba901e1b6493ca89277139a3b5df473a1292b4077d09378cfc70b2ae6",
    "75b97e4e46cac4697dc97fd8168be5c36584010fa3a66583a3e718162ffe4d17",
    "5b7eabefce23e2a93476d654e98425b3d33b8060d642cb28553b33c61352d7ab",
    "d36c3b279760bd8f419c6753a76b55c866d1f15f5fe6794ab8f845c55d2fea02",
    "0e42baf00b5b173fb2c6aa090fc22a7969f295f6bd9944bfaf0851470481ca5b",
    "268a6d34efb0acfbdcb20dbce7b6200fec0b90b3a326e20d50cd9cccb29315a1"
  ],
  "skeleton_acolyte": [
    "39ed755fad115f2c04396f6b59c260be941c837a007ff1ca51a487371a680396",
    "205d8c1f9f6e4560563705a82442605d2b72e0ed8e44b70157da5f9da4b2ccce",
    "4086cc7c27cefa86429e7392f2bb6785af635d54bcd42e45f419395bee0a5cf3",
    "f82dd35201a791939544af0a05d8167fa2bcc65cce2152690fa64c32da78dc91",
    "3b91713d7761761dacb0319c25f7087129fad3fedeef08a0df1f73c8c6b1fadb",
    "d4ab20732fc18aac815a274dd8035a3a340b0e7cc6bbf4805f600a4c1be02525",
    "661a938976bcb8471abc8753e121670c26096519f6d24b448d50605fdfeae8ba",
    "d34d713307d20129d6d25f98e39555ca4c04deaf1a23ff8fb2e4263c44209a1d"
  ],
  "skeleton_captain": [
    "5f17bd206b2f05df1c1eb18f90376c9cd311475d06e402f534be01b19b062b2e",
    "a4a1611c8585422361be200f729d749f7768fe2b807b2e9e53c9cac239116c34",
    "4077fe3dfa1f82ba757bafc65fa95db9cf389e0e7d56a8f1e41c1b075a957740",
    "f1252301e0ba6f0dfdd6311e564c7ea1bd244f0ff797a81aefbed854ac8f815f",
    "1c2ba120d2c65ecef26c0f9fa312a514559670cb2efed76f6a59281e4b3abecb",
    "cffe5657fce15fefc647ac2179515fe5c2b7f0e4fb6b87374bf012411484ab60",
    "2cedfb189094a5e0b6987151719facf20c6596eaf83cbff56c010f37f89af13b",
    "109a03e0379d7ae91eaef581cc90d99bf652ef867a0e1532a594ca64b91cbed9"
  ]
}

var checks := 0
var failures: Array[String] = []
var selected_skins: Array[String] = []
var capture_directory := ""
var completions: Dictionary = {}
var loops: Dictionary = {}
var observed_role := ""
var observed_frames: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("[Skeleton animation smoke] user:// = " + OS.get_user_data_dir())
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture_directory = argument.trim_prefix("--capture-dir=")
		elif argument.begins_with("--skin="):
			var skin := argument.trim_prefix("--skin=")
			_check(skin in SKINS, "Unknown skeleton selection: " + skin)
			if skin in SKINS and skin not in selected_skins:
				selected_skins.append(skin)
	if selected_skins.is_empty():
		selected_skins.assign(SKINS)
	var base: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASE_CATALOG))
	_check(base is Dictionary, "Original base catalog must parse.")
	if base is Dictionary:
		_test_preservation(base)
		var ready_skins: Array[String] = []
		for skin_id: String in selected_skins:
			var previous_failures := failures.size()
			_test_clips(skin_id)
			if failures.size() == previous_failures:
				ready_skins.append(skin_id)
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
		print("[Skeleton animation smoke] PASS: %d checks; %d selected skins %s; each 24 clips/224 frames; natural cycles, attack completion/cancel and public spawn/movement/combat verified. Artwork requires separate visual review." % [checks, selected_skins.size(), str(selected_skins)])
		quit(0)
	else:
		printerr("[Skeleton animation smoke] FAIL: %d of %d checks failed for %s." % [failures.size(), checks, str(selected_skins)])
		quit(1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("[Skeleton animation smoke] " + label)


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
		var expected_size: Vector2 = NATIVE_SIZES[skin_id]
		_check(native_size.size() == 2 and Vector2(float(native_size[0]), float(native_size[1])) == expected_size, skin_id + " original base canvas changed.")
		_check(is_equal_approx(float(skin.get("display_height", 0)), float(HEIGHTS[skin_id])), skin_id + " display height changed.")
		var foot: Array = skin.get("foot_position", [])
		_check(foot.size() == 2 and is_equal_approx(float(foot[0]), expected_size.x * 0.5) and is_equal_approx(float(foot[1]), float(FOOT_Y[skin_id])), skin_id + " original feet anchor changed.")
		_check(CharacterSpriteLibrary.skin_for_monster(MONSTERS[skin_id]) == skin_id, skin_id + " monster mapping changed.")
		for index in DIRECTIONS.size():
			var rotation_path := "res://Assets/Characters/%s/rotations/%s.png" % [skin_id, DIRECTIONS[index]]
			_check(skin.get("rotations", {}).get(DIRECTIONS[index], "") == rotation_path, skin_id + " original rotation path changed.")
			_check(FileAccess.get_sha256(rotation_path) == ORIGINAL_ROTATION_SHA256[skin_id][index], "Original rotation PNG bytes changed: " + rotation_path)
	_check(CharacterSpriteLibrary.default_player_skin() == String(base.get("defaults", {}).get("player", "")), "Default player changed.")
	_check(CharacterSpriteLibrary.skin_for_player(false) == CharacterSpriteLibrary.default_player_skin() and CharacterSpriteLibrary.skin_for_player(true) == CharacterSpriteLibrary.default_player_skin(), "Equipping a player weapon replaced its base skin.")


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
		var base_fps := float(RATES[role])
		var expected_overrides := {}
		_check(is_equal_approx(float(definition.get("fps", 0)), base_fps), skin_id + "/" + role + " catalog base FPS incorrect.")
		_check(definition.get("fps_by_direction", {}) == expected_overrides, skin_id + "/" + role + " direction FPS overrides incorrect.")
		_check(bool(definition.get("loop", role == "attack")) == (role != "attack"), skin_id + "/" + role + " catalog loop incorrect.")
		_check(coverage.get(role, []) == DIRECTIONS, skin_id + "/" + role + " coverage must list canonical eight directions.")
		for direction: String in DIRECTIONS:
			var paths: Array = by_direction.get(direction, [])
			var animation := StringName(role + "_" + direction)
			var label := skin_id + "/" + role + "/" + direction
			var visible_pixel_states: Dictionary = {}
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
				_check(path == "res://Assets/Characters/%s/animations/%s/%s/frame_%03d.png" % [skin_id, role, direction, index], label + " frame points outside its own ordered character/action/facing folder.")
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
					var canonical := image.duplicate() as Image
					canonical.premultiply_alpha()
					visible_pixel_states[canonical.get_data().hex_encode().sha256_text()] = true
					var source := Image.new()
					var png_error := source.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
					_check(png_error == OK and not source.is_empty(), "Native PNG could not load: " + path)
					if png_error == OK and not source.is_empty():
						source.convert(Image.FORMAT_RGBA8)
						source.premultiply_alpha()
						_check(source.get_size() == canonical.get_size() and source.get_data() == canonical.get_data(), "Imported texture does not match visible native PNG pixels: " + path)
			_check(visible_pixel_states.size() > 1, label + " contains only one visible pixel state; frame counters alone are insufficient.")
	_check(total == 224, skin_id + " authored animation frame total incorrect.")


func _test_live_actors(ready_skins: Array[String]) -> void:
	var actors: Array[ActorSprite] = []
	for skin_id: String in ready_skins:
		for index in DIRECTIONS.size():
			var actor := ActorSprite.new().configure(Vector2(32, 32), Color.GREEN, skin_id + "_" + DIRECTIONS[index])
			root.add_child(actor)
			actor.set_skin(skin_id)
			actor.face_direction(VECTORS[index])
			completions[actor.entity_id] = 0
			loops[actor.entity_id] = 0
			actor.attack_finished.connect(_on_attack_finished.bind(actor.entity_id))
			actor.animated_sprite.animation_looped.connect(_on_looped.bind(actor.entity_id))
			actor.animated_sprite.frame_changed.connect(_on_frame_changed.bind(actor))
			actors.append(actor)
	for role: String in ["idle", "walk"]:
		for actor: ActorSprite in actors:
			loops[actor.entity_id] = 0
			if role == "walk":
				actor.update_visual_motion(VECTORS[DIRECTIONS.find(actor.facing)])
		var duration := 2.0 * float(FRAME_COUNTS[role]) / float(RATES[role]) + 0.1
		var observed := await _observe_action(actors, role, duration)
		for actor: ActorSprite in actors:
			_check(actor.animated_sprite.animation == StringName(role + "_" + actor.facing), actor.entity_id + " selected the wrong locomotion role.")
			_check(observed[actor.entity_id].size() == int(FRAME_COUNTS[role]), actor.entity_id + " did not visit every " + role + " frame.")
			_check(int(loops[actor.entity_id]) >= 2, actor.entity_id + " did not complete two natural " + role + " loops.")
	await _elapsed_frames(0.3)
	# Start after node processing, so the attack timer and sprite clock begin
	# on the same next engine frame rather than at different process phases.
	await create_timer(0.0).timeout
	for actor: ActorSprite in actors:
		_check(actor.animated_sprite.animation == StringName("idle_" + actor.facing), actor.entity_id + " did not settle to idle after motion stopped.")
		actor.play_attack(VECTORS[DIRECTIONS.find(actor.facing)])
		_check(not actor._fallback_attack and is_equal_approx(actor._attack_duration, 1.2), actor.entity_id + " did not use its authored 12/10-second attack.")
		var direction := actor.facing
		actor.face_direction(-VECTORS[DIRECTIONS.find(direction)])
		_check(actor.facing == direction, actor.entity_id + " turned during attack.")
	var attack_seen := await _observe_action(actors, "attack", 1.35)
	for actor: ActorSprite in actors:
		_check(attack_seen[actor.entity_id].size() == 12, actor.entity_id + " did not visit all attack frames; observed " + str(attack_seen[actor.entity_id].keys()))
		_check(completions[actor.entity_id] == 1 and actor.animated_sprite.animation == StringName("idle_" + actor.facing), actor.entity_id + " attack did not complete exactly once and return to idle.")
		actor.play_attack()
	await _elapsed_frames(0.25)
	for actor: ActorSprite in actors:
		actor.cancel_action()
		_check(actor._attack_remaining == 0.0 and actor.animated_sprite.animation == StringName("idle_" + actor.facing), actor.entity_id + " explicit cancellation did not return to idle.")
	await _elapsed_frames(1.3)
	for actor: ActorSprite in actors:
		_check(completions[actor.entity_id] == 1, actor.entity_id + " cancelled attack emitted completion.")
		actor.play_attack()
	await _elapsed_frames(1.35)
	for actor: ActorSprite in actors:
		_check(completions[actor.entity_id] == 2, actor.entity_id + " restarted attack did not finish once.")
	await _elapsed_frames(0.25)
	for actor: ActorSprite in actors:
		_check(completions[actor.entity_id] == 2, actor.entity_id + " attack completion repeated after recovery.")
		_check_actor_geometry(actor)
		actor.free()
	print("[Skeleton animation smoke] Checked %d live facings for two idle/walk loops, all attack frames, exactly-once completion and explicit cancel/restart." % actors.size())


func _observe_action(actors: Array[ActorSprite], role: String, seconds: float) -> Dictionary:
	# Signals retain logical transitions even if one slow rendered frame spans
	# more than one authored frame. Captures separately require rendered poses.
	observed_role = role
	observed_frames = {}
	for actor: ActorSprite in actors:
		observed_frames[actor.entity_id] = {}
		if actor.animated_sprite.animation == StringName(role + "_" + actor.facing):
			observed_frames[actor.entity_id][actor.animated_sprite.frame] = true
	var elapsed := 0.0
	var deadline := Time.get_ticks_msec() + 30000
	while elapsed < seconds and Time.get_ticks_msec() < deadline:
		if role == "walk":
			for actor: ActorSprite in actors:
				actor.update_visual_motion(VECTORS[DIRECTIONS.find(actor.facing)])
		await process_frame
		elapsed += root.get_process_delta_time()
	_check(elapsed >= seconds, "Elapsed " + role + " observation timed out.")
	if role == "walk":
		for actor: ActorSprite in actors:
			actor.update_visual_motion(VECTORS[DIRECTIONS.find(actor.facing)])
	await create_timer(0.0).timeout
	if role == "walk":
		for actor: ActorSprite in actors:
			actor.update_visual_motion(VECTORS[DIRECTIONS.find(actor.facing)])
	observed_role = ""
	return observed_frames


func _elapsed_frames(seconds: float) -> void:
	var elapsed := 0.0
	var deadline := Time.get_ticks_msec() + 20000
	while elapsed < seconds and Time.get_ticks_msec() < deadline:
		await process_frame
		elapsed += root.get_process_delta_time()
	_check(elapsed >= seconds, "Simulation did not advance %.2f seconds before timeout." % seconds)
	await process_frame


func _on_attack_finished(entity_id: String) -> void:
	completions[entity_id] = int(completions.get(entity_id, 0)) + 1


func _on_looped(entity_id: String) -> void:
	loops[entity_id] = int(loops.get(entity_id, 0)) + 1


func _on_frame_changed(actor: ActorSprite) -> void:
	if not observed_role.is_empty() and observed_frames.has(actor.entity_id) and actor.animated_sprite.animation == StringName(observed_role + "_" + actor.facing):
		observed_frames[actor.entity_id][actor.animated_sprite.frame] = true


func _check_actor_geometry(actor: ActorSprite) -> void:
	var skin_id := actor.skin_id
	var native_size: Vector2 = NATIVE_SIZES[skin_id]
	var body := actor.get_node("BodyCollision") as CollisionShape2D
	var shape := body.shape as RectangleShape2D
	_check(actor.animated_sprite.scale.is_equal_approx(Vector2.ONE * float(HEIGHTS[skin_id]) / native_size.y), actor.entity_id + " visual scale changed.")
	_check(actor.animated_sprite.offset == Vector2(0, native_size.y * 0.5 - float(FOOT_Y[skin_id])), actor.entity_id + " original feet anchor changed.")
	_check(actor.animated_sprite.position == Vector2.ZERO, actor.entity_id + " action shifted the visual origin.")
	_check(actor.animated_sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, actor.entity_id + " lost nearest filtering.")
	_check(body.position == Vector2.ZERO and shape != null and shape.size == Vector2(24, 24), actor.entity_id + " collision body changed.")
	_check(actor.collision_layer == 2 and actor.collision_mask == 1, actor.entity_id + " collision layers changed.")
	_check(actor.z_index == 0 and not actor.y_sort_enabled, actor.entity_id + " actor sorting contract changed.")


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
	for skin_id: String in SKINS:
		if skin_id not in ready_skins:
			continue
		var template_id: int = int(MONSTER_IDS[skin_id])
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
		await _elapsed_frames(0.34)
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
		var projectile_id := ""
		var expected_event := "projectile_spawned" if skin_id == "skeleton_acolyte" else "entity_hit"
		for event: Dictionary in events:
			if event.get("type", "") == expected_event and event.get("attacker_id", "") == entity_id:
				produced_attack = true
				projectile_id = String(event.get("projectile_id", ""))
		if skin_id == "skeleton_acolyte":
			# Monster CombatActor.projectile_speed intentionally remains zero; the
			# projectile itself gets its speed from the default magic profile.
			var projectile: CombatProjectile = game.combat.projectiles.get(projectile_id)
			_check(projectile != null and projectile.attacker_id == entity_id and projectile.damage_type == "magic" and projectile.speed > 0.0, "Acolyte did not retain its separate gameplay projectile.")
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
	print("[Skeleton animation smoke] Checked actual EastOutskirts public spawns, motion bridge and combat events.")


func _capture_lab() -> void:
	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	var lab := Node2D.new()
	viewport.add_child(lab)
	var background := Polygon2D.new()
	background.polygon = PackedVector2Array([Vector2(-3000, -3000), Vector2(3000, -3000), Vector2(3000, 3000), Vector2(-3000, 3000)])
	background.color = Color("292f33")
	lab.add_child(background)
	var camera := Camera2D.new()
	lab.add_child(camera)
	camera.make_current()
	for skin_id: String in selected_skins:
		var actors: Array[ActorSprite] = []
		var labels: Array[Label] = []
		var width := 0.0
		var above := 0.0
		var below := 15.0
		for index in range(9):
			var actor := ActorSprite.new().configure(Vector2(32, 32), Color.GREEN, "capture_%s_%d" % [skin_id, index])
			lab.add_child(actor)
			actor.set_skin(CharacterSpriteLibrary.default_player_skin() if index == 0 else skin_id)
			actor.face_direction(Vector2.DOWN if index == 0 else VECTORS[index - 1])
			actor.attack_finished.connect(_on_attack_finished.bind(actor.entity_id))
			actor.animated_sprite.animation_looped.connect(_on_looped.bind(actor.entity_id))
			var frames := actor.animated_sprite.sprite_frames
			for animation: StringName in frames.get_animation_names():
				for frame in frames.get_frame_count(animation):
					var texture := frames.get_frame_texture(animation, frame)
					width = maxf(width, float(texture.get_width()) * actor.animated_sprite.scale.x)
					above = maxf(above, (float(texture.get_height()) * 0.5 - actor.animated_sprite.offset.y) * actor.animated_sprite.scale.y)
					below = maxf(below, (float(texture.get_height()) * 0.5 + actor.animated_sprite.offset.y) * actor.animated_sprite.scale.y)
			var label := Label.new()
			label.text = "Player" if index == 0 else DIRECTIONS[index - 1]
			label.add_theme_font_size_override("font_size", 9)
			lab.add_child(label)
			actors.append(actor)
			labels.append(label)
		# Fit every full native frame, including a raised/extended halberd, at 4x.
		var cell := Vector2(maxf(100.0, width + 24.0), maxf(85.0, above + below + 24.0))
		viewport.size = Vector2i(int(ceil(cell.x * 12.0)), int(ceil(cell.y * 12.0)))
		camera.position = Vector2(0, (below - above) * 0.5)
		for index in actors.size():
			actors[index].position = Vector2(float(index % 3 - 1) * cell.x, (floorf(float(index) / 3.0) - 1.0) * cell.y)
			labels[index].position = actors[index].position + Vector2(-22, 6)
		for zoom_level in [1, 4]:
			camera.zoom = Vector2.ONE * float(zoom_level)
			camera.force_update_scroll()
			# Wait for the visible renderer before resetting action poses or
			# starting observation deadlines. An inactive/minimized window may
			# defer its first draw while the actor simulation keeps running.
			for warmup in range(3):
				await process_frame
				await RenderingServer.frame_post_draw
			for role: String in FRAME_COUNTS:
				await _capture_action(viewport, camera, actors, skin_id, role, zoom_level, Vector4(width * 0.5 + 4.0, above + 4.0, width * 0.5 + 4.0, below + 4.0))
		for actor: ActorSprite in actors:
			actor.free()
		for label: Label in labels:
			label.free()
	viewport.free()


func _capture_action(viewport: SubViewport, camera: Camera2D, actors: Array[ActorSprite], skin_id: String, role: String, zoom_level: int, review_bounds: Vector4) -> void:
	# Begin after node processing; the ordinary draw at this frame's end can
	# record the real action-start pose at elapsed0 without pausing/forcing it.
	await create_timer(0.0).timeout
	var seen: Dictionary = {}
	var centers: Dictionary = {}
	var player_center := Vector2.ZERO
	for index in actors.size():
		var actor := actors[index]
		actor.cancel_action()
		loops[actor.entity_id] = 0
		completions[actor.entity_id] = 0
		seen[actor.entity_id] = {}
		var center := (actor.position - camera.position) * float(zoom_level) + Vector2(viewport.size) * 0.5
		if index == 0:
			player_center = center
		else:
			centers[DIRECTIONS[index - 1]] = [center.x, center.y]
			if role == "attack":
				actor.play_attack(VECTORS[index - 1])
			elif role == "walk":
				actor.update_visual_motion(VECTORS[index - 1])
			else:
				actor.animated_sprite.stop()
				actor.animated_sprite.play(StringName("idle_" + actor.facing))
		_check(is_equal_approx(actor.animated_sprite.speed_scale, 1.0), "Temporal capture changed sprite speed.")
	_check(is_equal_approx(Engine.time_scale, 1.0), "Temporal captures require normal engine time.")
	var cycle := float(FRAME_COUNTS[role]) / float(RATES[role])
	var duration := cycle + 0.15 if role == "attack" else cycle * 2.0 + 0.1
	var elapsed := 0.0
	var next_sample := 1.0 / 12.0
	var deadline := Time.get_ticks_msec() + 30000
	var samples: Array[Dictionary] = []
	var rendered_images: Array[Image] = []
	await RenderingServer.frame_post_draw
	_record_capture_sample(viewport, actors, skin_id, role, zoom_level, 0.0, samples, rendered_images, seen)
	while elapsed < duration and Time.get_ticks_msec() < deadline:
		if role == "walk":
			for index in range(1, actors.size()):
				actors[index].update_visual_motion(VECTORS[index - 1])
		await process_frame
		elapsed += root.get_process_delta_time()
		if elapsed < next_sample:
			continue
		next_sample += 1.0 / 12.0
		await RenderingServer.frame_post_draw
		_record_capture_sample(viewport, actors, skin_id, role, zoom_level, elapsed, samples, rendered_images, seen)
	_check(elapsed >= duration, "Temporal capture timed out before the requested action duration.")
	await create_timer(0.0).timeout
	var observed_loops: Dictionary = {}
	var completed_attacks: Dictionary = {}
	for index in range(1, actors.size()):
		var actor := actors[index]
		var direction := DIRECTIONS[index - 1]
		observed_loops[direction] = int(loops[actor.entity_id])
		completed_attacks[direction] = int(completions[actor.entity_id])
		_check(seen[actor.entity_id].size() == int(FRAME_COUNTS[role]), actor.entity_id + " temporal capture missed " + role + " frames.")
		if role == "attack":
			_check(completions[actor.entity_id] == 1 and actor.animated_sprite.animation == StringName("idle_" + direction), actor.entity_id + " recorded attack did not complete once and return to idle.")
		else:
			_check(loops[actor.entity_id] >= 2, actor.entity_id + " temporal " + role + " did not loop twice.")
	var metadata := {"skin": skin_id, "role": role, "zoom": zoom_level, "viewport_size": [viewport.size.x, viewport.size.y], "actor_centers": centers, "player_center": [player_center.x, player_center.y], "review_bounds_world_left_above_right_below": [review_bounds.x, review_bounds.y, review_bounds.z, review_bounds.w], "engine_time_scale": Engine.time_scale, "seconds": elapsed, "cycle_seconds": cycle, "minimum_cycles": 1 if role == "attack" else 2, "observed_loops": observed_loops, "completed_attacks": completed_attacks, "samples": samples}
	# Encode/write only after observation, so PNG compression and disk latency
	# cannot slow the recorded action or cause missed rendered poses.
	for index in rendered_images.size():
		_check(rendered_images[index].save_png(capture_directory.path_join(samples[index]["png"])) == OK, "Could not save temporal capture: " + String(samples[index]["png"]))
	rendered_images.clear()
	var metadata_path := capture_directory.path_join("%s-%s-zoom%d-frames.json" % [skin_id, role, zoom_level])
	var file := FileAccess.open(metadata_path, FileAccess.WRITE)
	_check(file != null, "Could not write temporal capture metadata.")
	if file != null:
		file.store_string(JSON.stringify(metadata, "  "))
		file.close()
	print("[Skeleton animation smoke] Recorded %s/%s at zoom%d: %.2fs, %d renders, loops %s, completions %s. Review motion visually." % [skin_id, role, zoom_level, elapsed, samples.size(), JSON.stringify(observed_loops), JSON.stringify(completed_attacks)])


func _record_capture_sample(viewport: SubViewport, actors: Array[ActorSprite], skin_id: String, role: String, zoom_level: int, elapsed: float, samples: Array[Dictionary], rendered_images: Array[Image], seen: Dictionary) -> void:
	var image := viewport.get_texture().get_image()
	_check(image != null and not image.is_empty(), "Temporal capture empty.")
	if image == null or image.is_empty():
		return
	var filename := "%s-%s-zoom%d-frame%03d.png" % [skin_id, role, zoom_level, samples.size()]
	var frame_snapshot: Dictionary = {}
	var animation_snapshot: Dictionary = {}
	for index in range(1, actors.size()):
		var actor := actors[index]
		var direction := DIRECTIONS[index - 1]
		frame_snapshot[direction] = actor.animated_sprite.frame
		animation_snapshot[direction] = String(actor.animated_sprite.animation)
		if actor.animated_sprite.animation == StringName(role + "_" + direction):
			seen[actor.entity_id][actor.animated_sprite.frame] = true
	samples.append({"elapsed": elapsed, "png": filename, "frames": frame_snapshot, "animations": animation_snapshot})
	rendered_images.append(image)
