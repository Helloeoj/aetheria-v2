extends Node
## Actual host/region movement intent coverage; no sockets, HTTP or live saves.

class TestHost extends "res://network/world_host.gd":
	func _ready() -> void:
		set_physics_process(false)
	func _persist(_session: Dictionary, _release: bool = false) -> bool:
		return true

class DelayedTravelHost extends TestHost:
	# Isolate the loading await from map content; queue, ack and movement are real.
	func _travel(_session: Dictionary, _portal_id: String) -> Dictionary:
		await get_tree().process_frame
		return {"ok": true}

var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("[Movement server FAIL] ", label)

func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(15).timeout.connect(func() -> void:
		printerr("[Movement server FAIL] Timed out")
		get_tree().quit(1))

func fixture(delayed_travel: bool = false) -> Dictionary:
	var host: TestHost = DelayedTravelHost.new() if delayed_travel else TestHost.new()
	add_child(host)
	var region := AuthoritativeRegion.new()
	region.configure("outskirts", null)
	var player := PlayerState.new("Movement test")
	player.x = 14.0
	player.y = 15.0
	player.set_skill_level("magic", 100)
	region.add_player("movement-character", player)
	host.regions["outskirts"] = region
	# Deliberately retain older fixture shape: new session fields need defaults.
	var session := {"peer": 12001, "character_id": player.entity_id,
		"region_id": "outskirts", "player": player, "busy": false, "queue": [],
		"pending": {}, "closing": false, "disconnected": 0, "last_sequence": -1, "saving": false}
	host.sessions[12001] = session
	return {"host": host, "region": region, "session": session, "player": player}

func metadata(f: Dictionary) -> Dictionary:
	if not f.host.has_method("_movement_snapshot"):
		check(false, "Host publishes movement acknowledgement metadata")
		return {}
	return f.host.call("_movement_snapshot", f.session, f.region)

func command(f: Dictionary, data: Dictionary, serial: int) -> void:
	var intent := data.duplicate(true)
	intent.sequence = serial
	f.host._command(12001, intent)

func move(f: Dictionary, serial: int, direction: Vector2) -> void:
	command(f, {"type": "move", "direction": [direction.x, direction.y]}, serial)

