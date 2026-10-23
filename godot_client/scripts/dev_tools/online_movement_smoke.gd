extends SceneTree
## Real map/sprite/camera integration, with deterministic packet arrival times.
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var network: Node = root.get_node("Network")
	network.set_process(false)
	var map: Node = load("res://scenes/EastOutskirtsLayered.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	await physics_frame
	await process_frame
	var game: Node = map.get_node("Combat")
	game.set_physics_process(false)
	network.mode = network.Mode.CLIENT
	network.authenticated = true
	network.game = game
	var view: Node = load("res://network/online_world_view.gd").new()
	game.add_child(view)
	view.configure(game)
	view.set_process(false)
	game.online_view = view
	check(view.has_method("advance_presentation"), "Online sprites must advance between snapshots")
	if not view.has_method("advance_presentation"):
		quit(1)
		return
	var id: String = game.player.entity_id
	var origin: Vector2 = game.player.get_position()
	var sprite: ActorSprite = game.actor_sprites[id]
	var direction := Vector2.ZERO
	for candidate: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		sprite.position = game._screen_position(origin.x, origin.y)
		if game._move_actor_with_map_collision(id, candidate * 0.1).length() > 0.09:
			direction = candidate
			break
	check(not direction.is_zero_approx(), "Authored spawn has an unobstructed direction for input measurement")
	var actor_data := {"entity_id":id,"name":"Movement fixture","x":origin.x,"y":origin.y,"hp":20,"max_hp":20,"is_alive":true,"is_monster":false}
	var packet := {"actors":[actor_data],"server_time":1.0,"movement_ack":-1,"movement_age":0.0,"movement_enabled":true,"snapshot_interval":0.1}
	view.apply(packet)
	var before: Vector2 = sprite.position
	view.record_command(1, {"type":"move","direction":[direction.x, direction.y]})
	view.advance_presentation(1.0 / 60.0, direction)
	check(sprite.position.distance_to(before) > 1.9, "Rendered local movement appears in one 60 Hz frame without another snapshot")
	check(game.player.get_position().is_equal_approx(origin), "Prediction cannot write authoritative player coordinates")
	check(Vector2(game.combat.actors[id].x, game.combat.actors[id].y).is_equal_approx(origin), "Prediction cannot advance combat authority")
	var moved: Vector2 = sprite.position
	view.record_command(2, {"type":"move","direction":[0,0]})
	view.advance_presentation(1.0 / 60.0, Vector2.ZERO)
	check(sprite.position.is_equal_approx(moved), "Local release stops on the next frame")
	view.record_command(3, {"type":"walk","x":origin.x + direction.x,"y":origin.y + direction.y})
	view.advance_presentation(1.0 / 60.0, Vector2.ZERO)
	check(sprite.position.is_equal_approx(moved), "Switching from keys to click movement preserves the displayed position until correction")
	packet.server_time = 1.1
	actor_data.x = origin.x + direction.x * 0.2
	actor_data.y = origin.y + direction.y * 0.2
	view.apply(packet)
	before = game._screen_position(origin.x, origin.y)
	view.advance_presentation(1.0 / 60.0, Vector2.ZERO)
	check(sprite.position.distance_to(before) > 0.01, "Own click movement does not wait for the remote interpolation delay")
	packet.movement_enabled = false
	view.apply(packet)
	check(sprite.position.is_equal_approx(game._screen_position(actor_data.x, actor_data.y)), "Alive frozen self snaps back to its authoritative position")
	packet.actors = []
	packet.movement_enabled = false
	view.apply(packet)
	before = sprite.position
	view.advance_presentation(0.1, direction)
	check(sprite.position.is_equal_approx(before), "Frozen/absent self actor stops client prediction")
	print("[Online movement] %d checks, %d failures" % [checks, failures])
	network.authenticated = false
	network.game = null
	quit(0 if failures == 0 else 1)
