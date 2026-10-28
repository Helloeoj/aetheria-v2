extends Node2D
## Development-only commands on the existing movement lattice. Never edits maps.
const HELP := "::tele x y (or ::teleport) · ::pos · ::tile (cursor) · ::coords [on|off] · ::help. X east, Y north; coordinates belong to this area."
var game: Node2D
var overlay_enabled := false
var coordinate_label: Label
var floor_support := preload("res://scripts/dev_tools/tile_floor_support.gd").new()

func configure(owner_game: Node2D) -> void:
	game = owner_game
	name = "TileCommands"
	z_index = 8
	coordinate_label = Label.new()
	coordinate_label.name = "TileCoordinates"
	coordinate_label.position = Vector2(22, 96)
	coordinate_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coordinate_label.add_theme_font_size_override("font_size", 15)
	coordinate_label.add_theme_color_override("font_color", Color("b4f5f0"))
	coordinate_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	coordinate_label.add_theme_constant_override("shadow_offset_x", 1)
	coordinate_label.add_theme_constant_override("shadow_offset_y", 1)
	coordinate_label.hide()
	game.ui_root.add_child(coordinate_label)
	floor_support.configure(game.get_parent())

func _grid_ready() -> bool:
	return is_instance_valid(game) and game.map_scene_mode and game.grid_adapter != null and game.grid_adapter.completed

func cell_at_global(point: Vector2) -> Vector2i:
	return game.world.cell_grid.cell_at(game.grid_adapter.simulation_point(point))

func _location(cell: Vector2i) -> String:
	return "%s · tile (%d, %d) · ::tele %d %d · %s" % [game.area_name, cell.x, cell.y, cell.x, cell.y, game.get_parent().scene_file_path]

func execute(text: String) -> String:
	var words := RegEx.create_from_string("\\S+").search_all(text.strip_edges())
	if words.is_empty():
		return HELP
	var command: String = words[0].get_string().to_lower()
	if command == "::help":
		return HELP
	if not _grid_ready():
		return "Tile coordinates are not ready. Enter a map and wait for it to load."
	var travel := get_node_or_null("/root/SceneTravel")
	if travel != null and travel.is_transitioning():
		return "Wait for the area transition to finish."
	match command:
		"::pos":
			if words.size() != 1:
				return "Usage: ::pos"
			return _location(game.world.cell_grid.cell_at(game.player.get_position()))
		"::tile":
			if words.size() != 1:
				return "Usage: ::tile"
			var cell := cell_at_global(game.get_global_mouse_position())
			var center: Vector2 = game.world.cell_grid.center(cell)
			var local_pixel: Vector2 = game.get_parent().to_local(game.to_global(game._screen_position(center.x, center.y)))
			return _location(cell) + " · placement center (%s, %s) px" % [local_pixel.x, local_pixel.y]
		"::coords":
			if words.size() > 2 or (words.size() == 2 and words[1].get_string().to_lower() not in ["on", "off"]):
				return "Usage: ::coords [on|off]"
			overlay_enabled = not overlay_enabled if words.size() == 1 else words[1].get_string().to_lower() == "on"
			coordinate_label.visible = overlay_enabled
			queue_redraw()
			return "Tile coordinates " + ("ON. Hover a tile; ::tile prints its address and placement center." if overlay_enabled else "OFF.")
		"::tele", "::teleport":
			if words.size() != 3:
				return "Usage: ::tele x y (two whole tile coordinates, no depth)."
			var values: Array[int] = []
			for index in [1, 2]:
				var value: String = words[index].get_string()
				# Bound before int conversion: neither overflow nor decimals can alias a tile.
				if value.length() > 11 or RegEx.create_from_string("^[+-]?[0-9]+$").search(value) == null:
					return "Use two whole tile coordinates: ::tele x y"
				var number := value.to_int()
				if number < -2147483648 or number > 2147483647:
					return "Tile coordinates are out of range."
				values.append(number)
			return teleport(Vector2i(values[0], values[1]))
	return "Unknown command. " + HELP

func teleport(cell: Vector2i) -> String:
	if not OS.is_debug_build() or OS.has_feature("tester_client") or Network.online() or Network.authenticated:
		return "Teleport is a developer sandbox command. Online characters require server permission."
	if not _grid_ready():
		return "Wait for the map's collision geometry to load."
	var travel := get_node_or_null("/root/SceneTravel")
	if travel != null and travel.is_transitioning():
		return "Wait for the area transition to finish."
	var actor: CombatActor = game.combat.actors.get(game.player.entity_id)
	if actor == null or not actor.is_alive or game.player.current_hp <= 0:
		return "You must be alive to teleport."
	if game.fishing_panel.visible or (game.cooking_controller != null and game.cooking_controller.panel.visible):
		return "Finish fishing or cooking before teleporting."
	var grid: HiddenGrid = game.world.cell_grid
	var destination := grid.center(cell)
	if not grid.contains(destination):
		return "That tile is outside this area's bounds."
	# Fresh body query: cached pathfinding results must not approve a blocked tile.
	if not grid.clear_point(destination):
		return "That tile is blocked. Choose a clear floor tile."
	if not floor_support.supports_body(game.to_global(game._screen_position(destination.x, destination.y))):
		return "That tile has no supported floor for the player."
	for other: CombatActor in game.combat.actors.values():
		if other.entity_id != actor.entity_id and other.is_alive and absf(other.x - destination.x) < 0.75 and absf(other.y - destination.y) < 0.75:
			return "That tile is occupied."
	game._reset_held_movement()
	game.interactions.cancel_walk()
	game._clear_target()
	game.spell_cast_requested = false
	game.combat.active_spell_casts.erase(actor.entity_id)
	if game.offline_mining != null:
		game.offline_mining.stop("teleport")
	actor.x = destination.x
	actor.y = destination.y
	game.player.x = destination.x
	game.player.y = destination.y
	actor.logical_cell = cell
	actor.grid_active = false
	if game.world.grid != null:
		var traveller: GridTraveller = game.world.grid_traveller(actor.entity_id)
		traveller.reset(destination, grid)
		game.world.actor_grid_state(actor.entity_id, traveller)
	# Do not animate a teleport as a long walking stride.
	game.visual_positions[actor.entity_id] = game._screen_position(destination.x, destination.y)
	game._update_sprite_position(actor.entity_id)
	game._update_map_camera()
	game.queue_redraw()
	return "Teleported to " + _location(cell)

func _process(_delta: float) -> void:
	if not overlay_enabled or not _grid_ready():
		return
	var player_cell: Vector2i = game.world.cell_grid.cell_at(game.player.get_position())
	var cursor_cell := cell_at_global(game.get_global_mouse_position())
	coordinate_label.text = "%s · Player (%d, %d)\nCursor (%d, %d) · ::tile to record · ::coords off to hide" % [game.area_name, player_cell.x, player_cell.y, cursor_cell.x, cursor_cell.y]
	queue_redraw()

func _draw() -> void:
	if not overlay_enabled or not _grid_ready():
		return
	var cell := cell_at_global(game.get_global_mouse_position())
	var center: Vector2 = game.world.cell_grid.center(cell)
	if not game.world.cell_grid.contains(center):
		return
	var point: Vector2 = game._screen_position(center.x, center.y)
	draw_rect(Rect2(point - Vector2(16, 16), Vector2(32, 32)), Color(0.35, 1.0, 0.9, 0.85), false, 1.0)
