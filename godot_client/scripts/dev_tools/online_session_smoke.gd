extends Node

var failures := 0
var checks := 0
var net: Node

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("[Online session FAIL] ", label)

func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(90).timeout.connect(func() -> void:
		printerr("[Online session FAIL] Timed out")
		get_tree().quit(1))

func _run() -> void:
	net = get_node_or_null("/root/Network")
	check(net != null, "Active game has a working networking autoload")
	if net == null:
		get_tree().quit(1)
		return
	net.auto_scene = false
	var args := OS.get_cmdline_user_args()
	var input := ""
	for arg: String in args:
		if arg.begins_with("--test-input="):
			input = arg.trim_prefix("--test-input=")
	if input.is_empty():
		check(false, "Integration input supplied by the Python runner")
		get_tree().quit(1)
		return
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(input))
	net.username = config.username
	net.account_token = config.get("token", "")
	var error: int = net.join_world(config.ticket)
	check(error == OK, "World transport connects")
	await net.joined
	check(net.authenticated and net.character_id == config.character_id, "Backend identity owns the world actor")
	check(net.saved_state.get("version") == 1, "Initial or returning character loaded durably")
	if config.has("expected_state"):
		var expected: Dictionary = config.expected_state
		check(net.saved_state.inventory == expected.inventory and net.saved_state.skill_experience == expected.skill_experience and net.saved_state.gold == expected.gold, "Inventory and progress resume across login sessions")
		check(Vector2(float(net.saved_state.x), float(net.saved_state.y)).distance_to(Vector2(float(expected.x), float(expected.y))) < 0.5, "Logout saved final server position")
	var scene := (load("res://scenes/EastOutskirtsLayered.tscn") as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	var game: Node = scene.get_node("Combat")
	check(game.player.entity_id == net.character_id, "Rendered map uses persistent online identity")
	await get_tree().create_timer(1).timeout
	var start: Vector2 = game.player.get_position()
	game.movement_controller.holding.right = true
	for _index in range(5):
		net.send_action({"type": "move", "direction": [1.0, 0.0]})
		await get_tree().create_timer(0.1).timeout
	game.movement_controller.holding.right = false
	net.send_action({"type": "move", "direction": [0.0, 0.0]})
	await get_tree().create_timer(0.5).timeout
	check(game.player.get_position().distance_to(start) <= 4.5, "Movement is server-speed limited")
	check(game.player.get_position().distance_to(start) > 0.05, "Server movement reaches the rendered character")
	net.send_action({"type": "grant", "gold": 999999})
	await get_tree().create_timer(0.3).timeout
	check(game.player.gold < 999999, "Client cannot grant gold")
	if config.has("output"):
		var output := FileAccess.open(config.output, FileAccess.WRITE)
		var expected: Dictionary = net.saved_state.duplicate(true)
		expected.x = game.player.x
		expected.y = game.player.y
		output.store_string(JSON.stringify({"character_id": net.character_id, "state": expected, "revision": net.revision, "checks": checks, "failures": failures}))
	net.request_logout()
	await get_tree().create_timer(2).timeout
	check(not net.authenticated, "Logout completes only after save")
	print("[Online session] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
