extends SceneTree
var game: Node
var failures := 0
var checks := 0
var start := Vector2.ZERO

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Grid interaction FAIL] ", label)

func place(point: Vector2) -> void:
	game.interactions.cancel_walk()
	var actor = game.combat.actors[game.player.entity_id]
	actor.x = point.x
	actor.y = point.y
	game.player.x = point.x
	game.player.y = point.y
	game.world.grid_travellers.erase(actor.entity_id)
	game.world.grid_traveller(actor.entity_id)
	game._update_sprite_position(actor.entity_id)

func walk() -> void:
	for frame in range(900):
		game.interactions.update_walk(1.0 / 60.0)
		if not game.interactions.walking:
			return
	check(false, "interaction walk completes")

func _run() -> void:
	var map: Node = load("res://scenes/GolemKingdom.tscn").instantiate()
	root.get_node("SceneTravel").set("_player", null)
	root.add_child(map)
	current_scene = map
	game = map.get_node("Combat")
	game.set_physics_process(false)
	for frame in range(60):
		await physics_frame
		if game.grid_adapter != null and game.grid_adapter.completed:
			break
	check(game.world.grid != null, "fixture uses real audited map grid")
	var grid: HiddenGrid = game.world.grid
	start = grid.center(grid.recovery_cell(game.player.get_position()))
	var route := grid.path(start, start + Vector2(-4, 0))
	check(not route.is_empty(), "fixture has real approach route")
	if route.is_empty():
		quit(1)
		return
	var destination := route[-1]
	place(start)
	var fish = load("res://scripts/fishing_spot.gd").new()
	fish.shore_offset = Vector2.ZERO
	fish.interact_radius = 16.0
	fish.position = game._screen_position(destination.x, destination.y)
	game.add_child(fish)
	game.request_fishing(fish)
	check(game.interactions.walking and not game.fishing_panel.visible, "distant fishing queues approach before opening original panel")
	walk()
	check(game.fishing_panel.visible and game.world.at_grid_rest(game.player.entity_id), "fishing opens at an arrived reachable center")
	check(game.player.get_position().distance_to(destination) <= 0.5, "fishing retains authored 16px range")
	game.fishing_panel.close()
	place(start)
	var forge = load("res://scripts/crafting_station.gd").new()
	forge.setup("furnace", "Grid forge", destination)
	forge.position = game._screen_position(destination.x, destination.y)
	game.add_child(forge)
	game.request_crafting(forge)
	walk()
	check(game.crafting_panel.visible and game.player.get_position().distance_to(destination) <= 2.5, "crafting routes within existing reach and opens original UI")
	game.crafting_panel.close()
	place(start)
	var stove = load("res://scripts/cooking_station.gd").new()
	stove.approach_offset = Vector2.ZERO
	stove.interaction_radius = 16.0
	stove.position = fish.position
	game.add_child(stove)
	game.interactions.request_cooking(stove)
	walk()
	check(game.cooking_controller.panel.visible and game.world.at_grid_rest(game.player.entity_id), "cooking opens original panel after center arrival")
	game.cooking_controller.panel.close()
	place(start)
	var rock = load("res://scripts/mining_deposit.gd").new()
	rock.deposit_id = "grid-rock"
	rock.position = fish.position
	rock.interaction_radius = 16.0
	game.add_child(rock)
	# Discover test-authored content using the real offline authority.
	game.offline_mining.configure(game)
	game.interactions.request_mining(rock)
	walk()
	check(game.player.get_position().distance_to(destination) <= 0.5 and game.world.at_grid_rest(game.player.entity_id), "mining approaches a center inside original range")
	check(not game.offline_mining.service.active(game.player.entity_id), "production pickaxe catalog hold remains enforced")
	var defs = load("res://scripts/dev_tools/mining_tool_fixture.gd").new()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mining.json"))
	data.ores[0].success.p_at_unlock = 1.0
	data.ores[0].success.p_at_mastery = 1.0
	defs.load_records(data)
	game.offline_mining.service._defs = defs
	game.request_mining(rock)
	check(game.offline_mining.service.active(game.player.entity_id), "eligible offline mining uses existing MiningService")
	for step in range(31):
		game.offline_mining.advance(0.1)
	check(game.player.backpack.get("Bronze Ore", 0) == 1, "shared mining transaction grants exactly one ore")
	check(rock.state.state == "depleted", "offline deposit publishes shared depletion state")
	place(start)
	var region = load("res://network/authoritative_region.gd").new()
	region.configure("grid-interactions", game)
	var online = load("res://scripts/player_state.gd").new("Online parity")
	online.x = start.x
	online.y = start.y
	region.add_player("parity-online", online)
	for pair: Array in [[fish,"fish"],[stove,"cook"],[forge,"craft"],[rock,"mine"]]:
		var kind: String = pair[1]
		var id: String = pair[0].deposit_id if kind == "mine" else str(map.get_path_to(pair[0]))
		var actor = region.world.combat.actors["parity-online"]
		actor.x = start.x
		actor.y = start.y
		online.x = start.x
		online.y = start.y
		region.world.grid_travellers.erase("parity-online")
		var outcome: Dictionary = region.submit("parity-online", {"type":"walk", "x":1.0, "y":1.0, "interaction_kind":kind, "interaction_id":id})
		check(outcome.ok, "server accepts trusted " + kind + " approach")
		for frame in range(180):
			region.advance(1.0 / 60.0)
		var reach := 2.5 if kind == "craft" else 0.5
		check(online.get_position().distance_to(destination) <= reach + 0.00001 and region.world.at_grid_rest("parity-online"), "server " + kind + " reaches center using authored range rather than forged coordinates")
	check(not region.submit("parity-online", {"type":"walk","x":1,"y":1,"interaction_kind":"mine","interaction_id":"missing"}).ok, "unknown interaction cannot forge a destination")
	var portal: Node2D = game.get_node("EastCaveExit")
	var portal_goal: Vector2 = game.interactions._simulation_position(portal.approach_position())
	check(region.submit("parity-online", {"type":"walk", "x":1, "y":1, "interaction_kind":"portal", "interaction_id":str(map.get_path_to(portal))}).ok, "server resolves authored portal approach")
	for frame in range(900):
		region.advance(1.0 / 60.0)
	check(online.get_position().distance_to(portal_goal) <= portal.interaction_radius / 32.0 + 0.00001 and region.world.at_grid_rest("parity-online"), "portal arrival respects authored reach and center occupancy")
	region._add_drop("Bronze Ore", 1, destination)
	var drop_id: String = region.drops.keys()[0]
	check(region.submit("parity-online", {"type":"walk", "x":1, "y":1, "interaction_kind":"pickup", "interaction_id":drop_id}).ok, "server resolves public pickup approach")
	for frame in range(900):
		region.advance(1.0 / 60.0)
	check(online.get_position().distance_to(destination) <= 2.0 and region.world.at_grid_rest("parity-online"), "pickup arrives inside existing range")
	check(region.submit("parity-online", {"type":"pickup", "drop_id":drop_id}).ok and online.backpack.get("Bronze Ore", 0) == 1, "arrived pickup credits original inventory once")
	check(not region.submit("parity-online", {"type":"pickup", "drop_id":drop_id}).ok, "pickup cannot duplicate a collected item")
	region._add_drop("Bronze Ore", 1, destination, "other-player")
	drop_id = region.drops.keys()[0]
	check(not region.submit("parity-online", {"type":"walk", "x":1, "y":1, "interaction_kind":"pickup", "interaction_id":drop_id}).ok, "private loot cannot be used as another player's approach target")
	var client = load("res://autoload/network_manager.gd").new()
	client.game = game
	client._last_direction = Vector2.RIGHT
	game.movement_controller.on_input("d", true)
	client.replace_keyboard_intent()
	check(game.movement_controller.get_move_vector().is_zero_approx() and client._last_direction.is_zero_approx(), "reliable walk replaces held input without a later synthetic release cancelling it")
	client.free()
	map.queue_free()
	await process_frame
	var tavern: Node = load("res://scenes/TavernInterior.tscn").instantiate()
	root.get_node("SceneTravel").set("_player", null)
	root.add_child(tavern)
	current_scene = tavern
	game = tavern.get_node("Combat")
	game.set_physics_process(false)
	for frame in range(60):
		await physics_frame
		if game.grid_adapter != null and game.grid_adapter.completed:
			break
	region = load("res://network/authoritative_region.gd").new()
	region.configure("tavern-parity", game)
	online = load("res://scripts/player_state.gd").new("Tavern walker")
	online.x = game.player.x
	online.y = game.player.y
	region.add_player("tavern-walker", online)
	var goal: Vector2 = game.interactions._simulation_position(game.get_node("Stove").approach_position())
	check(not region.world.has_line_of_sight(online.get_position(), goal), "tavern route fixture crosses furniture on its direct ray")
	check(region.submit("tavern-walker", {"type":"walk","x":goal.x,"y":goal.y}).ok, "server uses existing tavern navigation around furniture")
	for frame in range(600):
		region.advance(1.0 / 30.0)
	check(online.get_position().distance_to(goal) < 0.05, "legacy narrow-passage area reaches destination online")
	check(game.world.grid == null, "tavern compatibility hold remains intact")
	tavern.queue_free()
	await process_frame
	print("[Grid interaction] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
