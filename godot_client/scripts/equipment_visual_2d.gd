class_name EquipmentVisual2D
extends Node2D

## Direction artwork follows the actor's facing, not its animation frame timer.
## Grip coordinates are authored in each original texture's pixel canvas.
@export var directional_textures: Dictionary = {}
@export var grip_positions: Dictionary = {}
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
