class_name CraftingStation
extends Node2D

var station_id := ""
var station_name := ""
var simulation_position := Vector2.ZERO

func setup(id: String, title: String, point: Vector2) -> void:
	station_id = id
	station_name = title
	simulation_position = point
	add_to_group("crafting_station")
	var label := Label.new()
	label.text = title
	label.position = Vector2(-70, -44)
	label.size.x = 140
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("f1d18b"))
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	queue_redraw()

func contains_global_point(point: Vector2) -> bool:
	return Rect2(-25, -30, 50, 45).has_point(to_local(point))

func is_available(player: PlayerState) -> bool:
	return player != null and player.current_hp > 0 and not player.in_combat and player.current_target.is_empty() and player.get_position().distance_to(simulation_position) <= 2.5

func _draw() -> void:
	draw_rect(Rect2(-18, -20, 36, 24), Color("322b22"))
	draw_rect(Rect2(-18, -20, 36, 24), Color("d6b56e"), false, 2)
	draw_line(Vector2(-12, 6), Vector2(12, 6), Color("d6b56e"), 2)
