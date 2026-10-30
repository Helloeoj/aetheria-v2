extends SceneTree
## Import first, then run with --headless --path godot_client --script res://scripts/dev_tools/goblin_scout_animation_smoke.gd.
## A graphical run with -- --capture-dir=ABS writes actual ActorSprite lab renders at Camera2D zoom 1 and 4.

const BASE_CATALOG := "res://data/character_sprites.json"
const SKIN := "goblin_scout"
const EXPECTED_SCALE := 44.0 / 60.0
const DIRECTIONS: Array[String] = [
	"south", "south-east", "east", "north-east",
	"north", "north-west", "west", "south-west"
]
const VECTORS: Array[Vector2] = [
	Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(1, -1),
	Vector2(0, -1), Vector2(-1, -1), Vector2(-1, 0), Vector2(-1, 1)
]
const FRAME_COUNTS := {"idle": 5, "walk": 8, "attack": 12}
const RATES := {"idle": 6.0, "walk": 9.0, "attack": 10.0}

var checks := 0
var failures: Array[String] = []
var capture_directory := ""
var finished_attacks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture_directory = argument.trim_prefix("--capture-dir=")
	var base_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASE_CATALOG))
	_check(base_value is Dictionary, "Original base catalog must parse as a dictionary.")
	if base_value is Dictionary:
		_test_preservation(base_value)
		_test_clips()
		_test_actor()
	if not capture_directory.is_empty():
		_check(capture_directory.is_absolute_path(), "Capture directory must be absolute.")
		_check(DisplayServer.get_name() != "headless", "Captures require a graphical Godot run.")
		if failures.is_empty():
			var error := DirAccess.make_dir_recursive_absolute(capture_directory)
			_check(error == OK, "Could not create requested capture directory.")
			if error == OK:
				await _capture_lab()
	if failures.is_empty():
		print("[Scout animation smoke] PASS: %d checks; 24 clips, 200 frames, eight facings; base catalog preserved." % checks)
		quit(0)
	else:
		printerr("[Scout animation smoke] FAIL: %d of %d checks failed." % [failures.size(), checks])
		quit(1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("[Scout animation smoke] " + label)


func _test_preservation(base: Dictionary) -> void:
	var effective := CharacterSpriteLibrary.get_catalog()
	_check(effective.size() == base.size(), "Overlay changed base catalog top-level keys.")
	for key: String in base:
		if key != "skins":
			_check(effective.get(key) == base[key], "Overlay changed base catalog field: " + key)
	var base_skins: Dictionary = base.get("skins", {})
	var effective_skins: Dictionary = effective.get("skins", {})
	_check(effective_skins.size() == base_skins.size(), "Overlay added or removed a skin.")
	for skin_id: String in base_skins:
		if skin_id != SKIN:
			_check(effective_skins.get(skin_id) == base_skins[skin_id], "Overlay changed another skin: " + skin_id)
	var scout := CharacterSpriteLibrary.get_skin(SKIN)
	var original: Dictionary = base_skins.get(SKIN, {})
	_check(not scout.is_empty() and not original.is_empty(), "Scout is missing from a catalog.")
	for key: String in original:
		if key not in ["animations", "frame_sizes", "coverage"]:
			_check(scout.get(key) == original[key], "Overlay changed original Scout field: " + key)
	for path: String in original.get("frame_sizes", {}):
		_check(scout.get("frame_sizes", {}).get(path) == original["frame_sizes"][path], "Overlay changed rotation dimensions: " + path)
	var native_size: Array = scout.get("size", [])
	_check(native_size.size() == 2 and is_equal_approx(float(native_size[0]), 60.0) and is_equal_approx(float(native_size[1]), 60.0), "Scout base canvas must remain 60x60.")
	_check(is_equal_approx(float(scout.get("display_height", 0)), 44.0), "Scout display height must remain 44.")
	var foot_position: Array = scout.get("foot_position", [])
	_check(foot_position.size() == 2 and is_equal_approx(float(foot_position[0]), 30.0) and is_equal_approx(float(foot_position[1]), 55.0), "Scout feet anchor must remain [30,55].")
	_check(CharacterSpriteLibrary.skin_for_monster("Goblin Scout") == SKIN, "Goblin Scout mapping changed.")
	_check(CharacterSpriteLibrary.default_player_skin() == String(base.get("defaults", {}).get("player", "")), "Default player changed.")


func _test_clips() -> void:
	var scout := CharacterSpriteLibrary.get_skin(SKIN)
	var definitions: Dictionary = scout.get("animations", {})
	var dimensions: Dictionary = scout.get("frame_sizes", {})
	var coverage: Dictionary = scout.get("coverage", {}).get("animated_directions", {})
	var frames := CharacterSpriteLibrary.get_frames(SKIN)
	_check(definitions.size() == 3, "Scout must have exactly idle, walk and attack action definitions.")
	_check(frames.get_animation_names().size() == 24, "Scout must build exactly 24 directional clips.")
	var total_frames := 0
	var seen_paths: Dictionary = {}
	for role: String in FRAME_COUNTS:
		var definition: Dictionary = definitions.get(role, {})
		var by_direction: Dictionary = definition.get("directions", {})
		_check(by_direction.size() == 8, role + " must contain all eight exact directions.")
		_check(is_equal_approx(float(definition.get("fps", 0)), float(RATES[role])), role + " catalog FPS is incorrect.")
		_check(bool(definition.get("loop", role == "attack")) == (role != "attack"), role + " catalog loop setting is incorrect.")
		_check(coverage.get(role, []) == DIRECTIONS, role + " coverage must list all eight directions in canonical order.")
		for direction: String in DIRECTIONS:
			var paths: Array = by_direction.get(direction, [])
			var animation := CharacterSpriteLibrary.animation_name(role, direction)
			var label := role + "/" + direction
			_check(paths.size() == int(FRAME_COUNTS[role]), label + " catalog frame count is incorrect.")
			_check(CharacterSpriteLibrary.has_authored_animation(SKIN, role, direction), label + " is using a fallback.")
			_check(frames.has_animation(animation), label + " was not built.")
			if not frames.has_animation(animation):
				continue
			_check(frames.get_frame_count(animation) == int(FRAME_COUNTS[role]), label + " runtime frame count is incorrect.")
			_check(is_equal_approx(frames.get_animation_speed(animation), float(RATES[role])), label + " runtime FPS is incorrect.")
			_check(frames.get_animation_loop(animation) == (role != "attack"), label + " runtime loop setting is incorrect.")
			for index in paths.size():
				var path := String(paths[index])
				total_frames += 1
				_check(not seen_paths.has(path), "Frame path reused across clips: " + path)
				seen_paths[path] = true
				_check(ResourceLoader.exists(path, "Texture2D"), "Imported texture missing: " + path)
				if index >= frames.get_frame_count(animation):
					continue
				var texture := frames.get_frame_texture(animation, index)
				_check(texture != null, label + " has a null texture.")
				if texture == null:
					continue
				_check(texture.resource_path == path, label + " frame order/path changed at %d." % index)
				var declared: Array = dimensions.get(path, [])
				_check(declared.size() == 2, "Native frame size missing: " + path)
				if declared.size() == 2:
					_check(texture.get_width() == int(declared[0]) and texture.get_height() == int(declared[1]), "Imported dimensions differ from native declaration: " + path)
				var image := texture.get_image()
				_check(image != null and not image.is_empty(), "Imported texture pixels unavailable: " + path)
				if image != null and not image.is_empty():
					_check(image.detect_alpha() != Image.ALPHA_NONE, "Imported frame lost transparent alpha: " + path)
					_check(not image.has_mipmaps(), "Imported frame contains mipmaps: " + path)
	_check(total_frames == 200, "Scout must reference exactly 200 animation frames.")


func _test_actor() -> void:
	var actor := ActorSprite.new().configure(Vector2(32, 32), Color.GREEN, "scout_animation_smoke")
	root.add_child(actor)
	actor.set_process(false)
	actor.set_skin(SKIN)
	actor.attack_finished.connect(_on_attack_finished)
	var body_shape := actor.get_node("BodyCollision").get("shape") as RectangleShape2D
	for index in DIRECTIONS.size():
		var direction := DIRECTIONS[index]
		var vector := VECTORS[index]
		actor.cancel_action()
		actor.face_direction(vector)
		_check(actor.facing == direction, "Actor facing resolver failed: " + direction)
		_check(actor.animated_sprite.animation == StringName("idle_" + direction), "Actor idle failed: " + direction)
		actor.update_visual_motion(vector)
		_check(actor.animated_sprite.animation == StringName("walk_" + direction), "Actor walk failed: " + direction)
		actor._process(0.25)
		_check(actor.animated_sprite.animation == StringName("idle_" + direction), "Actor did not settle to idle: " + direction)
		var previous_completions := finished_attacks
		actor.play_attack(vector)
		_check(actor.animated_sprite.animation == StringName("attack_" + direction), "Actor authored attack failed: " + direction)
		_check(not actor._fallback_attack, "Actor used fallback attack: " + direction)
		_check(is_equal_approx(actor._attack_duration, 1.2), "Actor attack duration must be 12/10 seconds: " + direction)
		actor._process(0.6)
		_check(finished_attacks == previous_completions, "Attack completed before its duration: " + direction)
		actor.face_direction(-vector)
		_check(actor.facing == direction, "Actor changed facing during attack: " + direction)
		actor._process(0.7)
		_check(finished_attacks == previous_completions + 1, "Attack completion signal missing or duplicated: " + direction)
		_check(actor.animated_sprite.animation == StringName("idle_" + direction), "Actor did not return to idle after attack: " + direction)
		_check(actor.animated_sprite.scale.is_equal_approx(Vector2.ONE * EXPECTED_SCALE), "Animation changed Scout scale: " + direction)
		_check(actor.animated_sprite.offset == Vector2(0, -25), "Animation changed Scout anchor offset: " + direction)
		_check(actor.animated_sprite.position == Vector2.ZERO, "Authored action moved the visual origin: " + direction)
		_check(actor.animated_sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Scout lost nearest filtering.")
		_check(body_shape != null and body_shape.size == Vector2(24, 24), "Animation changed the actor collision body.")
	actor.free()


func _on_attack_finished() -> void:
	finished_attacks += 1


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
	var actors: Array[ActorSprite] = []
	for index in range(9):
		var actor := ActorSprite.new().configure(Vector2(32, 32), Color.GREEN, "capture_%d" % index)
		lab.add_child(actor)
		actor.position = Vector2(float(index % 3 - 1) * 100.0, (floorf(float(index) / 3.0) - 1.0) * 75.0 + 15.0)
		actor.set_process(false)
		actor.set_skin(CharacterSpriteLibrary.default_player_skin() if index == 0 else SKIN)
		actor.face_direction(Vector2.DOWN if index == 0 else VECTORS[index - 1])
		var label := Label.new()
		label.text = "Player" if index == 0 else DIRECTIONS[index - 1]
		label.position = actor.position + Vector2(-22, 6)
		label.add_theme_font_size_override("font_size", 9)
		lab.add_child(label)
		actors.append(actor)
	for zoom_level in [1, 4]:
		camera.zoom = Vector2.ONE * float(zoom_level)
		camera.force_update_scroll()
		for role: String in FRAME_COUNTS:
			# Three actual frame samples show beginning, middle and end without synthetic sprite assembly.
			for sample in range(3):
				for index in actors.size():
					var actor := actors[index]
					actor.cancel_action()
					var direction := "south" if index == 0 else DIRECTIONS[index - 1]
					var animation := CharacterSpriteLibrary.animation_name(role, direction)
					if not actor.animated_sprite.sprite_frames.has_animation(animation):
						animation = CharacterSpriteLibrary.animation_name("idle", direction)
					actor.animated_sprite.play(animation)
					actor.animated_sprite.pause()
					var count := actor.animated_sprite.sprite_frames.get_frame_count(animation)
					actor.animated_sprite.frame = int(round(float(count - 1) * float(sample) / 2.0))
				await process_frame
				await RenderingServer.frame_post_draw
				var image := viewport.get_texture().get_image()
				_check(image != null and not image.is_empty(), "Lab capture was empty.")
				if image != null and not image.is_empty():
					var filename := "scout-%s-zoom%d-sample%d.png" % [role, zoom_level, sample]
					_check(image.save_png(capture_directory.path_join(filename)) == OK, "Could not save lab capture: " + filename)
	viewport.free()
