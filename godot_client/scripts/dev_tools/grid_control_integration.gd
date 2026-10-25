extends SceneTree
## Actual map/controller update path, not just an isolated traveller.
var checks := 0
var failures := 0
var game: Node

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Grid controls FAIL] ",label)

func place(point: Vector2) -> void:
	game.interactions.cancel_walk()
	game._reset_held_movement()
	game._clear_target()
	var actor: CombatActor = game.combat.actors[game.player.entity_id]
	actor.x = point.x
	actor.y = point.y
	game.player.x = point.x
	game.player.y = point.y
	game.world.grid_travellers.erase(actor.entity_id)
	game.world.grid_traveller(actor.entity_id)
	game._update_sprite_position(actor.entity_id)

func key(code: Key,pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	root.push_input(event)

func controls() -> void:
	var grid: HiddenGrid = game.world.grid
	var base := grid.cell_at(game.player.get_position())
	var open := Vector2(INF,INF)
	for y in range(-8,9):
		for x in range(-8,9):
			var cell := base+Vector2i(x,y)
			var clear := grid.walkable(cell)
			for direction: Vector2i in HiddenGrid.DIRECTIONS:
				clear = clear and grid.connected(cell,cell+direction)
			if clear and not grid.path(game.player.get_position(),grid.center(cell)).is_empty():
				open = grid.center(cell)
				break
		if open.is_finite(): break
	check(open.is_finite(),"reachable open floor supports all native directional controls")
	if not open.is_finite(): return
	for pair: Array in [[KEY_W,Vector2.UP],[KEY_UP,Vector2.UP],[KEY_S,Vector2.DOWN],[KEY_DOWN,Vector2.DOWN],[KEY_A,Vector2.LEFT],[KEY_LEFT,Vector2.LEFT],[KEY_D,Vector2.RIGHT],[KEY_RIGHT,Vector2.RIGHT]]:
		place(open)
		key(pair[0],true)
		game._move_player(0.1)
		# Map simulation Y is up; native Up/W therefore increases world Y.
		var direction: Vector2 = Vector2(pair[1].x,-pair[1].y)
		check(game.player.get_position().is_equal_approx(open+direction*0.4),"native " + OS.get_keycode_string(pair[0]) + " moves smoothly at 128px/sec")
		key(pair[0],false)
		game._move_player(0.5)
		check(game.player.get_position().is_equal_approx(open+direction) and game.world.at_grid_rest(game.player.entity_id),"native key release finishes exactly one edge")
	place(open)
	key(KEY_D,true)
	game._move_player(0.1)
	key(KEY_D,false)
	key(KEY_W,true)
	game._move_player(0.1)
	check(game.player.get_position().is_equal_approx(open+Vector2(0.8,0)),"native turn cannot redirect an unfinished step")
	key(KEY_W,false)
	game._move_player(0.1)
	check(game.player.get_position().is_equal_approx(open+Vector2.RIGHT),"buffered turn released before arrival does not start another step")
	place(open)
	key(KEY_D,true)
	key(KEY_W,true)
	game._move_player(0.1)
	check(is_equal_approx(game.player.get_position().distance_to(open),0.4),"diagonal preserves world-space speed")
	key(KEY_D,false)
	key(KEY_W,false)
	game._move_player(0.15)
	check(not game.world.at_grid_rest(game.player.entity_id) and game.world.occupied_cell(game.player.entity_id) == grid.cell_at(open),"diagonal duration is longer and occupancy remains at source")
	game._move_player(0.11)
	check(game.player.get_position().is_equal_approx(open+Vector2.ONE),"diagonal release arrives at intended center")
	place(open)
	var peer := ActorSprite.new().configure(Vector2(32,32),Color.TRANSPARENT,"tile-peer")
	game.add_child(peer)
	peer.position = game._screen_position(open.x+1,open.y)
	game.combat.add_actor(CombatActor.new().configure({"entity_id":"tile-peer","x":open.x+1,"y":open.y,"hp":10,"max_hp":10}))
	game.world.grid_traveller("tile-peer")
	game.world.move_grid_direction(game.player.entity_id,Vector2.RIGHT,0.25,4.0)
	check(game.player.get_position().is_equal_approx(open+Vector2.RIGHT),"another actor collider does not reserve or block a tile")
	check(game.world.occupied_cell(game.player.entity_id) == game.world.occupied_cell("tile-peer"),"two live actors can share committed occupancy")
	game.world.move_grid_direction(game.player.entity_id,Vector2.LEFT,0.25,4.0)
	check(game.player.get_position().is_equal_approx(open),"actors can pass through each other under original layer rules")
	peer.queue_free()
	game.combat.remove_actor("tile-peer")
	game.world.grid_travellers.erase("tile-peer")
	var sprite: ActorSprite = game.actor_sprites[game.player.entity_id]
	var skin := CharacterSpriteLibrary.get_skin(sprite.skin_id)
	var source: Texture2D = load(skin.rotations.south)
	var walk: Texture2D = sprite.animated_sprite.sprite_frames.get_frame_texture("walk_south",0)
	check(source.get_size() == Vector2(64,64) and sprite.animated_sprite.scale == Vector2(0.75,0.75),"64px source artwork keeps its 48px world display scale")
	check((sprite.get_node("BodyCollision").shape as RectangleShape2D).size == Vector2(24,24),"24px body remains distinct from artwork and 32px gameplay cell")
	print("[Character scale] source=",source.get_size(),"; walk frame=",walk.get_size(),"; visual scale=",sprite.animated_sprite.scale,"; body=24x24; gameplay cell=32px")

func _run() -> void:
	var map: Node = load("res://scenes/GolemKingdom.tscn").instantiate()
	root.get_node("SceneTravel").set("_player",null)
	root.add_child(map)
	current_scene = map
	game = map.get_node("Combat")
	game.set_physics_process(false)
	for frame in range(60):
		await physics_frame
		if game.grid_adapter != null and game.grid_adapter.completed: break
	var start: Vector2 = game.player.get_position()
	controls()
	place(start)
	var route: PackedVector2Array = game.world.grid.path(start,start+Vector2(-4,0))
	check(route.size() >= 3,"real map provides a multi-step chase fixture")
	if route.size() < 3:
		finish()
		return
	for cancellation: String in ["clear","replace","dead"]:
		place(start)
		var foe := CombatActor.new().configure({"entity_id":"cancel-foe","x":route[-1].x,"y":route[-1].y,"hp":10000,"max_hp":10000,"is_monster":true})
		game.combat.add_actor(foe)
		game._set_target(foe.entity_id)
		game._start_auto_chase()
		game._update_auto_chase(0.1)
		var step: GridTraveller = game.world.grid_traveller(game.player.entity_id)
		check(step.active and step.goal.is_finite(),"chase starts a committed segment before " + cancellation)
		var committed := step.target
		if cancellation == "clear":
			game._clear_target()
		elif cancellation == "replace":
			game._set_target(foe.entity_id)
		else:
			foe.is_alive = false
		for frame in range(30):
			game._physics_process(1.0/60.0)
		check(game.player.get_position().is_equal_approx(committed) and game.world.at_grid_rest(game.player.entity_id),"chase " + cancellation + " finishes only the committed edge at a center")
		check(game.world.grid_traveller(game.player.entity_id).route.is_empty(),"chase " + cancellation + " discards stale remaining route")
		game.combat.remove_actor(foe.entity_id)
	map.queue_free()
	await process_frame
	finish()

func finish() -> void:
	print("[Grid controls] %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
