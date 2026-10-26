extends SceneTree
## Real geometry audit and integration. Does not write saves or map assets.
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("[Grid maps FAIL] ", label)

func _run() -> void:
	for scene_path: String in ["res://scenes/GolemKingdom.tscn", "res://scenes/TavernInterior.tscn", "res://scenes/EastOutskirtsLayered.tscn", "res://scenes/CatacombsFloor01.tscn"]:
		if not ResourceLoader.exists(scene_path):
			continue
		var map: Node = load(scene_path).instantiate()
		root.get_node("SceneTravel").set("_player", null)
		root.add_child(map)
		current_scene = map
		var game: Node = map.get_node("Combat")
		game.set_physics_process(false)
		await physics_frame
		await process_frame
		await physics_frame
		for frame in range(60):
			if game.grid_adapter != null and game.grid_adapter.completed:
				break
			await physics_frame
		if not game.has_method("grid_adoption_report"):
			check(false, "map provides adoption report: " + scene_path)
		else:
			var report: Dictionary = game.grid_adoption_report()
			print("[Grid audit] ", scene_path, " ", JSON.stringify(report))
			check(not report.is_empty(), "audit produces a decision")
			check(report.enabled, "compatible area enables grid: " + scene_path)
			if report.enabled:
				var grid = game.world.grid
				if scene_path.ends_with("CatacombsFloor01.tscn"):
					check(not grid.clear_point(game.grid_adapter.simulation_point(Vector2(708, 5900))), "audit sees actual catacombs rock collision")
				var start: Vector2 = game.player.get_position()
				var recover: Variant = grid.recovery_cell(start)
				check(recover != null, "spawn has a swept connection to a center")
				var actor = game.combat.actors[game.player.entity_id]
				var route: PackedVector2Array = grid.path(start, start + Vector2(2, 0))
				check(not route.is_empty(), "near-spawn route exists")
				if not route.is_empty():
					for frame in range(180):
						game.world.move_grid_toward(actor.entity_id, start + Vector2(2, 0), 1.0 / 60.0, 4.0)
					check(Vector2(actor.x, actor.y).distance_to(route[-1]) < 0.001, "actual body follows grid route to its center")
					check(actor.logical_cell == grid.cell_at(route[-1]), "logical occupancy agrees on arrival")
					var target_actor = load("res://scripts/combat_actor.gd").new().configure({"entity_id": "grid-chase-target", "x": route[0].x, "y": route[0].y, "hp": 10, "max_hp": 10, "is_monster": true})
					game.combat.add_actor(target_actor)
					var old_range: float = actor.attack_range
					actor.attack_range = 0.75
					game.player.current_target = target_actor.entity_id
					game.auto_chase_target = true
					for frame in range(180):
						game._update_auto_chase(1.0 / 60.0)
					var chased: Vector2 = Vector2(actor.x, actor.y)
					check(chased.distance_to(grid.center(grid.cell_at(chased))) < 0.001, "auto-chase finishes committed step after entering attack range")
					check(chased.distance_to(route[0]) < 0.75, "auto-chase reaches valid attack distance")
					actor.attack_range = old_range
					game.auto_chase_target = false
					game.player.current_target = ""
					game.combat.remove_actor(target_actor.entity_id)
					var region = load("res://network/authoritative_region.gd").new()
					region.configure("grid-map", game)
					var remote_player = load("res://scripts/player_state.gd").new("Grid online")
					remote_player.x = route[0].x
					remote_player.y = route[0].y
					region.add_player("grid-online", remote_player)
					var goal: Vector2 = route[-1]
					check(region.submit("grid-online", {"type": "walk", "x": goal.x, "y": goal.y}).ok, "authoritative walk accepts checked route")
					for frame in range(180):
						region.advance(1.0 / 60.0)
					check(remote_player.get_position().distance_to(goal) < 0.001, "online body reaches same tile center as offline")
					check(region.snapshot("grid-online").has("grid"), "real map authority advertises adoption")
		map.queue_free()
		current_scene = null
		await process_frame
	print("[Grid maps] %d failures" % failures)
	quit(0 if failures == 0 else 1)
