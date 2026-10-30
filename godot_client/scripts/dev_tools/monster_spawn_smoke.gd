extends SceneTree
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Monster spawn FAIL] ", label)

func _initialize() -> void:
	_run.call_deferred()

func frames(count: int = 4) -> void:
	for _frame in count:
		await process_frame

func _run() -> void:
	create_timer(180).timeout.connect(func() -> void: quit(1))
	var maps := ["res://scenes/TavernInterior.tscn", "res://scenes/EastOutskirtsLayered.tscn", "res://scenes/GolemKingdom.tscn", "res://scenes/BrackenMine.tscn", "res://scenes/main.tscn"]
	for optional: String in ["res://scenes/CatacombsFloor01.tscn", "res://scenes/ValtherianMines.tscn"]:
		if ResourceLoader.exists(optional):
			maps.append(optional)
	for path: String in maps:
		root.get_node("SceneTravel").clear_online_binding()
		var scene: Node = load(path).instantiate()
		root.add_child(scene)
		current_scene = scene
		var game: Node = scene.get_node("Combat") if scene.has_node("Combat") else scene
		await frames(12)
		game.set_physics_process(false)
		var ids: Array = game._active_monster_database().keys()
		check(not ids.is_empty(), path + " exposes existing monster templates")
		if ids.is_empty():
			scene.queue_free()
			await frames()
			continue
		var id: int = int(ids[0])
		var start: Vector2 = game.player.get_position()
		for _spawn in range(3):
			var count: int = game.world.monsters.size()
			game.spawn_monster_by_id(id)
			check(game.world.monsters.size() == count + 1, path + " spawns near the current player")
			if game.world.monsters.size() != count + 1:
				continue
			var monster: MonsterState = game.world.monsters[-1]
			var point := monster.get_position()
			var grid: HiddenGrid = game.world.cell_grid
			check(point.distance_to(start) <= 3.00001 and point.distance_to(start) >= 0.75, path + " spawn is within three tiles and off the player")
			check(grid.is_center(point) and grid.clear_point(point), path + " spawn is an exact physically clear tile")
			var route := grid.path(start, point)
			check(not route.is_empty() and route[-1].is_equal_approx(point), path + " player can walk to the exact spawn tile")
			for other: CombatActor in game.combat.actors.values():
				if other.entity_id != monster.entity_id and other.is_alive:
					check(absf(other.x - point.x) >= 0.75 or absf(other.y - point.y) >= 0.75, path + " repeated spawns never overlap another body")
		if path.ends_with("TavernInterior.tscn"):
			var grid: HiddenGrid = game.world.cell_grid
			var old_clear := grid.point_clear
			grid.point_clear = func(_p: Vector2) -> bool: return false
			grid.clear_cache()
			var count: int = game.world.monsters.size()
			var serial: int = game.next_monster_number
			game.spawn_menu.visible = true
			game.spawn_menu.input_text = str(id)
			var enter := InputEventKey.new()
			enter.keycode = KEY_ENTER
			game.spawn_menu.on_key_press(enter)
			check(game.world.monsters.size() == count and game.next_monster_number == serial, "No valid tile creates no actor or consumed spawn ID")
			check(not game.spawn_menu.status_text.begins_with("Spawned"), "Dev menu reports failed placement honestly")
			game.spawn_menu.hide()
			grid.point_clear = old_clear
			grid.clear_cache()
			if OS.get_cmdline_user_args().has("--spawn-screenshot"):
				scene.get_node("MapCamera").zoom = Vector2(4, 4)
				await frames()
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("aetheria-monster-spawn-4x.png"))
		scene.queue_free()
		await frames()
	print("[Monster spawn] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
