class_name MovementController
extends RefCounted

var holding := {"up": false, "down": false, "left": false, "right": false}
var direction_resolver: Callable

func _init(resolver: Callable = Callable()) -> void:
	direction_resolver = resolver if resolver.is_valid() else Callable(self, "_default_direction_resolver")

func on_input(input_payload: Variant, pressed: bool) -> void:
	var direction: String = direction_resolver.call(input_payload)
	if holding.has(direction):
		holding[direction] = pressed

func on_key_press(key: Variant) -> void:
	on_input(key, true)

func on_key_release(key: Variant) -> void:
	on_input(key, false)

func get_move_vector() -> Vector2:
	var dx := 0.0
	var dy := 0.0
	if holding.left:
		dx -= 1.0
	if holding.right:
		dx += 1.0
	if holding.up:
		dy += 1.0
	if holding.down:
		dy -= 1.0
	var direction := Vector2(dx, dy)
	return direction.normalized() if not direction.is_zero_approx() else Vector2.ZERO

func _default_direction_resolver(input_payload: Variant) -> String:
	if input_payload is String:
		var normalized := String(input_payload).to_lower()
		if normalized in ["w", "up"]:
			return "up"
		if normalized in ["s", "down"]:
			return "down"
		if normalized in ["a", "left"]:
			return "left"
		if normalized in ["d", "right"]:
			return "right"
	if input_payload is InputEventKey:
		match input_payload.keycode:
			KEY_W, KEY_UP:
				return "up"
			KEY_S, KEY_DOWN:
				return "down"
			KEY_A, KEY_LEFT:
				return "left"
			KEY_D, KEY_RIGHT:
				return "right"
	return ""
