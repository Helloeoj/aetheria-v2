extends Node
## Exercises persistent character ownership, spawn transforms and an actual scene swap.

class TestGame extends Node2D:
	const TILE_SIZE := 32
	var player := PlayerState.new("Travel test")
	var skill_training_session := SkillTrainingSession.new()
	var map_origin := Vector2(-64, 16)
	var map_height := 1024.0
	var combat := CombatEngine.new()
	var fishing_panel: Control
	var interactions: Node
	var spell_cast_requested := false
	var notice := ""

	func show_fishing_notice(message: String) -> void:
		notice = message

var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("[Scene travel FAIL] ", label)


func _run() -> void:
	var tree := get_tree()
	var travel := tree.root.get_node("SceneTravel")
	var old_area := Node2D.new()
	old_area.name = "OldArea"
	tree.root.add_child(old_area)
	tree.current_scene = old_area
	var game := TestGame.new()
	old_area.add_child(game)
	_check(not travel.bind_game(game), "initial binding keeps the scene's player")
	var original_player: PlayerState = game.player
	var original_training: SkillTrainingSession = game.skill_training_session
	original_player.add_item("Low Grade Fish Food", 17)
	original_player.gold = 37
	original_player.current_hp = 71
	original_player.current_mana = 6
	original_player.selected_spell_id = "unchanged_spell"
	original_player.current_target = "old_area_monster"
	original_player.in_combat = true
	original_training.record_event({"type": "skill_experience_gained", "skill": "fishing", "experience_gained": 15})
	original_training.advance(12.0)
	var replacement := TestGame.new()
	_check(travel.bind_game(replacement), "subsequent binding resumes the existing session")
	_check(replacement.player == original_player, "adopts the exact PlayerState reference")
	_check(replacement.skill_training_session == original_training, "adopts the exact training reference")
	_check(original_player.current_hp == 71 and original_player.current_mana == 6, "binding does not refill health or mana")
	_check(original_player.selected_spell_id == "unchanged_spell", "binding does not cycle spell selection")
	replacement.free()
	travel.pending_spawn_id = "Missing"
	travel.resolve_spawn(game)
	_check(travel.pending_spawn_id == "Missing", "missing spawn does not consume the pending destination")
	travel.pending_spawn_id = ""
	var actor := CombatActor.new().configure({"entity_id": original_player.entity_id, "hp": 53, "max_hp": 100, "x": 4.0, "y": 7.0})
	game.combat.add_actor(actor)
	_check(not travel.request_travel(game, "res://scenes/no_such_area.tscn", "Entry"), "missing scene is rejected without swapping")
	_check(not travel.is_transitioning() and old_area.process_mode != Node.PROCESS_MODE_DISABLED, "rejected travel leaves gameplay active")
	_check(original_player.current_hp == 53, "travel captures current actor health")
	actor.hp = 0
	_check(not travel.request_travel(game, "res://scenes/EastOutskirtsLayered.tscn", "Entry"), "dead character cannot travel")
	actor.hp = 53
	game.fishing_panel = Control.new()
	game.add_child(game.fishing_panel)
	game.fishing_panel.show()
	_check(not travel.request_travel(game, "res://scenes/EastOutskirtsLayered.tscn", "Entry"), "active fishing blocks travel")
	game.fishing_panel.hide()
	var destination := Node2D.new()
	destination.name = "Destination"
	destination.position = Vector2(41, 23)
	var points := Node2D.new()
	points.name = "SpawnPoints"
	destination.add_child(points)
	points.owner = destination
	var marker := Marker2D.new()
	marker.name = "Entry"
	marker.position = Vector2(256, 400)
	points.add_child(marker)
	marker.owner = destination
	var packed := PackedScene.new()
	_check(packed.pack(destination) == OK, "test destination packs")
	destination.free()
	var destination_path := "user://scene_travel_unit_destination.tscn"
	_check(ResourceSaver.save(packed, destination_path) == OK, "test destination saves")
	_check(travel.request_travel(game, destination_path, "Entry"), "valid travel starts")
	_check(old_area.process_mode == Node.PROCESS_MODE_DISABLED, "loading freezes the departing area")
	_check(not travel.request_travel(game, destination_path, "Entry"), "repeat activation cannot start a second transition")
	await travel.transition_finished
	_check(not travel.is_transitioning(), "transition completes and releases input")
	_check(tree.current_scene != old_area and tree.current_scene.name == "Destination", "the scene tree replaces the old area")
	var arrived := TestGame.new()
	arrived.position = Vector2(16, 32)
	tree.current_scene.add_child(arrived)
	_check(travel.bind_game(arrived), "arrival resumes persistent state")
	travel.resolve_spawn(arrived)
	_check(travel.pending_spawn_id.is_empty(), "arrival consumes its matching spawn")
	_check(is_equal_approx(arrived.player.x, 9.5) and is_equal_approx(arrived.player.y, 21.0), "spawn converts world canvas coordinates to game-local upward simulation tiles")
	_check(arrived.player.current_hp == 53 and arrived.player.current_mana == 6, "scene swap preserves health and mana")
	_check(arrived.player.gold == 37 and int(arrived.player.backpack.get("Low Grade Fish Food", 0)) == 17, "scene swap preserves inventory and gold")
	_check(arrived.player.current_target.is_empty() and not arrived.player.in_combat, "old area combat targets do not carry into the new area")
	_check(int(arrived.skill_training_session.get_progress("fishing").experience_gained) == 15, "scene swap preserves session XP")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(destination_path))
	print("[Scene travel] %d checks, %d failures" % [checks, failures.size()])
	tree.quit(0 if failures.is_empty() else 1)
