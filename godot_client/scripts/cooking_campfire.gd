class_name CookingCampfire
extends RefCounted
## Logic-only heat source. Firemaking will own lighting, lifetime and placement.
## Position and reach use the same simulation coordinates as PlayerState.
var position := Vector2.ZERO
var active := false
var cooking_reach := 2.0

func _init(at: Vector2 = Vector2.ZERO) -> void:
	position = at

func cooking_error(player: PlayerState) -> String:
	if not active:
		return "The campfire is no longer burning."
	if player.get_position().distance_to(position) > cooking_reach:
		return "Move closer to the campfire to cook."
	return ""
