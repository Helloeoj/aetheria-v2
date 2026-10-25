class_name CavePortal
extends Node2D
## A deliberate entrance interaction. Merely walking across it never changes scenes.
@export var portal_name := "Golem Kingdom"
@export_file("*.tscn") var destination_scene := ""
@export var destination_spawn_id := "entrance"
@export var approach_offset := Vector2(0, 40)
@export_range(1.0, 512.0, 1.0) var interaction_radius := 72.0
@export var hit_polygon := PackedVector2Array()
@export var click_rect := Rect2(-48, -96, 96, 96)
@export var enabled := true

func _enter_tree() -> void:
	add_to_group("cave_portal")

func contains_global_point(point: Vector2) -> bool:
	if not enabled or not is_visible_in_tree():
		return false
	var local_point := to_local(point)
	if hit_polygon.size() >= 3:
		return Geometry2D.is_point_in_polygon(local_point, hit_polygon)
	return click_rect.has_point(local_point)

func approach_position() -> Vector2:
	return to_global(approach_offset)

func is_in_interaction_range(game: Node) -> bool:
	var rules: Script = load("res://scripts/interaction_approach.gd")
	return rules.in_range(game.world, game.combat.actors.get(game.player.entity_id), rules.describe(game, self, "portal"))

func try_enter(game: Node) -> bool:
	if not enabled or not is_visible_in_tree() or destination_scene.is_empty() or not is_instance_valid(game):
		return false
	var map_root := game.get_parent()
	if map_root == null or not map_root.is_ancestor_of(self):
		return false
	var actor: CombatActor = game.combat.actors.get(game.player.entity_id)
	if actor == null or not actor.is_alive or game.player.current_hp <= 0:
		return false
	if not is_in_interaction_range(game):
		return false
	var travel := get_tree().root.get_node_or_null("SceneTravel")
	if travel == null or travel.is_transitioning():
		return false
	return travel.request_travel(game, destination_scene, destination_spawn_id)
