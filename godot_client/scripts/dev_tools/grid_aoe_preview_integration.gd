extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[AoE preview FAIL] ",label)

func _run() -> void:
	var map: Node = load("res://scenes/GolemKingdom.tscn").instantiate()
	root.get_node("SceneTravel").set("_player",null)
	root.add_child(map)
	current_scene = map
	var game: Node = map.get_node("Combat")
	game.set_physics_process(false)
	for frame in range(60):
		await physics_frame
		if game.grid_adapter != null and game.grid_adapter.completed: break
	var preview: Node = game.get("aoe_preview")
	check(preview != null, "debug game installs tile preview")
	if preview == null:
		finish()
		return
	check(not preview.enabled and preview.affected_cells().is_empty(), "preview disabled by default")
	game.player.set_skill_level("magic",100)
	game.player.current_mana = 10000
	game.player.selected_spell_id = "air_stormring"
	var point: Vector2 = game.player.get_position()
	var actor := CombatActor.new().configure({"entity_id":"preview-target","x":point.x-3,"y":point.y,"hp":1000,"max_hp":1000,"is_monster":true})
	game.combat.add_actor(actor)
	game.world.grid_traveller(actor.entity_id)
	game.player.current_target = actor.entity_id
	var key := InputEventKey.new()
	key.keycode = KEY_V
	key.pressed = true
	key.ctrl_pressed = true
	key.shift_pressed = true
	game._unhandled_input(key)
	check(preview.enabled and preview.affected_cells().size() == 13, "Ctrl+Shift+V previews existing radius-two spell without new targeting controls")
	check(game.combat.cast_spell(game.world,game.player.entity_id,"air_stormring",actor.entity_id).ok, "preview does not replace real casting")
	var cast: Dictionary = game.combat.active_spell_casts[game.player.entity_id]
	var before: Array = preview.affected_cells()
	game.world.displace_actor(actor.entity_id,Vector2(-3,0))
	check(preview.affected_cells() == before, "active-cast preview stays on captured tile after target moves")
	var region = load("res://network/authoritative_region.gd").new()
	region.configure("preview",game)
	var p = load("res://scripts/player_state.gd").new("Preview server")
	p.x = point.x
	p.y = point.y
	p.set_skill_level("magic",100)
	p.current_mana = 10000
	region.add_player("preview-online",p)
	region.world.combat.add_actor(CombatActor.new().configure({"entity_id":"online-target","x":point.x-3,"y":point.y,"hp":1000,"max_hp":1000,"is_monster":true}))
	check(region.submit(p.entity_id,{"type":"cast","spell_id":"air_stormring","target_id":"online-target"}).ok,"server starts unchanged spell command")
	var snapshot: Dictionary = region.snapshot(p.entity_id)
	var descriptor: Dictionary = snapshot.get("area_cast",{})
	check(descriptor.get("target_cell") == [cast.target_cell.x,cast.target_cell.y], "own snapshot carries authoritative captured cell")
	check(region.snapshot("").get("area_cast",{}).is_empty(), "public snapshots do not leak private cast descriptors")
	preview.authoritative_cast = descriptor
	check(preview.affected_cells() == before, "server descriptor produces identical preview footprint")
	var events: Array = game.combat._process_spell_casts(game.world,2.5)
	for event: Dictionary in events:
		if event.type == "spell_area_resolved":
			check(event.cells.size() == before.size() and event.cells.has([cast.target_cell.x+2,cast.target_cell.y]), "damage resolution and drawn footprint share boundary cells")
	# Optional real-render capture; never writes inside the repository.
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--preview-capture=") and DisplayServer.get_name() != "headless":
			await process_frame
			await RenderingServer.frame_post_draw
			var output := argument.trim_prefix("--preview-capture=")
			check(root.get_texture().get_image().save_png(output) == OK, "real in-game tile preview rendered")
	var view = load("res://network/online_world_view.gd").new()
	view.game = game
	game.add_child(view)
	game.online_view = view
	view._has_self = true
	view._keyboard = true
	view._prediction.record_input(7,Vector2.RIGHT)
	view._motion["old-peer"] = load("res://network/snapshot_interpolation.gd").new()
	game.movement_controller.on_input("d",true)
	game.auto_chase_target = true
	game.spell_cast_requested = true
	game.world.move_grid_direction(game.player.entity_id,Vector2.LEFT,0.1,4.0)
	check(game.has_method("prepare_area_exit"),"scene boundary has explicit movement/presentation cleanup")
	if game.has_method("prepare_area_exit"):
		game.prepare_area_exit()
		check(game.movement_controller.get_move_vector().is_zero_approx() and not game.auto_chase_target and not game.spell_cast_requested,"area exit clears held controls, chase and queued casting")
		check(game.world.grid_travellers.is_empty() and game.combat.active_spell_casts.is_empty() and not preview.enabled,"area exit clears old travel/casts/preview")
		check(view._motion.is_empty() and view._prediction._commands.is_empty() and not view._has_self,"area exit clears prediction and remote interpolation")
	map.queue_free()
	await process_frame
	finish()

func finish() -> void:
	print("[AoE preview] %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
