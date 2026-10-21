class_name LegacyProjectileSprite
extends RefCounted

const TILE_SIZE := 32

var p: Variant
var emoji := "➤"
var x := 0.0
var y := 0.0
var marked_for_removal := false

func _init(projectile_obj: Variant, projectile_emoji: String = "➤") -> void:
	p = projectile_obj
	emoji = projectile_emoji
	x = float(_read(p, "start_x", 0.0))
	y = float(_read(p, "start_y", 0.0))

func update(active_monsters: Array) -> void:
	if marked_for_removal:
		return
	var speed := float(_read(p, "speed_tiles_per_tick", 0.0))
	var current_x := float(_read(p, "current_x", x)) + float(_read(p, "dir_x", 0.0)) * speed
	var current_y := float(_read(p, "current_y", y)) + float(_read(p, "dir_y", 0.0)) * speed
	_write(p, "current_x", current_x)
	_write(p, "current_y", current_y)
	x = current_x
	y = current_y
	var start := Vector2(float(_read(p, "start_x", x)), float(_read(p, "start_y", y)))
	if Vector2(x, y).distance_to(start) >= float(_read(p, "max_range", 0.0)):
		marked_for_removal = true
		return
	var target: Variant = _read(p, "target", null)
	if target == null or int(_read(target, "current_hp", 0)) <= 0:
		marked_for_removal = true
		return
	if Vector2(x, y).distance_to(Vector2(float(_read(target, "x", 0.0)), float(_read(target, "y", 0.0)))) < 0.5:
		var damage := int(p.call("resolve_hit"))
		_write(target, "current_hp", int(_read(target, "current_hp", 0)) - damage)
		marked_for_removal = true

func get_world_position() -> Vector2:
	return Vector2(x * TILE_SIZE, y * TILE_SIZE)

func _read(source: Variant, key: String, fallback: Variant) -> Variant:
	if source is Dictionary:
		return source.get(key, fallback)
	if source is Object:
		var value: Variant = source.get(key)
		return fallback if value == null else value
	return fallback

func _write(target: Variant, key: String, value: Variant) -> void:
	if target is Dictionary:
		target[key] = value
	elif target is Object:
		target.set(key, value)
