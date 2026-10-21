extends Node
## Owns the world stove and panel lifecycle; recipes/transactions stay in CookingSession.
const PanelScript = preload("res://scripts/ui_cooking.gd")
var game: Node
var panel: Control

func configure(owner_game: Node) -> void:
	game = owner_game
	panel = PanelScript.new()
	panel.name = "CookingPanel"
	game.ui_root.add_child(panel)
	panel.configure(game, self)

func can_use(station: Node2D) -> bool:
	if not is_instance_valid(station) or not station.is_current(game) or not station.in_range(game):
		return false
	var travel := get_node_or_null("/root/SceneTravel")
	return game.player.current_hp > 0 and not game.player.in_combat and game.player.current_target.is_empty() and not game.combat.active_spell_casts.has(game.player.entity_id) and (travel == null or not travel.is_transitioning())

func open(station: Node2D) -> void:
	if not can_use(station):
		game.show_fishing_notice("Move closer to the stove and finish combat before cooking.")
		return
	if panel.visible:
		panel.close()
	game.spawn_menu.hide()
	game.item_menu.hide()
	game.inventory_menu.hide()
	game.skill_debug_panel.hide()
	if game.crafting_panel != null:
		game.crafting_panel.close()
	if game.fishing_panel.visible:
		game.fishing_panel.close()
	game.context_menu.dismiss()
	game.interactions.cancel_walk()
	game.interactions.clear_drop_selection()
	game._reset_held_movement()
	game.spell_cast_requested = false
	station.update_heat(game)
	panel.open(station)

func _process(delta: float) -> void:
	# One tick per presented frame; physics catch-up must not spend an unseen prompt.
	advance(delta)

func advance(delta: float) -> void:
	if not _sync_attempt():
		return
	_record_results(panel.session.advance(delta))
	panel.refresh()

func flip() -> void:
	if not _sync_attempt():
		return
	_record_results(panel.session.flip())
	panel.refresh()

func _sync_attempt() -> bool:
	if panel == null or not panel.visible:
		return false
	var station: Node2D = panel.station
	if not can_use(station):
		panel.close()
		return false
	station.update_heat(game)
	var actor: CombatActor = game.combat.actors.get(game.player.entity_id)
	if actor != null:
		game.player.x = actor.x
		game.player.y = actor.y
		game.player.current_hp = actor.hp
	return true

func _record_results(results: Array[Dictionary]) -> void:
	for result: Dictionary in results:
		if int(result.experience) > 0:
			game.skill_training_session.record_event({"type": "skill_experience_gained", "skill": "cooking", "experience_gained": int(result.experience)})
	if not results.is_empty():
		game._refresh_character_ui()

func _exit_tree() -> void:
	if is_instance_valid(panel) and panel.session != null:
		panel.session.close()
