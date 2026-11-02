class_name EquipmentVisual2D
extends Node2D

## Direction artwork follows the actor's facing, not its animation frame timer.
## Grip coordinates are authored in each original texture's pixel canvas.
@export var directional_textures: Dictionary = {}
@export var grip_positions: Dictionary = {}
@export var support_grip_positions: Dictionary = {}
@export var weapon_family: String = ""
@export var source_scale := 0.5
@export var keep_upright := true

var current_facing := ""


func _ready() -> void:
	if current_facing.is_empty():
		set_attachment_facing("south")


func set_attachment_facing(direction: String) -> void:
	var artwork := get_node_or_null("Artwork") as Sprite2D
	var texture := directional_textures.get(direction) as Texture2D
	if artwork == null or texture == null or not grip_positions.has(direction):
		visible = false
		return
	current_facing = direction
	artwork.texture = texture
	artwork.centered = false
	artwork.scale = Vector2.ONE * source_scale
	var grip: Vector2 = grip_positions[direction]
	artwork.position = -grip * source_scale
	# The socket can angle swords; an already drawn directional shield must
	# keep its authored orientation while its grip follows that same socket.
	if keep_upright:
		var socket := get_parent() as Node2D
		rotation = -socket.rotation if socket != null else 0.0
	visible = true


## Grips remain in the original direction texture's pixel canvas.
func get_weapon_profile(direction: String) -> Dictionary:
	if not directional_textures.has(direction) or not grip_positions.has(direction):
		return {}
	return {
		"family": weapon_family,
		"texture": directional_textures[direction],
		"pivot": grip_positions[direction],
		"support_grip": support_grip_positions.get(direction, grip_positions[direction]),
		"source_scale": source_scale
	}


func set_attachment_pose(context: Dictionary) -> void:
	var socket := get_parent() as Node2D
	var socket_rotation := socket.rotation if socket != null else 0.0
	var motion: Dictionary = context.get("weapon_motion", {})
	if not motion.is_empty() and bool(motion.get("active", false)):
		var root_value: Variant = context.get("pose", {}).get(String(context.get("root_socket", "right_hand")), Vector2.ZERO)
		var root_point := Vector2.ZERO
		if root_value is Vector2:
			root_point = root_value
		elif root_value is Array and root_value.size() >= 2:
			root_point = Vector2(float(root_value[0]), float(root_value[1]))
		var primary: Vector2 = motion.get("primary", root_point + Vector2(context.get("padding", Vector2.ZERO)))
		# Motion is in the fitted 80px body canvas; the socket is in the
		# unpadded source frame and can still carry a legacy sword angle.
		position = (primary - Vector2(context.get("padding", Vector2.ZERO)) - root_point).rotated(-socket_rotation)
		rotation = float(motion.get("rotation", 0.0)) - socket_rotation
	elif weapon_family == "pickaxe":
		position = Vector2.ZERO
		rotation = -socket_rotation
