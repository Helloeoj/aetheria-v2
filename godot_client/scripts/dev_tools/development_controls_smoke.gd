extends Node
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("[Development controls FAIL] ", label)

func frames(count: int = 3) -> void:
	for _frame in count:
		await get_tree().process_frame

func key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		get_tree().root.push_input(event)
		await frames()

func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(45).timeout.connect(func() -> void: get_tree().quit(1))

func _run() -> void:
	var region := AuthoritativeRegion.new()
	region.configure("fresh-world", null)
	check(region.world.monsters.is_empty(), "Starting a real region never invents goblin encounters")
	var login := (load("res://scenes/Login.tscn") as PackedScene).instantiate()
	add_child(login)
	await frames()
	var sandbox := login.get_node_or_null("Center/Frame") # Buttons are discovered by label below.
	for node: Node in login.find_children("*", "Button", true, false):
		if node.text.begins_with("Developer sandbox"):
			sandbox = node
	check(sandbox != null, "Login exposes developer testing without an account or server")
	login.queue_free()
	await frames()
	Network.mode = Network.Mode.OFFLINE
	var map := (load("res://scenes/EastOutskirtsLayered.tscn") as PackedScene).instantiate()
	add_child(map)
	await frames(6)
	var game: Node = map.get_node("Combat")
	check(game.fishing_test_button.visible and game.skill_test_button.visible, "Practice buttons remain available in developer sandbox")
	check(game.ui_root.get_node_or_null("OnlineLoginButton") != null, "Developer map offers an explicit online login entry")
	await key(KEY_F5)
	check(game.spawn_menu.visible, "F5 opens monster testing")
	game.spawn_menu.hide()
	await key(KEY_F6)
	check(game.item_menu.visible, "F6 opens item testing")
	game.item_menu.hide()
	await key(KEY_F7)
	check(game.sprite_preview.visible, "F7 opens sprite testing")
	await key(KEY_ESCAPE)
	await key(KEY_K)
	check(game.skill_debug_panel.visible, "K opens skill testing")
	await key(KEY_K)
	await key(KEY_P)
	check(game.fishing_panel.visible, "P opens the original fishing practice panel")
	game.fishing_panel.close()
	await frames()
	var spots: Array[FishingSpot] = game.fishing_spots()
	check(not spots.is_empty(), "Existing authored fishing spots remain")
	if not spots.is_empty():
		var spot := spots[0]
		var local: Vector2 = game.to_local(spot.shore_position())
		var actor: CombatActor = game.combat.actors[game.player.entity_id]
		actor.x = (local.x - game.map_origin.x) / game.TILE_SIZE
		actor.y = (game.map_origin.y + game.map_height - local.y) / game.TILE_SIZE
		if game.world.grid != null:
			var route: PackedVector2Array = game.world.grid.path(game.player.get_position(),Vector2(actor.x,actor.y),spot.interact_radius/game.TILE_SIZE)
			check(not route.is_empty(),"Native F fixture uses a reachable tile center within shore range")
			if not route.is_empty():
				actor.x = route[-1].x
				actor.y = route[-1].y
		game.player.x = actor.x
		game.player.y = actor.y
		game._update_sprite_position(actor.entity_id)
		await key(KEY_F)
		check(game.fishing_panel.visible, "Native F near shore opens the fishing panel")
		await key(KEY_ESCAPE)
		check(not game.fishing_panel.visible, "Escape closes fishing and releases input")
	check(Network.mode == Network.Mode.OFFLINE and not Network.authenticated, "Sandbox never authenticates or writes online character progress")
	print("[Development controls] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
