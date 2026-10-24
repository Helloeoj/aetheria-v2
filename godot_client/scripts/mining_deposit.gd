class_name MiningDeposit
extends Node2D
## Authored identity/geometry only. The region's MiningService owns all state.
@export var deposit_id := ""
@export var ore_item_id := 235
@export var approach_offset := Vector2.ZERO
@export var interaction_radius := 48.0
@export var click_rect := Rect2(-16, -16, 32, 32)
@export var enabled := true
var state: Dictionary = {}

func _enter_tree() -> void:
	add_to_group("mining_deposit")

func approach_position() -> Vector2:
	return to_global(approach_offset)

func contains_global_point(point: Vector2) -> bool:
	return enabled and is_visible_in_tree() and click_rect.has_point(to_local(point))

func apply_state(value: Dictionary) -> void:
	if String(value.get("deposit_id", "")) != deposit_id or int(value.get("generation", -1)) < int(state.get("generation", -1)):
		return
	state = value.duplicate(true)
