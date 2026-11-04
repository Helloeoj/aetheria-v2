extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	if not FileAccess.file_exists("res://scripts/valtherian_population.gd"):
		printerr("FAIL: mine population controller missing")
		quit(1)
		return
	create_timer(45).timeout.connect(func()->void:quit(1))
	var scene: Node = load("res://scenes/ValtherianMines.tscn").instantiate()
	root.get_node("SceneTravel").clear_online_binding()
	root.add_child(scene)
	current_scene = scene
	for i in 20: await physics_frame
	var game: Node = scene.get_node("Combat")
	game.set_physics_process(false)
	var population: RefCounted = game.mine_population
	population.advance(game, game.world, 0.01)
	assert(population.slots.size() == 18, "18 authored encounters")
	for slot: Dictionary in population.slots:
		if String(slot.entity).is_empty(): print("MISSING SPAWN ",slot, " clear=",game.monster_spawn_allowed(slot.home))
	assert(game.world.monsters.size() == 18, "all mine encounters spawned")
	assert(GameTickConfig.MONSTER_CHASE_LEASH_TILES == 10.0)
	for slot: Dictionary in population.slots:
		var actor: CombatActor = game.combat.actors[slot.entity]
		assert(game.monster_spawn_allowed(slot.home) and game.world.grid.clear_point(Vector2(actor.x,actor.y)), "spawn uses actual player body/floor collision")
		assert(population.has_loot(game._active_monster_database()[slot.template]))
		var item_seen := false
		for roll in 80:
			var result: Dictionary = game.loot_system.roll_monster_loot(game._find_monster_by_entity_id(slot.entity))
			item_seen = item_seen or result.get("item") is Dictionary or not result.get("items",[]).is_empty()
		assert(item_seen,"every dungeon mob produces actual catalog items")
		var monster_loot: Dictionary=game.loot_system.roll_monster_loot(game._find_monster_by_entity_id(slot.entity))
		assert(monster_loot.gold>0,"every dungeon mob awards tier gold")
	# Remove one enemy exactly as the offline death handler does; clock starts at death.
	var first: Dictionary = population.slots[0]
	var old_id: String = first.entity
	game._despawn_monster(old_id)
	population.advance(game,game.world,0.01)
	population.advance(game,game.world,14.98)
	assert(first.entity == "", "no early respawn")
	population.advance(game,game.world,0.02)
	assert(first.entity != "" and first.entity != old_id, "fresh enemy after 15 seconds")
	# Exercise real shared-grid roaming with combat movement active.
	var moved := false
	for i in 240:
		population.advance(game,game.world,1.0/30.0)
		game._handle_combat_events(game.combat.process_realtime(game.world,1.0/30.0))
		for slot: Dictionary in population.slots:
			var actor: CombatActor = game.combat.actors[slot.entity]
			var point := Vector2(actor.x,actor.y)
			assert(point.distance_to(slot.home) <= 10.001, "ten-tile roam/leash")
			assert(game.world.grid.clear_point(point), "full player collision body remains clear")
			moved = moved or point.distance_to(slot.home) > 0.5
	assert(moved, "monsters actually roam")
	var hard: Dictionary = population.slots[-1]
	var enemy: CombatActor = game.combat.actors[hard.entity]
	var player_actor: CombatActor = game.combat.actors[game.player.entity_id]
	var near: Vector2 = game.world.grid.center(game.world.grid.cell_at(hard.home)+Vector2i(1,0))
	player_actor.x=near.x
	player_actor.y=near.y
	population.advance(game,game.world,0.01)
	assert(player_actor.entity_id in enemy.aggro_attacker_ids, "hardest enemies acquire player on sight")
	player_actor.x=hard.home.x+11.0
	player_actor.y=hard.home.y
	game.combat._refresh_monster_target(game.world,enemy)
	assert(enemy.current_target_id.is_empty(), "drop target beyond ten-tile chase area")
	if OS.get_cmdline_user_args().has("--render"):
		player_actor.x=first.home.x+2.0
		player_actor.y=first.home.y
		game.player.x=player_actor.x
		game.player.y=player_actor.y
		game._sync_actor_states()
		var camera: Camera2D=scene.get_node("MapCamera")
		camera.position=game._screen_position(first.home.x,first.home.y)
		camera.zoom=Vector2(4,4)
		await create_timer(0.4).timeout
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("valtherian-population-4x.png"))
		var captain_slot: Dictionary=population.slots[13]
		var captain: CombatActor=game.combat.actors[captain_slot.entity]
		player_actor.x=captain.x+2.0
		player_actor.y=captain.y
		game.player.x=player_actor.x
		game.player.y=player_actor.y
		game._sync_actor_states()
		camera.position=game._screen_position(captain.x,captain.y)
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("valtherian-skeleton-population-4x.png"))

	# A separate authoritative region owns its own population and publishes snapshots.
	var region: RefCounted = load("res://network/authoritative_region.gd").new()
	region.configure("valtherian_mines",game)
	region.advance(0.1)
	assert(region.world.monsters.size()==18,"server populates the same authored roster")
	for monster: MonsterState in region.world.monsters:
		assert(monster.get_meta("dungeon_loot_table", "") == "valtherian_mines", "server uses dungeon loot profile")
		assert(game.loot_system.roll_monster_loot(monster).gold > 0, "server skeleton and goblin gold enabled")
	var published: Dictionary=region.snapshot("fixture")
	assert(published.actors.size()==18,"server publishes every monster")
	var server_slot: Dictionary=region.mine_population.slots[0]
	var server_old: String=server_slot.entity
	region.world.combat.actors[server_old].is_alive=false
	region.mine_population.advance(game,region.world,0.01,true)
	region.mine_population.advance(game,region.world,14.99,true)
	assert(server_slot.entity=="","server waits fifteen seconds")
	region.mine_population.advance(game,region.world,0.02,true)
	assert(server_slot.entity!="" and server_slot.entity!=server_old,"server respawns with fresh identity")
	print("[Valtherian population] PASS: placement, existing loot, respawn, movement, collision, aggression and leash")
	quit(0)
