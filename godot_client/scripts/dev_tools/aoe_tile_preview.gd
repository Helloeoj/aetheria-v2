extends Node2D
## Debug aid only, not spell artwork or a targeting interface.
const Footprint := preload("res://scripts/spell_footprint.gd")
var game: Node2D
var enabled := false
var authoritative_cast: Dictionary = {}

func toggle() -> void:
	if not OS.is_debug_build() or OS.has_feature("tester_client"):
		return
	enabled = not enabled
	print("[AoE preview] ", "ON — PROVISIONAL sizes; Ctrl+Shift+V to hide" if enabled else "OFF")
	queue_redraw()

func descriptor() -> Dictionary:
	if not enabled or not is_instance_valid(game):
		return {}
	if not authoritative_cast.is_empty():
		return authoritative_cast
	var cast: Dictionary = game.combat.active_spell_casts.get(game.player.entity_id,{})
	if not cast.is_empty():
		if cast.spell.get("kind") != "area":
			return {}
		return {"spell":cast.spell, "target_cell":[cast.target_cell.x,cast.target_cell.y]}
	var spell: Dictionary = GameData.get_spell(game.player.selected_spell_id)
	var actor: CombatActor = game.combat.actors.get(game.player.current_target)
	if spell.get("kind") != "area" or actor == null or not actor.is_alive:
		return {}
	var cell: Vector2i
	if Network.online() and game.world.grid != null:
		cell = actor.logical_cell
	else:
		cell = game.world.occupied_cell(actor.entity_id)
	return {"spell":spell,"target_cell":[cell.x,cell.y]}

func affected_cells() -> Array[Vector2i]:
	var data := descriptor()
	if data.is_empty():
		return []
	var anchor: Array = data.get("target_cell",[])
	if anchor.size() != 2:
		return []
	return Footprint.cells(game.world.cell_grid,Vector2i(int(anchor[0]),int(anchor[1])),data.get("spell",{}))

func _process(_delta: float) -> void:
	if enabled:
		queue_redraw()

func _draw() -> void:
	var cells := affected_cells()
	if cells.is_empty():
		return
	for cell: Vector2i in cells:
		var center: Vector2 = game.world.cell_grid.center(cell)
		var point: Vector2 = game._screen_position(center.x,center.y)
		var rect := Rect2(point-Vector2(16,16),Vector2(32,32))
		draw_rect(rect,Color(1.0,0.68,0.12,0.19))
		draw_rect(rect,Color(1.0,0.77,0.24,0.85),false,1.0)
	var first: Vector2 = game.world.cell_grid.center(cells[-1])
	draw_string(ThemeDB.fallback_font,game._screen_position(first.x,first.y)+Vector2(-50,-22),"PROVISIONAL AoE",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color(1.0,0.82,0.35))
