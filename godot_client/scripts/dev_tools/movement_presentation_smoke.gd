extends SceneTree
## Catch delayed local input, repeated replay, wall penetration and stale snapshots.
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("_run")

func _wall(start: Vector2, motion: Vector2) -> Vector2:
	return Vector2(minf(start.x + motion.x, 1.0), start.y + motion.y)

func _run() -> void:
	var path := "res://network/movement_prediction.gd"
	check(ResourceLoader.exists(path), "Online movement must respond between server snapshots")
	if failures > 0:
		quit(1)
		return
	var model = load(path).new()
	model.reset(Vector2.ZERO)
	model.record_input(1, Vector2.RIGHT)
	model.advance(1.0 / 60.0, Vector2.RIGHT)
	check(model.position.x > 0.06, "First frame responds without a server round trip")
	var before: Vector2 = model.position
	model.record_input(2, Vector2.ZERO)
	model.advance(1.0 / 60.0, Vector2.ZERO)
	check(model.position.is_equal_approx(before), "Release stops immediately")
	model.reset(Vector2.ZERO)
	model.record_input(1, Vector2.RIGHT)
	model.advance(0.1, Vector2.RIGHT)
	model.reconcile(Vector2.ZERO, -1, 0.0)
	check(absf(model.position.x - 0.4) < 0.001, "Snapshot predating first input preserves all pending prediction")
	model.advance(1.0 / 60.0, Vector2.RIGHT)
	check(model.render_position().x > 0.4, "Delayed acknowledgement cannot pull held movement backwards")
	model.reset(Vector2.ZERO)
	model.record_input(10, Vector2.RIGHT)
	for i in range(6):
		model.advance(1.0 / 60.0, Vector2.RIGHT)
	model.reconcile(Vector2(0.2, 0), 10, 0.05)
	check(absf(model.position.x - 0.4) < 0.001, "Replay only time not represented in acknowledged server state")
	model.reconcile(Vector2(0.2, 0), 10, 0.05)
	check(absf(model.position.x - 0.4) < 0.001, "Duplicate reconciliation cannot accumulate movement")
	model.record_input(11, Vector2.LEFT)
	model.advance(0.05, Vector2.LEFT)
	check(absf(model.position.x - 0.2) < 0.001, "Direction reversal takes effect immediately")
	model.reset(Vector2.ZERO)
	model.move_resolver = _wall
	model.record_input(20, Vector2.RIGHT)
	for i in range(12):
		model.advance(1.0 / 60.0, Vector2.RIGHT)
	check(model.position.x <= 1.0, "Prediction obeys collision geometry")
	model.move_resolver = Callable()
	model.reset(Vector2.ZERO)
	model.record_input(30, Vector2.ONE)
	model.advance(0.1, Vector2.ONE)
	check(absf(model.position.length() - 0.4) < 0.001, "Diagonal movement cannot exceed server speed")
	for i in range(120):
		model.advance(1.0 / 60.0, Vector2.RIGHT)
	check(model.position.length() <= 1.001, "Missing server snapshots bound speculative travel")
	model.reconcile(Vector2(10, 10), -1, 0.0, false)
	model.advance(0.1, Vector2.RIGHT)
	check(model.position.is_equal_approx(Vector2(10, 10)), "Freeze cancels speculation and history")
	# Idle time still makes authority stale. Integration latency measurements
	# must wait for live readiness rather than extending this outage allowance.
	model.reset(Vector2.ZERO)
	model.advance(1.0, Vector2.ZERO)
	model.record_input(31, Vector2.RIGHT)
	model.advance(1.0 / 60.0, Vector2.RIGHT)
	check(model.position.is_zero_approx(), "Input after idle snapshot loss preserves the stale-authority freeze")
	model.reconcile(Vector2.ZERO, -1, 0.0)
	model.advance(1.0 / 60.0, Vector2.RIGHT)
	check(model.render_position().x > 0.06, "Fresh authority restores first-frame input after idle snapshot loss")
	model.reset(Vector2(50, 50))
	check(model.render_position().is_equal_approx(Vector2(50, 50)), "Region reset cannot interpolate across maps")
	# At 60 FPS a 10 Hz snapshot-only renderer changes nine times between
	# its first and last packets. Prediction should keep moving each frame.
	model.reset(Vector2.ZERO)
	var rendered_frames := 0
	var packet_only_frames := 0
	var previous := Vector2.ZERO
	var packet_position := Vector2.ZERO
	for frame in range(60):
		if frame % 2 == 0:
			model.record_input(frame + 1, Vector2.RIGHT)
		if frame % 6 == 0:
			var authority := Vector2(float(frame) / 15.0, 0.0)
			model.reconcile(authority, frame + 1, 0.0)
			if not authority.is_equal_approx(packet_position):
				packet_only_frames += 1
			packet_position = authority
		model.advance(1.0 / 60.0, Vector2.RIGHT)
		if model.render_position().x > previous.x:
			rendered_frames += 1
		previous = model.render_position()
	check(rendered_frames == 60 and packet_only_frames == 9, "10 Hz snapshots retain continuous 60 FPS movement")
	check(absf(model.position.x - 4.0) < 0.001, "Repeated snapshots and replay preserve travel distance")
	print("[Movement benchmark] 60 FPS / 10 Hz snapshots: packet-only=%d moving frames; predicted=%d; first response=16.67ms" % [packet_only_frames, rendered_frames])
	var remote_path := "res://network/snapshot_interpolation.gd"
	check(ResourceLoader.exists(remote_path), "Remote motion must interpolate server samples")
	if ResourceLoader.exists(remote_path):
		var remote = load(remote_path).new()
		remote.push(1.0, Vector2(0, 0))
		remote.push(1.1, Vector2(0.4, 0))
		check(remote.sample(1.05).is_equal_approx(Vector2(0.2, 0)), "Remote actor occupies midpoint between packets")
		remote.push(1.0, Vector2(100, 100))
		check(remote.sample(1.05).is_equal_approx(Vector2(0.2, 0)), "Out of order packet cannot rewind interpolation")
		check(remote.sample(5.0).is_equal_approx(Vector2(0.4, 0)), "Packet loss holds latest remote position instead of running through walls")
		remote.push(1.2, Vector2(20, 20))
		check(remote.sample(1.15).is_equal_approx(Vector2(20, 20)), "Teleport-sized changes snap instead of streaking")
	print("[Movement presentation] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
