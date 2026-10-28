extends SceneTree
## Real map, physics, chat and movement state; no socket or account required.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Tile commands FAIL] ", label)

func _initialize() -> void:
	_run.call_deferred()

func frames(count: int = 4) -> void:
	for _frame in count:
		await process_frame

func _run() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	var path := "res://scripts/dev_tools/tile_commands.gd"
	check(FileAccess.file_exists(path), "Tile command controller is installed")
	if not FileAccess.file_exists(path):
		_finish()
		return
	var scene: Node = load("res://scenes/TavernInterior.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await frames(12)
	var game: Node = scene.get_node("Combat")
	game.set_physics_process(false)
	check(game.get("tile_commands") != null, "Active game owns its tile command controller")
	if game.get("tile_commands") == null:
		_finish()
		return
	var commands: Node = game.tile_commands
	var grid: HiddenGrid = game.world.cell_grid
	var actor: CombatActor = game.combat.actors[game.player.entity_id]
	var start := Vector2(actor.x, actor.y)
	var cell := grid.cell_at(start)
	check(grid.cell_at(grid.center(Vector2i(-3, -7))) == Vector2i(-3, -7), "Signed tile addresses round-trip exactly")
	check(commands.cell_at_global(game.to_global(Vector2(-0.01, 0.01))) == Vector2i(-1, -1), "Cursor tile boundaries floor correctly on both signed axes")
	var pixel: Vector2 = game._screen_position(start.x, start.y)
	check(commands.cell_at_global(game.to_global(pixel)) == cell, "Cursor uses same grid as movement")
	var description: String = commands.execute("::pos")
	check(description.contains(scene.scene_file_path) and description.contains("::tele %d %d" % [cell.x, cell.y]), "Position reports area identity and reusable command")
	check(commands.execute("::help").contains("::tile"), "Help explains coordinate picking")
	var destination := Vector2i.ZERO
	var found := false
	for y in range(-5, 6):
		for x in range(-5, 6):
			var candidate := cell + Vector2i(x, y)
			if candidate != cell and grid.clear_point(grid.center(candidate)):
				destination = candidate
				found = true
				break
		if found:
			break
	check(found, "Fixture finds another physically clear tile")
	var traveller: GridTraveller = game.world.grid_traveller(actor.entity_id)
	if traveller != null:
		traveller.active = true
		traveller.target = start + Vector2.RIGHT
		traveller.goal = start + Vector2(4, 0)
	game.interactions.walking = true
	game.interactions.destination = start + Vector2(4, 0)
	game.auto_chase_target = true
	game.spell_cast_requested = true
	game.movement_controller.holding["right"] = true
	game.player.current_target = "stale-target"
	actor.current_target_id = "stale-target"
	var hp: int = actor.hp
	var inventory: Dictionary = game.player.backpack.duplicate(true)
	var reply: String = commands.execute("::tele %d %d" % [destination.x, destination.y])
	var finish := grid.center(destination)
	check(reply.begins_with("Teleported"), "Classic ::tele x y succeeds")
	check(Vector2(actor.x, actor.y) == finish and game.player.get_position() == finish, "Player and actor land on exact requested tile center")
	check(not game.interactions.walking and not game.auto_chase_target and not game.spell_cast_requested, "Teleport cancels stale walk, chase and spell intent")
	check(not game.movement_controller.holding.values().has(true), "Held movement is cleared on arrival")
	check(game.player.current_target.is_empty() and actor.current_target_id.is_empty(), "Teleport clears old targeting")
	check(actor.logical_cell == destination and not actor.grid_active, "Committed grid occupancy resets immediately")
	if traveller != null:
		check(not traveller.active and traveller.route.is_empty() and not traveller.goal.is_finite(), "Committed step and route cannot resume")
	check(game.actor_sprites[actor.entity_id].position == game._screen_position(finish.x, finish.y), "Sprite moves immediately")
	check(scene.get_node("MapCamera").global_position == game.actor_sprites[actor.entity_id].global_position, "Camera follows the teleport immediately")
	check(actor.hp == hp and game.player.backpack == inventory, "Teleport preserves health and inventory")
	for invalid: String in ["::tele", "::tele 2", "::tele 1 2 3", "::tele 1.5 2", "::tele NaN 2", "::tele 9999999999999999999999999 0", "::tele 2147483648 0", "::tele 100000 -100000"]:
		var result: String = commands.execute(invalid)
		check(not result.begins_with("Teleported") and Vector2(actor.x, actor.y) == finish, "Invalid address preserves state: " + invalid)
	var blocked := destination
	var blocked_found := false
	for y in range(-20, 21):
		for x in range(-20, 21):
			var candidate := cell + Vector2i(x, y)
			if grid.contains(grid.center(candidate)) and not grid.clear_point(grid.center(candidate)):
				blocked = candidate
				blocked_found = true
				break
		if blocked_found:
			break
	check(blocked_found, "Fixture contains a real solid wall")
	check(not commands.teleport(blocked).begins_with("Teleported") and game.player.get_position() == finish, "Real wall rejects teleport without substituting a nearby tile")
	game.interactions.walking = true
	game.spell_cast_requested = true
	commands.teleport(blocked)
	check(game.interactions.walking and game.spell_cast_requested, "Rejected teleport preserves pending activity intent")
	game.interactions.cancel_walk()
	game.spell_cast_requested = false
	var occupant := CombatActor.new().configure({"entity_id": "tile-occupant", "x": start.x, "y": start.y, "hp": 10, "max_hp": 10})
	game.combat.add_actor(occupant)
	check(not commands.teleport(cell).begins_with("Teleported"), "Occupied destination rejects teleport")
	game.combat.remove_actor(occupant.entity_id)
	check(commands.execute("  ::TeLePoRt\t%d   %d  " % [cell.x, cell.y]).begins_with("Teleported"), "Alias, case and whitespace work with negative coordinates")
	commands.execute("::coords on")
	await frames()
	check(commands.overlay_enabled and commands.coordinate_label.visible and commands.coordinate_label.text.contains("Player"), "Coordinate HUD shows player and cursor cells")
	check(commands.coordinate_label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Coordinate HUD never consumes clicks")
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = dimensions
		game._update_ui_scale()
		await frames()
		var overlaps := false
		for button: Control in [game.character_menu_button, game.fishing_test_button, game.skill_test_button]:
			overlaps = overlaps or commands.coordinate_label.get_global_rect().intersects(button.get_global_rect())
		check(not overlaps and Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(commands.coordinate_label.get_global_rect()), "Coordinate HUD fits without covering original controls at %s" % dimensions)
	root.size = Vector2i(1280, 720)
	game._update_ui_scale()
	var tile_report: String = commands.execute("::tile")
	check(tile_report.contains("placement center") and not tile_report.contains("%g"), "Cursor picking reports the area-local pixel anchor for future placement")
	commands.execute("::coords off")
	check(not commands.overlay_enabled and not commands.coordinate_label.visible, "Coordinate HUD turns off")
	var social: Node = root.get_node("Social")
	social.connected = false
	social.history.clear()
	for channel: String in ["local", "global", "private"]:
		check(social.send_chat(channel, "::pos", "Nobody"), "Commands work with disconnected chat in " + channel)
	check(social.pending.is_empty() and social.history.size() == 3, "Commands create only local feedback and no network pending messages")
	check(social.panel.transcript.get_parsed_text().contains("::tele"), "Command result appears in existing chat")
	check(social.send_chat("global", "::unknown"), "Unknown command is consumed locally")
	social.panel._filter_changed(2)
	check(social.panel.transcript.get_parsed_text().contains("Unknown command"), "Local command feedback remains visible in a filtered channel")
	social.panel.composer.text = "::pos"
	social.panel.composer.grab_focus()
	social.panel._submit("::pos")
	check(social.panel.composer.text.is_empty() and not social.panel.composer.has_focus(), "Submitting a command clears chat and releases gameplay focus")
	var before_transition: Vector2 = game.player.get_position()
	var travel: Node = root.get_node("SceneTravel")
	travel._transitioning = true
	check(not commands.teleport(destination).begins_with("Teleported") and game.player.get_position() == before_transition, "Teleport cannot race area transition")
	travel._transitioning = false
	var before_online: Vector2 = game.player.get_position()
	var network: Node = root.get_node("Network")
	network.mode = network.Mode.CLIENT
	check(not commands.teleport(destination).begins_with("Teleported") and game.player.get_position() == before_online, "Client cannot teleport an authoritative online character locally")
	network.mode = network.Mode.OFFLINE
	actor.is_alive = false
	check(not commands.teleport(destination).begins_with("Teleported"), "Dead player cannot teleport")
	actor.is_alive = true
	game.fishing_panel.show()
	check(not commands.teleport(destination).begins_with("Teleported"), "Active fishing cannot be interrupted by teleport")
	game.fishing_panel.hide()
	var adapter: Node = game.grid_adapter
	adapter.completed = false
	check(not commands.teleport(destination).begins_with("Teleported"), "Unready collision geometry fails closed")
	adapter.completed = true
	if OS.get_cmdline_user_args().has("--tile-screenshot"):
		commands.execute("::coords on")
		scene.get_node("MapCamera").zoom = Vector2(4, 4)
		var mouse := InputEventMouseMotion.new()
		mouse.position = Vector2(790, 270)
		root.push_input(mouse)
		await frames()
		await RenderingServer.frame_post_draw
		var output := OS.get_environment("TEMP").path_join("aetheria-tile-coordinates.png")
		root.get_texture().get_image().save_png(output)
		print("[Tile commands] screenshot: ", output)
	scene.queue_free()
	await frames()
	# An in-progress local expansion may not be present in every checkout.
	# Always run its real void regression when installed on the active PC.
	var catacombs_path := "res://scenes/CatacombsFloor01.tscn"
	if ResourceLoader.exists(catacombs_path):
		travel.clear_online_binding()
		var catacombs: Node = load(catacombs_path).instantiate()
		root.add_child(catacombs)
		current_scene = catacombs
		await frames(12)
		var cave: Node = catacombs.get_node("Combat")
		cave.set_physics_process(false)
		var original: Vector2 = cave.player.get_position()
		var void_point: Vector2 = cave.world.cell_grid.center(Vector2i(0, -1))
		check(cave.world.cell_grid.clear_point(void_point), "Catacombs void fixture is inside bounds and collision-free")
		cave.interactions.walking = true
		var void_reply: String = cave.tile_commands.execute("::tele 0 -1")
		check(not void_reply.begins_with("Teleported") and cave.player.get_position() == original and cave.interactions.walking, "Catacombs unsupported floor rejects teleport without mutating activity or position")
		cave.interactions.cancel_walk()
		var valid_cell: Vector2i = cave.world.cell_grid.cell_at(original)
		check(cave.tile_commands.teleport(valid_cell).begins_with("Teleported"), "Catacombs authored entrance floor still allows exact-center teleport")
		catacombs.queue_free()
		await frames()
	for map_path: String in ["res://scenes/EastOutskirtsLayered.tscn", "res://scenes/GolemKingdom.tscn", "res://scenes/BrackenMine.tscn"]:
		travel.clear_online_binding()
		var map: Node = load(map_path).instantiate()
		root.add_child(map)
		current_scene = map
		await frames(12)
		var map_game: Node = map.get_node("Combat")
		map_game.set_physics_process(false)
		var spawn_cell: Vector2i = map_game.world.cell_grid.cell_at(map_game.player.get_position())
		var spawn_reply: String = map_game.tile_commands.teleport(spawn_cell)
		check(spawn_reply.begins_with("Teleported"), "Authored full-body floor supports teleport in " + map_path + ": " + spawn_reply)
		check(map_game.player.get_position() == map_game.world.cell_grid.center(spawn_cell), "Exact tile round-trip in " + map_path)
		map.queue_free()
		await frames()
	_finish()

func _finish() -> void:
	print("[Tile commands] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
