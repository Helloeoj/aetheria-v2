extends Node
## Real placed-node catalog, click routing, inventory/XP and presentation checks.
var failures: Array[String] = []
var checks := 0
var output := ""
@onready var root: Window = get_tree().root

func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("[Mining activation FAIL] ", message)

func _run() -> void:
	get_tree().create_timer(90).timeout.connect(func() -> void: get_tree().quit(1))
	var catalog := root.get_node("GameData")
	for name: String in ["Copper Ore", "Tin Ore", "Blackstone", "Bronze Pickaxe"]:
		check(not catalog.get_item_by_name(name).is_empty(), "catalog contains " + name)
	for area: String in ["BrackenMine", "ValtherianMines"]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Assets/Maps/" + area + "/layout.json"))
		var content: Node2D = load("res://scenes/" + area + "Content.tscn").instantiate()
		root.add_child(content)
		for row: Dictionary in data.ores:
			var node: Node2D = content.get_node(("Ores/" if area == "ValtherianMines" else "") + str(row.name))
			var deposit := node.get_node_or_null("Mining") as MiningDeposit
			check(deposit != null, area + "/" + str(row.name) + " is mineable")
			if deposit != null:
				var point: Array = row.get("approach", row.get("approach_world_xy", []))
				check(deposit.approach_position().is_equal_approx(content.to_global(Vector2(point[0], point[1]))), "exact authored approach retained")
				var visual := node.get_node("Footprint/Visual") as Sprite2D
				var full := visual.texture
				deposit.apply_state({"deposit_id":deposit.deposit_id,"generation":1,"state":"depleted"})
				check(visual.texture == deposit.depleted_texture and visual.texture != full, "depletion swaps the existing aligned texture")
				deposit.apply_state({"deposit_id":deposit.deposit_id,"generation":0,"state":"available"})
				check(visual.texture == deposit.depleted_texture, "stale state cannot restore ore")
				deposit.apply_state({"deposit_id":deposit.deposit_id,"generation":2,"state":"available"})
				check(visual.texture == full, "respawn restores full artwork")
		content.free()
	if failures.is_empty():
		_crafting()
		await _clicks()
	print("[Mining activation] ", checks, " checks, ", failures.size(), " failures")
	get_tree().quit(0 if failures.is_empty() else 1)

func _crafting() -> void:
	var player := PlayerState.new("Mining crafting regression")
	player.add_item("Copper Ore",2)
	player.add_item("Tin Ore",2)
	var driver := preload("res://scripts/dev_tools/smithing_test_driver.gd")
	check(driver.craft(player,"smelt_bronze_copper_tin","furnace",2).ok,"Copper and Tin smelt through existing Smithing sessions")
	check(player.backpack.get("Bronze Ingot",0) == 2,"smelting consumes Copper plus Tin into two real ingots")
	check(driver.craft(player,"bronze_pickaxe","anvil").ok,"Bronze Pickaxe is obtainable through existing Smithing")
	check(player.backpack.get("Bronze Pickaxe",0) == 1,"Smithing produces a reusable real catalog pickaxe")
	for name: String in ["Copper Ore","Tin Ore","Blackstone","Bronze Pickaxe"]:
		check(not SmithingCatalog.category(root.get_node("GameData").get_item_by_name(name)).is_empty(),name + " appears in the existing Smithing catalog")

func _clicks() -> void:
	root.size = Vector2i(1280,720)
	root.mode = Window.MODE_MINIMIZED
	root.get_node("SceneTravel").set("_player", null)
	var scene: Node2D = load("res://scenes/BrackenMine.tscn").instantiate()
	root.add_child(scene)
	var game: Node2D = scene.get_node("Combat")
	await get_tree().process_frame
	while game.get("grid_adapter") == null or not game.get("grid_adapter").completed:
		await get_tree().physics_frame
	game.set_physics_process(false)
	var player: PlayerState = game.get("player")
	player.backpack.clear()
	var node: MiningDeposit = scene.get_node("BrackenMineContent/CopperWestNorth/Mining")
	var approach: Dictionary = preload("res://scripts/interaction_approach.gd").describe(game,node,"mine")
	var body: CombatActor = game.get("combat").actors[player.entity_id]
	player.x = approach.point.x
	player.y = approach.point.y
	body.x = player.x
	body.y = player.y
	game.get("world").grid_traveller(player.entity_id)
	game.call("_update_sprite_position",player.entity_id)
	var camera: Camera2D = scene.get_node("MapCamera")
	camera.zoom = Vector2(4,4)
	camera.global_position = node.global_position + Vector2(0,-16)
	camera.force_update_scroll()
	await get_tree().process_frame
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = game.get_canvas_transform() * (node.global_position + Vector2(-8,-36))
	game.call("_unhandled_input",click)
	var controller: Node = game.get("offline_mining")
	check(not controller.service.active(player.entity_id),"left click without a tool fails closed")
	check(player.backpack.is_empty(),"missing tool cannot award ore")
	player.give_and_equip(333)
	game.call("_refresh_player_actor_from_player")
	game.get("fishing_notice").text = ""
	var actor: ActorSprite = game.get("actor_sprites")[player.entity_id]
	actor.set_process(false)
	check(actor.attachment_rig.get_equipped_visual("weapon") != null,"real catalog pickaxe uses installed hand attachment")
	click.button_index = MOUSE_BUTTON_RIGHT
	game.call("_unhandled_input",click)
	var menu: InteractionContextMenu = game.get("context_menu")
	check(menu.visible and menu.actions.any(func(entry: Dictionary) -> bool: return entry.label == "Mine"),"right click offers Mine in actual dropdown")
	await _capture("right-click-mine-4x.png")
	var chosen := false
	for button: Node in menu.options.get_children():
		if button is Button and button.text == "Mine":
			button.pressed.emit()
			chosen = true
			break
	check(chosen and controller.service.active(player.entity_id),"dropdown Mine starts the shared extraction service")
	controller.service._rng.seed = 42
	for step in range(11): controller.advance(0.25)
	check(int(player.backpack.get("Copper Ore",0)) == 0,"no reward before a full tool interval")
	for step in range(400):
		if not controller.service.active(player.entity_id): break
		controller.advance(0.25)
	check(player.backpack.get("Copper Ore",0) == 1 and player.get_skill_experience("mining") == 121,"real mining grants exactly one Copper Ore and configured XP")
	check(node.state.get("state") == "depleted","successful mining depletes the placed node")
	await _capture("mined-depleted-4x.png")
	click.button_index = MOUSE_BUTTON_LEFT
	game.call("_unhandled_input",click)
	check(not controller.service.active(player.entity_id) and player.backpack.get("Copper Ore",0) == 1,"depleted node cannot grant again")
	for step in range(16): controller.advance(0.25)
	check(node.state.get("state") == "available","placed node respawns after configured interval")
	game.call("_unhandled_input",click)
	check(controller.service.active(player.entity_id),"left click quick action starts mining the respawned node")
	controller.stop("test_complete")
	await _capture("respawn-full-4x.png")
	var region := AuthoritativeRegion.new()
	region.configure("bracken_mine",game)
	check(region.mining.deposit_snapshots().size() == 15,"authoritative region discovers all 15 actual Bracken nodes")
	scene.free()

func _capture(filename: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(output)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(filename)) == OK,"saved actual-game " + filename)
