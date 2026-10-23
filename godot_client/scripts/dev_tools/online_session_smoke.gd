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
	net.world_id = config.get("world_id", "world-1")
	# Isolated encrypted beta tests supply private loopback transport settings.
	if config.has("account_url"):
		net.account_url = String(config.account_url)
	if config.has("beta_profile"):
		net.beta_profile = config.beta_profile
	if config.has("release_id"):
		net.release_id = String(config.release_id)
	var error: int = net.join_world(config.ticket, "127.0.0.1", int(config.get("port", 24567)))
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
	check(net.latest_snapshot.has("movement_ack") and net.latest_snapshot.has("server_time"), "Live world publishes movement reconciliation metadata")
	# Loading the full map blocks polling and drains queued startup snapshots.
	# Require two new consecutive movement-enabled snapshots at live cadence;
	# prediction deliberately freezes after 250 ms without authoritative state.
	var readiness_at := Time.get_ticks_usec()
	var previous_snapshot := int(net.latest_snapshot.get("snapshot_id", -1))
	var previous_received_at := 0
	var ready_snapshots := 0
	var last_interval_ms := -1.0
	while Time.get_ticks_usec() - readiness_at < 5000000 and ready_snapshots < 2:
		await get_tree().process_frame
		var serial := int(net.latest_snapshot.get("snapshot_id", -1))
		if serial <= previous_snapshot:
			continue
		var now := Time.get_ticks_usec()
		last_interval_ms = float(now - previous_received_at) / 1000.0 if previous_received_at > 0 else -1.0
		if bool(net.latest_snapshot.get("movement_enabled", false)) and game.online_view._has_self:
			ready_snapshots = ready_snapshots + 1 if serial == previous_snapshot + 1 and last_interval_ms >= 20.0 and last_interval_ms <= 250.0 else 1
		else:
			ready_snapshots = 0
		previous_snapshot = serial
		previous_received_at = now
	check(ready_snapshots >= 2, "Post-load transport supplies consecutive movement-enabled snapshots within 250ms")
	print("[Live readiness] snapshots=%d; interval=%.2fms; wait=%.2fms" % [ready_snapshots, last_interval_ms, float(Time.get_ticks_usec() - readiness_at) / 1000.0])
	if ready_snapshots < 2:
		get_tree().quit(1)
		return
	var start: Vector2 = game.player.get_position()
	var sprite: ActorSprite = game.actor_sprites[game.player.entity_id]
	var rendered_start := sprite.position
	game.movement_controller.holding.right = true
	var input_at := Time.get_ticks_usec()
	var first_motion_ms := -1.0
	var observed_frames := 0
	# Headless frames can run much faster than display frames. Keep the actual
	# 100 ms response requirement rather than ending after twelve tiny frames.
	while Time.get_ticks_usec() - input_at < 100000:
		await get_tree().process_frame
		observed_frames += 1
		if sprite.position.distance_to(rendered_start) > 0.01:
			first_motion_ms = float(Time.get_ticks_usec() - input_at) / 1000.0
			break
	check(first_motion_ms >= 0.0 and first_motion_ms < 100.0, "Local input renders before the 100ms snapshot cadence")
	print("[Live movement] first rendered response=%.2fms; snapshots=10Hz; prediction never writes saves" % first_motion_ms)
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
