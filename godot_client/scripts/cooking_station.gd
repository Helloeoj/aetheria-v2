class_name CookingStation
extends Node2D
## A permanent stove uses the existing heat-source/session rules.
@export var station_name := "Tavern stove"
@export var approach_offset := Vector2(15, 52)
@export var click_rect := Rect2(-70, -32, 140, 64)
@export var interaction_radius := 42.0
@export var enabled := true
var heat := CookingCampfire.new()

func _enter_tree() -> void:
	add_to_group("cooking_station")

func _exit_tree() -> void:
	heat.active = false

func approach_position() -> Vector2:
	return to_global(approach_offset)

func contains_global_point(point: Vector2) -> bool:
	return enabled and is_visible_in_tree() and click_rect.has_point(to_local(point))

func is_current(game: Node) -> bool:
	return enabled and is_inside_tree() and is_visible_in_tree() and is_instance_valid(game) and game.get_parent() != null and game.get_parent().is_ancestor_of(self)

func in_range(game: Node) -> bool:
	var sprite: Node2D = game.actor_sprites.get(game.player.entity_id)
	return is_instance_valid(sprite) and sprite.global_position.distance_to(approach_position()) <= interaction_radius

func update_heat(game: Node) -> void:
	heat.active = is_current(game)
	var point: Vector2 = game.to_local(approach_position())
	heat.position = Vector2((point.x - game.map_origin.x) / game.TILE_SIZE, (game.map_origin.y + game.map_height - point.y) / game.TILE_SIZE)
	heat.cooking_reach = interaction_radius / game.TILE_SIZE
