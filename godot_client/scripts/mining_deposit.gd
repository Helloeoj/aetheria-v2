class_name MiningDeposit
extends Node2D
## Authored identity/geometry only. The region's MiningService owns all state.
@export var deposit_id := ""
@export var ore_item_id := 330
@export var approach_offset := Vector2.ZERO
@export var interaction_radius := 48.0
@export var click_rect := Rect2(-16, -16, 32, 32)
@export var enabled := true
@export var visual_path: NodePath
@export var available_texture: Texture2D
@export var depleted_texture: Texture2D
var state: Dictionary = {}

func _enter_tree() -> void:
	add_to_group("mining_deposit")

func _ready() -> void:
	_update_visual()

func approach_position() -> Vector2:
	return to_global(approach_offset)

func contains_global_point(point: Vector2) -> bool:
	return enabled and is_visible_in_tree() and click_rect.has_point(to_local(point))

func apply_state(value: Dictionary) -> void:
	if String(value.get("deposit_id", "")) != deposit_id or int(value.get("generation", -1)) < int(state.get("generation", -1)):
		return
	state = value.duplicate(true)
	_update_visual()

func _update_visual() -> void:
	if visual_path.is_empty():
		return
	var visual := get_node_or_null(visual_path) as Sprite2D
	var texture := depleted_texture if String(state.get("state", "available")) == "depleted" else available_texture
	if visual != null and texture != null:
		visual.texture = texture
