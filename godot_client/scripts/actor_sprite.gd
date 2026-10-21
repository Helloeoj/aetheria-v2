class_name ActorSprite
extends CharacterBody2D

signal attack_finished

const WALK_HOLD_SECONDS := 0.22
const FALLBACK_ATTACK_SECONDS := 0.22
const HURT_FLASH_SECONDS := 0.16

var entity_id := ""
var size := Vector2(32, 32)
var color := Color(0.0, 0.0, 1.0)
var skin_id := ""
var facing := "south"
var targeted := false
var dead := false
var health_bar_offset := Vector2(0, -43)
var animated_sprite: AnimatedSprite2D
var attachment_rig: CharacterAttachmentRig

var _collision: CollisionShape2D
var _walk_remaining := 0.0
var _attack_remaining := 0.0
var _attack_duration := 0.0
var _attack_direction := Vector2.DOWN
var _fallback_attack := false
var _hurt_remaining := 0.0
var _visual_scale := 1.0
var _has_visual := false


func configure(sprite_size: Vector2, sprite_color: Color, id: String) -> ActorSprite:
	size = sprite_size
	color = sprite_color
	entity_id = id
	# The complete actor sorts at its feet; gear stays inside this subtree.
	z_index = 0
	y_sort_enabled = false
	collision_layer = 2
	collision_mask = 1
	_ensure_nodes()
	var body_shape := RectangleShape2D.new()
	body_shape.size = size * 0.75
	_collision.shape = body_shape
	queue_redraw()
	return self


func _ensure_nodes() -> void:
	if _collision == null:
		_collision = CollisionShape2D.new()
		_collision.name = "BodyCollision"
		add_child(_collision)
	if animated_sprite == null:
		animated_sprite = AnimatedSprite2D.new()
		animated_sprite.name = "CharacterVisual"
		animated_sprite.centered = true
		animated_sprite.z_index = 0
		animated_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		animated_sprite.animation_finished.connect(_on_animation_finished)
		add_child(animated_sprite)
	if attachment_rig == null:
		attachment_rig = CharacterAttachmentRig.new()
		attachment_rig.name = "EquipmentSkeleton"
		animated_sprite.add_child(attachment_rig)
		attachment_rig.bind_to(animated_sprite)


func set_skin(new_skin_id: String) -> void:
	if skin_id == new_skin_id and animated_sprite != null:
		return
	_ensure_nodes()
	skin_id = new_skin_id
	_attack_remaining = 0.0
	_fallback_attack = false
	animated_sprite.position = Vector2.ZERO
	var data := CharacterSpriteLibrary.get_skin(skin_id)
	_has_visual = not data.is_empty()
	animated_sprite.visible = _has_visual
	if _has_visual:
		var dimensions: Array = data.get("size", [60, 60])
		var width := float(dimensions[0])
		var height := float(dimensions[1])
		_visual_scale = float(data.get("display_height", 48.0)) / maxf(height, 1.0)
		var foot: Array = data.get("foot_position", [width * 0.5, height])
		# Authored animation frames add symmetric transparent padding around
		# the rotation canvas. Center them first, then apply the shared feet
		# anchor; this keeps their larger canvases from shifting the actor.
		animated_sprite.offset = Vector2(width, height) * 0.5 - Vector2(float(foot[0]), float(foot[1]))
		animated_sprite.scale = Vector2.ONE * _visual_scale
		animated_sprite.sprite_frames = CharacterSpriteLibrary.get_frames(skin_id)
		health_bar_offset = Vector2(0.0, -float(foot[1]) * _visual_scale - 10.0)
		_play_locomotion()
	else:
		health_bar_offset = Vector2(0.0, -size.y - 10.0)
	attachment_rig.set_skin(skin_id)
	queue_redraw()


## Equipment visuals are separate scenes; equipping never replaces this skin.
func set_equipment(equipment: Dictionary) -> void:
	_ensure_nodes()
	attachment_rig.set_equipment(equipment)


func set_socket_debug(enabled: bool) -> void:
	_ensure_nodes()
	attachment_rig.debug_sockets = enabled


## Displacement is supplied after map projection, in screen coordinates.
## A brief walk hold also covers actors moved in discrete simulation ticks.
func update_visual_motion(screen_displacement: Vector2) -> void:
	if dead or screen_displacement.length_squared() < 0.000001:
		return
	_walk_remaining = WALK_HOLD_SECONDS
	face_direction(screen_displacement)
	if _attack_remaining <= 0.0:
		_play_locomotion()


func face_direction(screen_direction: Vector2) -> void:
	if screen_direction.is_zero_approx() or dead or _attack_remaining > 0.0:
		return
	# Godot screen Y increases downward: east=0, south=PI/2.
	var clockwise := posmod(int(round(screen_direction.angle() / (PI / 4.0))), 8)
	var directions: Array[String] = [
		"east", "south-east", "south", "south-west",
		"west", "north-west", "north", "north-east"
	]
	var next_facing := directions[clockwise]
	if facing == next_facing:
		return
	facing = next_facing
	if _attack_remaining <= 0.0:
		_play_locomotion()