func _run() -> void:
	defaults_and_simulation_time()
	accepted_rejected_and_stale_moves()
	movement_enablement()
	reliable_intent_ordering()
	await queued_intent_ordering()
	await awaited_travel_ordering()
	accepted_actions_cancel_replay()
	print("[Movement server] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func defaults_and_simulation_time() -> void:
	var f := fixture()
	var initial := metadata(f)
	check(int(initial.get("movement_ack", -2)) == -1, "A new session has no acknowledged keyboard intent")
	check(is_equal_approx(float(initial.get("movement_age", -1.0)), 0.0), "An absent keyboard intent has zero age")
	check(is_equal_approx(float(initial.get("server_time", -1.0)), 0.0), "New region metadata uses simulation time")
	check(is_equal_approx(float(initial.get("snapshot_interval", -1.0)), 0.1), "Default snapshot interval describes server publication rate")
	f.host.snapshot_hz = 20.0
	move(f, 7, Vector2.RIGHT)
	f.region.advance(0.1)
	var state := metadata(f)
	check(int(state.get("movement_ack", -1)) == 7, "Accepted movement serial reaches snapshot metadata")
	check(is_equal_approx(float(state.get("server_time", -1.0)), 0.1), "Server time advances only with region simulation")
	check(is_equal_approx(float(state.get("movement_age", -1.0)), 0.1), "Acknowledgement age measures simulation since intent acceptance")
	check(is_equal_approx(float(state.get("snapshot_interval", -1.0)), 0.05), "Configured snapshot frequency reaches metadata")
	f.host.queue_free()

func accepted_rejected_and_stale_moves() -> void:
	var f := fixture()
	move(f, 8, Vector2.RIGHT)
	f.region.advance(0.1)
	var before: Vector2 = f.player.get_position()
	move(f, 7, Vector2.UP)
	move(f, 8, Vector2.ZERO)
	f.region.advance(0.05)
	check(f.player.x > before.x and is_equal_approx(f.player.y, before.y), "Stale and duplicate direct host movement cannot replace newer direction")
	command(f, {"type": "move", "direction": ["bad", 0]}, 9)
	check(int(metadata(f).get("movement_ack", -1)) == 8, "Rejected malformed movement never advances acknowledgement")
	f.region.frozen[f.player.entity_id] = true
	move(f, 10, Vector2.UP)
	check(int(metadata(f).get("movement_ack", -1)) == 8, "Frozen character never acknowledges rejected movement")
	f.region.frozen.clear()
	f.session.pending = {"operation_id": "unconfirmed"}
	move(f, 11, Vector2.UP)
	check(int(metadata(f).get("movement_ack", -1)) == 8, "Uncertain persistence never acknowledges blocked input")
	f.session.pending = {}
	move(f, 12, Vector2.ZERO)
	f.region.advance(0.1)
	check(int(metadata(f).get("movement_ack", -1)) == 12, "Accepted release input acknowledges its own serial")
	var stopped: Vector2 = f.player.get_position()
	f.region.advance(0.3)
	check(f.player.get_position().is_equal_approx(stopped), "Release input stops authoritative movement")
	f.host.queue_free()

func movement_enablement() -> void:
	var f := fixture()
	check(bool(metadata(f).get("movement_enabled", false)), "Living available character permits prediction")
	f.session.saving = true
	check(bool(metadata(f).get("movement_enabled", false)), "Normal in-flight autosave keeps movement enabled")
	f.session.saving = false
	for field: String in ["closing", "retired", "ownership_paused"]:
		f.session[field] = true
		check(not bool(metadata(f).get("movement_enabled", true)), "Movement is disabled while " + field)
		f.session[field] = false
	f.region.frozen[f.player.entity_id] = true
	check(not bool(metadata(f).get("movement_enabled", true)), "Frozen simulation disables prediction")
	f.region.frozen.clear()
	f.region.world.combat.actors[f.player.entity_id].is_alive = false
	check(not bool(metadata(f).get("movement_enabled", true)), "Death disables prediction")
	move(f, 20, Vector2.RIGHT)
	check(int(metadata(f).get("movement_ack", -2)) == -1, "Dead character cannot acknowledge movement")
	f.host.queue_free()

func reliable_intent_ordering() -> void:
	var f := fixture()
	move(f, 20, Vector2.RIGHT)
	command(f, {"type": "target", "target_id": ""}, 19)
	var start: Vector2 = f.player.get_position()
	f.region.advance(0.05)
	check(f.player.x > start.x, "Older reliable target cannot override accepted newer keyboard movement")
	command(f, {"type": "target", "target_id": ""}, 21)
	check(int(metadata(f).get("movement_ack", -2)) == -1, "Accepted newer target clears keyboard replay acknowledgement")
	move(f, 20, Vector2.RIGHT)
	start = f.player.get_position()
	f.region.advance(0.05)
	check(f.player.get_position().is_equal_approx(start), "Late keyboard packet cannot override newer accepted target")
	move(f, 22, Vector2.UP)
	f.region.advance(0.05)
	check(f.player.y < start.y and int(metadata(f).get("movement_ack", -1)) == 22, "Fresh keyboard intent after target remains usable")
	f.host.queue_free()

func queued_intent_ordering() -> void:
	var f := fixture()
	f.session.saving = true
	command(f, {"type": "walk", "x": 14.0, "y": 17.0}, 30)
	check(f.session.queue.size() == 1 and f.session.busy, "Reliable walk can wait for an ordinary save")
	move(f, 31, Vector2.RIGHT)
	f.session.saving = false
	await get_tree().process_frame
	var start: Vector2 = f.player.get_position()
	f.region.advance(0.05)
	check(f.player.x > start.x and is_equal_approx(f.player.y, start.y), "Queued older walk cannot override keyboard movement accepted during autosave")
	check(f.session.queue.is_empty() and not f.session.busy, "Superseded reliable movement drains normally")
	f.host.queue_free()

func accepted_actions_cancel_replay() -> void:
	for action: Dictionary in [{"type": "walk", "x": 14.0, "y": 17.0},
		{"type": "target", "target_id": ""}, {"type": "attack", "target_id": ""},
		{"type": "cast", "spell_id": "fire_scorch", "target_id": "goblin-1"}]:
		var f := fixture()
		if action.type == "cast":
			preload("res://scripts/dev_tools/region_combat_fixture.gd").add_monsters(f.region)
			action.target_id = f.region.world.monsters[0].entity_id
		move(f, 1, Vector2.RIGHT)
		command(f, action, 2)
		check(int(metadata(f).get("movement_ack", -2)) == -1, "Accepted " + String(action.type) + " clears keyboard replay")
		check(is_equal_approx(float(metadata(f).get("movement_age", -1.0)), 0.0), "Accepted " + String(action.type) + " clears keyboard age")
		move(f, 1, Vector2.UP)
		check(int(metadata(f).get("movement_ack", -2)) == -1, "Late keyboard packet remains superseded after " + String(action.type))
		f.host.queue_free()

func awaited_travel_ordering() -> void:
	var f := fixture(true)
	command(f, {"type": "travel", "portal_id": "fixture"}, 40)
	move(f, 41, Vector2.RIGHT)
	await get_tree().process_frame
	check(int(metadata(f).get("movement_ack", -2)) == -1, "Completed region transfer clears keyboard replay from its source")
	move(f, 41, Vector2.UP)
	check(int(metadata(f).get("movement_ack", -2)) == -1, "Awaited travel cannot make an already accepted source packet fresh again")
	f.host.queue_free()
