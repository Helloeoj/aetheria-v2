extends Node
## Keeps the character alive while independently loaded areas are replaced.

signal transition_finished(scene_path: String)
signal transition_failed(message: String)

const FADE_SECONDS := 0.18

var pending_spawn_id := ""
var _player: PlayerState
var _training_session: SkillTrainingSession
var _transitioning := false
var _overlay: CanvasLayer
var _cover: ColorRect
var _loading_label: Label
var _source_scene: Node
var _source_process_mode: Node.ProcessMode
var _previous_spawn_id := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay = CanvasLayer.new()
	_overlay.name = "AreaLoadingScreen"
	_overlay.layer = 120
	add_child(_overlay)
	_cover = ColorRect.new()
	_cover.name = "LoadingCover"
	_cover.color = Color(0.025, 0.018, 0.014, 1.0)
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_cover.modulate.a = 0.0
	_cover.hide()
	_overlay.add_child(_cover)
	_loading_label = Label.new()
	_loading_label.text = "Entering Golem Kingdom…"
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_label.add_theme_font_size_override("font_size", 26)
	_loading_label.add_theme_color_override("font_color", Color(0.88, 0.75, 0.55))
	_loading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.add_child(_loading_label)


func _input(_event: InputEvent) -> void:
	if _transitioning:
		get_viewport().set_input_as_handled()


func bind_game(game: Node) -> bool:
	if _player != null:
		game.set("player", _player)
		game.set("skill_training_session", _training_session)
		return true
	_player = game.get("player") as PlayerState
	_training_session = game.get("skill_training_session") as SkillTrainingSession
	return false


func resolve_spawn(game: Node) -> void:
	if pending_spawn_id.is_empty() or not is_instance_valid(game.get_parent()):
		return
	var marker := game.get_parent().get_node_or_null("SpawnPoints/" + pending_spawn_id) as Node2D
	if marker == null:
		return
	var player := game.get("player") as PlayerState
	if player == null or not game is Node2D:
		return
	# Artwork and the actor are in the game's local canvas; simulation Y points up.
	var local_point := (game as Node2D).to_local(marker.global_position)
	var origin: Vector2 = game.get("map_origin")
	var height: float = game.get("map_height")
	var tile_size: float = game.TILE_SIZE
	player.x = (local_point.x - origin.x) / tile_size
	player.y = (origin.y + height - local_point.y) / tile_size
	pending_spawn_id = ""


func is_transitioning() -> bool:
	return _transitioning


func request_travel(game: Node, destination_scene: String, spawn_id: String) -> bool:
	if _transitioning or not is_instance_valid(game) or not game.is_inside_tree():
		return false
	var player := game.get("player") as PlayerState
	if player == null:
		return false
	_sync_player_actor(game, player)
	if player.current_hp <= 0:
		_notice(game, "You must be alive to enter another area.")
		return false
	var fishing_panel := game.get("fishing_panel") as Control
	if fishing_panel != null and fishing_panel.visible:
		_notice(game, "Finish fishing before entering another area.")
		return false
	if spawn_id.is_empty() or not ResourceLoader.exists(destination_scene, "PackedScene"):
		_fail_request(game, "The destination area is unavailable.")
		return false
	var cooking: Node = game.get("cooking_controller")
	if cooking != null and cooking.panel.visible:
		cooking.panel.close()
	# Keep one background loader: subthread fanout fails to reopen the
	# overworld's nested TileSet resources under the project's Godot 4.5.1.
	var load_error := ResourceLoader.load_threaded_request(destination_scene, "PackedScene", false)
	if load_error != OK:
		_fail_request(game, "The destination could not be loaded (%s)." % error_string(load_error))
		return false
	bind_game(game)
	_transitioning = true
	_previous_spawn_id = pending_spawn_id
	pending_spawn_id = spawn_id
	_source_scene = get_tree().current_scene
	if _source_scene == null:
		_source_scene = game.get_parent()
	_source_process_mode = _source_scene.process_mode
	_source_scene.process_mode = Node.PROCESS_MODE_DISABLED
	if game.has_method("_reset_held_movement"):
		game.call("_reset_held_movement")
	var interactions: Variant = game.get("interactions")
	if interactions != null:
		interactions.cancel_walk()
	game.set("spell_cast_requested", false)
	_cover.show()
	if destination_scene.contains("CatacombsFloor01"):
		_loading_label.text = "Entering Golem Catacombs — Floor One…"
	elif destination_scene.contains("GolemKingdom"):
		_loading_label.text = "Entering Golem Kingdom…"
	elif destination_scene.contains("TavernInterior"):
		_loading_label.text = "Entering the tavern…"
	else:
		_loading_label.text = "Returning to the outskirts…"
	_complete_travel.call_deferred(game, destination_scene)
	return true


func _complete_travel(game: Node, destination_scene: String) -> void:
	await _fade_to(1.0)
	var status := ResourceLoader.load_threaded_get_status(destination_scene)
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		status = ResourceLoader.load_threaded_get_status(destination_scene)
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		await _recover(game, "The destination could not be loaded. Please try again.")
		return
	var packed := ResourceLoader.load_threaded_get(destination_scene) as PackedScene
	if packed == null:
		await _recover(game, "The destination is not a playable area.")
		return
	# Targets and combat belong to the old area, while character stats persist.
	var previous_target := _player.current_target
	var previous_combat := _player.in_combat
	_player.current_target = ""
	_player.in_combat = false
	var error := get_tree().change_scene_to_packed(packed)
	if error != OK:
		_player.current_target = previous_target
		_player.in_combat = previous_combat
		await _recover(game, "The destination could not be opened (%s)." % error_string(error))
		return
	await get_tree().scene_changed
	_source_scene = null
	var arriving_scene := get_tree().current_scene
	var arriving_process_mode := arriving_scene.process_mode
	arriving_scene.process_mode = Node.PROCESS_MODE_DISABLED
	await _fade_to(0.0)
	_cover.hide()
	if is_instance_valid(arriving_scene):
		arriving_scene.process_mode = arriving_process_mode
	_transitioning = false
	transition_finished.emit(destination_scene)


func _recover(game: Node, message: String) -> void:
	pending_spawn_id = _previous_spawn_id
	if is_instance_valid(_source_scene):
		_source_scene.process_mode = _source_process_mode
	_source_scene = null
	await _fade_to(0.0)
	_cover.hide()
	_transitioning = false
	_fail_request(game, message)


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(_cover, "modulate:a", alpha, FADE_SECONDS)
	await tween.finished


func _sync_player_actor(game: Node, player: PlayerState) -> void:
	var combat: Variant = game.get("combat")
	if combat == null:
		return
	var actor: CombatActor = combat.actors.get(player.entity_id)
	if actor != null:
		player.x = actor.x
		player.y = actor.y
		player.current_hp = actor.hp
	# Spell costs are already applied directly to PlayerState.current_mana.


func _notice(game: Node, message: String) -> void:
	if is_instance_valid(game) and game.has_method("show_fishing_notice"):
		game.call("show_fishing_notice", message)


func _fail_request(game: Node, message: String) -> void:
	_notice(game, message)
	transition_failed.emit(message)
