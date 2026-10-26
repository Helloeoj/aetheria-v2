extends SceneTree
## Screenshot regressions: walk behind both counters and one tile nearer the bench.
var game: Node
var checks := 0
var failures := 0
var capture_directory := ""

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Tavern walk-behind FAIL] ",label)

func sim(pixel: Vector2) -> Vector2:
	return game.grid_adapter.simulation_point(pixel)

func place(pixel: Vector2) -> void:
	game.interactions.cancel_walk()
	game._reset_held_movement()
	var actor: CombatActor = game.combat.actors[game.player.entity_id]
	var point := sim(pixel)
	actor.x = point.x
	actor.y = point.y
	game.player.x = point.x
	game.player.y = point.y
	game.world.grid_travellers.erase(actor.entity_id)
	game.world.grid_traveller(actor.entity_id)
	game._update_sprite_position(actor.entity_id)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	root.push_input(event)

func frame_image() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func verify_render(map: Node) -> void:
	if DisplayServer.get_name() == "headless" or capture_directory.is_empty(): return
	DirAccess.make_dir_recursive_absolute(capture_directory)
	root.size = Vector2i(1280,720)
	game.get_node("UI").visible = false
	game.health_bar_layer.hide()
	var camera: Camera2D = map.get_node("MapCamera")
	camera.zoom = Vector2.ONE * 4.0
	var sprite: ActorSprite = game.actor_sprites[game.player.entity_id]
	sprite.set_process(false)
	for sample: Array in [["KitchenIsland",Vector2(792,208)],["BarCounter",Vector2(408,176)],["HearthNorthBench",Vector2(472,368)]]:
		var name: String = sample[0]
		place(sample[1])
		sprite.face_direction(Vector2.DOWN)
		sprite.animated_sprite.pause()
		game._update_map_camera()
		camera.force_update_scroll()
		var foreground: CanvasItem = map.get_node("TavernContent/"+name+"/Foreground")
		sprite.hide()
		var background: Image = await frame_image()
		sprite.show()
		foreground.hide()
		var unoccluded: Image = await frame_image()
		foreground.show()
		var actual: Image = await frame_image()
		var hidden_pixels := 0
		var visible_pixels := 0
		for y in range(140,380):
			for x in range(520,760):
				var base := background.get_pixel(x,y)
				if not unoccluded.get_pixel(x,y).is_equal_approx(base) and actual.get_pixel(x,y).is_equal_approx(base): hidden_pixels += 1
				if not actual.get_pixel(x,y).is_equal_approx(base): visible_pixels += 1
		check(hidden_pixels > 0 and visible_pixels > 0,name+" renders over the player's lower body while the upper body remains visible at 4x")
		print("[Tavern occlusion] ",name,": hidden=",hidden_pixels," visible=",visible_pixels)
		check(actual.save_png(capture_directory.path_join(name+"-behind-4x.png")) == OK,"save real 4x "+name+" evidence")

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-directory="): capture_directory = argument.trim_prefix("--capture-directory=")
	var map: Node = load("res://scenes/TavernInterior.tscn").instantiate()
	root.get_node("SceneTravel").set("_player",null)
	root.add_child(map)
	current_scene = map
	game = map.get_node("Combat")
	game.set_physics_process(false)
	for frame in range(60):
		await physics_frame
		if game.grid_adapter != null and game.grid_adapter.completed: break
	check(game.world.grid != null,"Tavern remains on the shared grid")
	if game.world.grid == null:
		finish()
		return
	var rows: Array = [
		[Vector2(664,208),Vector2(856,208),KEY_D,"kitchen island",7],
		[Vector2(568,176),Vector2(184,176),KEY_A,"bar counter",13],
		[Vector2(472,336),Vector2(472,368),KEY_S,"north hearth bench",2],
	]
	for row: Array in rows:
		var start: Vector2 = row[0]
		var goal: Vector2 = row[1]
		var label: String = row[3]
		check(game.world.grid.clear_point(sim(goal)),label+" allows the requested body-clear standing tile")
		check(game.world.grid.path(sim(start),sim(goal)).size() == row[4],label+" has a direct tile route without detouring around the furniture")
		place(start)
		key(row[2],true)
		for frame in range(240):
			game._move_player(1.0/60.0)
			if game.player.get_position().is_equal_approx(sim(goal)): break
		key(row[2],false)
		game._move_player(0.5)
		check(game.player.get_position().is_equal_approx(sim(goal)),"native directional input passes behind "+label)
		check(game.world.at_grid_rest(game.player.entity_id),label+" stops at a tile center")
		place(start)
		game.interactions.walk_here(goal)
		for frame in range(600):
			game.interactions.update_walk(1.0/60.0)
			if not game.interactions.walking: break
		check(game.player.get_position().is_equal_approx(sim(goal)),"click route reaches the requested "+label+" tile")
		var region = load("res://network/authoritative_region.gd").new()
		region.configure("walkbehind-"+label,game)
		var player = load("res://scripts/player_state.gd").new("Walk behind")
		player.x = sim(start).x
		player.y = sim(start).y
		region.add_player("walkbehind-player",player)
		var outcome: Dictionary = region.submit(player.entity_id,{"type":"walk","x":sim(goal).x,"y":sim(goal).y})
		check(outcome.ok,"server accepts requested "+label+" tile")
		for frame in range(600): region.advance(1.0/60.0)
		check(player.get_position().is_equal_approx(sim(goal)),"server reaches same "+label+" tile")
		region.remove_player(player.entity_id)
	# The physical furniture fronts and inner hearth remain inaccessible.
	for pixel: Vector2 in [Vector2(792,240),Vector2(408,208),Vector2(472,400),Vector2(472,480)]:
		check(not game.world.grid.clear_point(sim(pixel)),"solid furniture/hearth still blocks "+str(pixel))
	for name: String in ["KitchenIsland","BarCounter","HearthNorthBench"]:
		check(map.get_node("TavernContent/"+name+"/Foreground") is Polygon2D,name+" retains its existing foreground artwork")
	await verify_render(map)
	map.queue_free()
	await process_frame
	finish()

func finish() -> void:
	print("[Tavern walk-behind] %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