func play_attack(screen_direction: Vector2 = Vector2.ZERO) -> void:
	if dead:
		return
	_ensure_nodes()
	_attack_remaining = 0.0
	face_direction(screen_direction)
	_attack_direction = screen_direction.normalized() if not screen_direction.is_zero_approx() else _facing_vector()
	var animation := CharacterSpriteLibrary.animation_name("attack", facing)
	_fallback_attack = not _can_play(animation)
	if _fallback_attack:
		_attack_duration = FALLBACK_ATTACK_SECONDS
		_play_animation(CharacterSpriteLibrary.animation_name("idle", facing), true)
	else:
		var frames := animated_sprite.sprite_frames
		_attack_duration = float(frames.get_frame_count(animation)) / frames.get_animation_speed(animation)
		_play_animation(animation, true)
	_attack_remaining = maxf(_attack_duration, 0.05)
	queue_redraw()


func play_hurt() -> void:
	if not dead:
		_hurt_remaining = HURT_FLASH_SECONDS


## Explicit preview/action changes can interrupt an attack immediately.
func cancel_action() -> void:
	_walk_remaining = 0.0
	_attack_remaining = 0.0
	_attack_duration = 0.0
	_fallback_attack = false
	if animated_sprite != null:
		animated_sprite.position = Vector2.ZERO
	if not dead:
		_play_locomotion()


func set_targeted(value: bool) -> void:
	targeted = value
	queue_redraw()


func set_dead(value: bool) -> void:
	if dead == value:
		return
	dead = value
	_walk_remaining = 0.0
	_attack_remaining = 0.0
	_hurt_remaining = 0.0
	_fallback_attack = false
	if _collision != null:
		_collision.set_deferred("disabled", value)
	if animated_sprite != null:
		animated_sprite.position = Vector2.ZERO
		animated_sprite.modulate = Color(0.55, 0.55, 0.55) if dead else Color.WHITE
		if dead:
			animated_sprite.stop()
		else:
			_play_locomotion()
	queue_redraw()


func get_health_bar_offset() -> Vector2:
	return health_bar_offset


func _process(delta: float) -> void:
	if dead:
		return
	var was_walking := _walk_remaining > 0.0
	_walk_remaining = maxf(_walk_remaining - delta, 0.0)
	if _attack_remaining > 0.0:
		_attack_remaining = maxf(_attack_remaining - delta, 0.0)
		if _fallback_attack and animated_sprite != null:
			var progress := 1.0 - _attack_remaining / _attack_duration
			animated_sprite.position = _attack_direction * sin(progress * PI) * minf(size.x * 0.22, 7.0)
		if _attack_remaining <= 0.0:
			_finish_attack()
	elif was_walking and _walk_remaining <= 0.0:
		_play_locomotion()
	_hurt_remaining = maxf(_hurt_remaining - delta, 0.0)
	if animated_sprite != null:
		var flash := _hurt_remaining / HURT_FLASH_SECONDS
		animated_sprite.modulate = Color.WHITE.lerp(Color(1.0, 0.35, 0.35), flash)


func _play_locomotion() -> void:
	var action := "walk" if _walk_remaining > 0.0 else "idle"
	_play_animation(CharacterSpriteLibrary.animation_name(action, facing))


func _play_animation(animation: StringName, restart: bool = false) -> void:
	if not _can_play(animation):
		return
	if restart or animated_sprite.animation != animation or not animated_sprite.is_playing():
		if restart:
			animated_sprite.stop()
		animated_sprite.play(animation)


func _can_play(animation: StringName) -> bool:
	return animated_sprite != null and animated_sprite.sprite_frames != null \
		and animated_sprite.sprite_frames.has_animation(animation) \
		and animated_sprite.sprite_frames.get_frame_count(animation) > 0


func _finish_attack() -> void:
	_attack_remaining = 0.0
	_fallback_attack = false
	if animated_sprite != null:
		animated_sprite.position = Vector2.ZERO
	_play_locomotion()
	attack_finished.emit()


func _on_animation_finished() -> void:
	if _attack_remaining > 0.0 and not _fallback_attack:
		_finish_attack()


func _facing_vector() -> Vector2:
	var direction_index := CharacterSpriteLibrary.DIRECTIONS.find(facing)
	return Vector2.DOWN.rotated(-float(direction_index) * PI / 4.0)


func _draw() -> void:
	var radius := size.x * 0.42
	# The origin and collision stay at the feet in every animation frame.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.48))
	draw_circle(Vector2.ZERO, radius, Color(0.0, 0.0, 0.0, 0.24))
	if targeted and not dead:
		draw_arc(Vector2.ZERO, radius + 3.0, 0.0, TAU, 48, Color(1.0, 0.25, 0.15, 0.95), 2.0, true)
	draw_set_transform(Vector2.ZERO)
	if not _has_visual:
		draw_rect(Rect2(Vector2(-size.x * 0.5, -size.y), size), color)
