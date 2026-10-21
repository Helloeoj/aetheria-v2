extends SceneTree
## godot --headless --path . --script res://tools/check_camera_controls.gd

var _failures: Array[String] = []
var _checks := 0
var _game: Node2D
var _camera: Camera2D
var _actor: ActorSprite

func _initialize() -> void:
	_run.call_deferred()

func _verify(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		printerr("[Camera check] " + message)

func _wheel(button: MouseButton, factor: float = 1.0, pressed: bool = true) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.factor = factor
	event.position = Vector2(root.size) * Vector2(0.75, 0.25)
	Input.parse_input_event(event)
	await process_frame
	await physics_frame
	await process_frame

func _verify_center(message: String) -> void:
	_camera.force_update_scroll()
	var screen_position := _actor.get_global_transform_with_canvas().origin
	_verify(screen_position.distance_to(_actor.get_viewport_rect().size * 0.5) < 0.1, message)

func _run() -> void:
	var scene := load("res://scenes/EastOutskirtsLayered.tscn") as PackedScene
	var map := scene.instantiate() as Node2D
	root.add_child(map)
	for frame in 3:
		await process_frame
		await physics_frame
	_game = map.get_node("Combat")
	_camera = map.get_node("MapCamera")
	_actor = _game.actor_sprites[_game.player.entity_id]
	_verify(root.get_camera_2d() == _camera, "Gameplay camera is not active.")
	_verify_center("Character is off-center at spawn.")
	var initial_zoom := _camera.zoom.x
	_verify(is_equal_approx(initial_zoom, 1.5), "Starting zoom must be 1.5x.")
	await _wheel(MOUSE_BUTTON_WHEEL_UP)
	_verify(_camera.zoom.x > initial_zoom, "Wheel up did not zoom in through viewport input.")
	_verify_center("Wheel up moved character away from center.")
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_verify(is_equal_approx(_camera.zoom.x, initial_zoom), "Wheel down did not reverse wheel up.")
	await _wheel(MOUSE_BUTTON_WHEEL_UP, 0.5)
	_verify(_camera.zoom.x > initial_zoom and _camera.zoom.x < initial_zoom * _game.CAMERA_ZOOM_STEP, "Fractional wheel input was not respected.")
	var fractional_zoom := _camera.zoom.x
	await _wheel(MOUSE_BUTTON_WHEEL_UP, 1.0, false)
	_verify(is_equal_approx(_camera.zoom.x, fractional_zoom), "Wheel release changed zoom.")
	await _wheel(MOUSE_BUTTON_WHEEL_UP, 100.0)
	_verify(is_equal_approx(_camera.zoom.x, _game.CAMERA_MAX_ZOOM), "Zoom-in limit failed.")
	_verify_center("Character is off-center at maximum zoom.")
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN, 100.0)
	_verify(is_equal_approx(_camera.zoom.x, _game.CAMERA_MIN_ZOOM), "Zoom-out limit failed.")
	_verify_center("Character is off-center at minimum zoom.")
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_verify(is_equal_approx(_camera.zoom.x, 1.5), "Repeated wheel down went below 1.5x.")
	for menu_name in ["SpawnMenu", "ItemMenu", "InventoryMenu", "SpritePreview"]:
		var menus := {"SpawnMenu": _game.spawn_menu, "ItemMenu": _game.item_menu, "InventoryMenu": _game.inventory_menu, "SpritePreview": _game.sprite_preview}
		var menu: Control = menus[menu_name]
		menu.show()
		await _wheel(MOUSE_BUTTON_WHEEL_UP)
		_verify(is_equal_approx(_camera.zoom.x, _game.CAMERA_MIN_ZOOM), "Wheel changed map zoom with " + menu_name + " open.")
		menu.hide()
	await _wheel(MOUSE_BUTTON_WHEEL_UP, 0.0)
	_verify(_camera.zoom.x > _game.CAMERA_MIN_ZOOM, "Zero-factor wheel event did not zoom.")

	# Exercise normal physics movement and check the actual screen projection.
	var start := _actor.global_position
	var key := InputEventKey.new()
	key.keycode = KEY_D
	key.pressed = true
	Input.parse_input_event(key)
	for frame in 12:
		await physics_frame
		await process_frame
		_verify_center("Camera lost the character during movement.")
	key = InputEventKey.new()
	key.keycode = KEY_D
	key.pressed = false
	Input.parse_input_event(key)
	_verify(_actor.global_position.distance_to(start) > 1.0, "Movement check did not move the player.")
	_game.set_physics_process(false)

	# Near map boundaries the character must remain centered even when the
	# viewport extends beyond the authored map or the window is resized.
	for zoom_level in [1.5, 4.0]:
		_camera.zoom = Vector2.ONE * zoom_level
		for point in [Vector2(-1520, -3056), Vector2(1520, -3056), Vector2(16, 2640), Vector2(1520, 2640)]:
			_actor.global_position = point
			_game._update_map_camera()
			_verify_center("Character drifted from center near map boundary.")
	root.size = Vector2i(1920, 1080)
	await process_frame
	_game._update_map_camera()
	_verify_center("Resizing the viewport moved character off-center.")

	print("[Camera check] %d checks, %d failures." % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
