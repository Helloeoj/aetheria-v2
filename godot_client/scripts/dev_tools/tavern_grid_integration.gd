extends SceneTree
## Real hearth exclusion, outer circulation and shared offline/server grid.
var checks := 0
var failures := 0
var game: Node

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Tavern grid FAIL] ", label)

func sim(pixel: Vector2) -> Vector2:
	return game.grid_adapter.simulation_point(game.to_global(pixel))

func place(pixel: Vector2) -> void:
	game.interactions.cancel_walk()
	game._reset_held_movement()
	var point := sim(pixel)
	var actor: CombatActor = game.combat.actors[game.player.entity_id]

	actor.x = point.x
	actor.y = point.y
	game.player.x = point.x
	game.player.y = point.y
	game.world.grid_travellers.erase(actor.entity_id)
	game.world.grid_traveller(actor.entity_id)
	game._update_sprite_position(actor.entity_id)
	game._update_map_camera()
	game.get_parent().get_node("MapCamera").force_update_scroll()

func _run() -> void:
	root.size = Vector2i(1280,720)
	check(FileAccess.get_sha256("res://Assets/Maps/Tavern/Interior.png") == "5d502827e17658c703b2e818ae4e2370811945e9a903cceb545481061cd98e55", "approved Tavern artwork remains byte-for-byte unchanged")
	var map: Node = load("res://scenes/TavernInterior.tscn").instantiate()
	root.get_node("SceneTravel").set("_player", null)
	root.add_child(map)
	current_scene = map
	game = map.get_node("Combat")
	game.set_physics_process(false)
	map.get_node("MapCamera").zoom = Vector2.ONE * 0.68
	for frame in range(60):
		await physics_frame
		if game.grid_adapter != null and game.grid_adapter.completed: break
	# These were clear floor between the hearth and each surrounding bench.
	for source: Vector2 in [Vector2(452,640),Vector2(780,640),Vector2(615,554),Vector2(615,748)]:
		var point := sim(source * 0.75)
		check(not game.grid_adapter.grid.clear_point(point), "full body cannot enter former hearth aisle " + str(source))
		check(map.interaction_path(Vector2(470.25,780),source * 0.75).is_empty(), "legacy navigation also excludes hearth aisle " + str(source))
	check(game.world.grid != null and game.grid_adoption_report().enabled, "Tavern adopts the shared gameplay grid after physical audit")
	if game.world.grid == null:
		map.queue_free()
		await process_frame
		finish()
		return
	var grid: HiddenGrid = game.world.grid
	var left := sim(Vector2(280,496))
	var right := sim(Vector2(664,496))
	check(grid.is_center(left) and grid.is_center(right), "fixed Tavern lattice aligns with physical circulation")
	check(grid == game.world.cell_grid, "movement and AoE share the same authored map origin")
	var route := grid.path(left,right)
	check(route.size() > 12, "left-to-right route detours outside the whole hearth island")
	for point: Vector2 in route:
		var pixel: Vector2 = game._screen_position(point.x,point.y)
		check(not Rect2(284.25,352.5,357,262.5).has_point(pixel), "route respects full body clearance around the island")
	place(Vector2(280,496))
	var key := InputEventKey.new()
	key.keycode = KEY_D
	key.physical_keycode = KEY_D
	key.pressed = true
	root.push_input(key)
	game._move_player(0.5)
	key.pressed = false
	root.push_input(key)
	check(game.player.get_position().is_equal_approx(left), "native WASD cannot step into the island from its west side")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = game.get_global_transform_with_canvas() * Vector2(664,496)
	check(root.get_visible_rect().has_point(click.position), "native click destination is visible in the real viewport")
	root.push_input(click)
	click = click.duplicate()
	click.pressed = false
	root.push_input(click)
	check(game.interactions.walking, "ground click starts an outer circulation route")
	for frame in range(900):
		game.interactions.update_walk(1.0/60.0)
		if not game.interactions.walking: break
	check(game.player.get_position().is_equal_approx(right) and game.world.at_grid_rest(game.player.entity_id), "offline click walk arrives around the island at a tile center")
	var region = load("res://network/authoritative_region.gd").new()
	region.configure("tavern-grid", game)
	var player = load("res://scripts/player_state.gd").new("Tavern grid")
	player.x = left.x
	player.y = left.y
	region.add_player("tavern-grid-player",player)
	check(region.submit(player.entity_id,{"type":"walk","x":right.x,"y":right.y}).ok, "server accepts the same outside route")
	for frame in range(900): region.advance(1.0/60.0)
	check(player.get_position().is_equal_approx(right), "authoritative player arrives at the same safe center")
	var blocked := sim(Vector2(461.25,480))
	check(not region.submit(player.entity_id,{"type":"walk","x":blocked.x,"y":blocked.y}).ok, "server rejects a destination inside the hearth island")
	check(player.get_position().is_equal_approx(right), "rejected hearth walk cannot relocate the player")
	check(region.world.cell_grid.origin == grid.origin, "server movement and AoE preserve the authored Tavern origin")
	for node: Node2D in [game.get_node("Stove"),game.get_node("TavernExit")]:
		check(not grid.path(left,sim(node.approach_position()),node.interaction_radius/32.0).is_empty(), "outside route retains " + node.name + " within unchanged interaction range")
	map.queue_free()
	await process_frame
	finish()

func finish() -> void:
	print("[Tavern grid] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
