extends Node
## Isolated coverage: scripted account replies, ephemeral loopback transport, no live saves.

class TestHost extends "res://network/world_host.gd":
	func _ready() -> void:
		set_physics_process(false)

class ScriptedHTTP extends "res://network/account_http.gd":
	var replies: Array[Dictionary] = []
	var requests: Array[Dictionary] = []
	var response_delay_frames := 1

	func request_json(route: String, data: Dictionary = {}, _bearer: String = "", _server_key: String = "", _method: int = HTTPClient.METHOD_POST) -> Dictionary:
		requests.append({"route": route, "body": data.duplicate(true)})
		for _frame in range(response_delay_frames):
			await get_tree().process_frame
		if replies.is_empty():
			return {"ok": false, "code": "unexpected_request"}
		return replies.pop_front()

var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("[World host persistence FAIL] ", label)

func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(20).timeout.connect(func() -> void:
		printerr("[World host persistence FAIL] Timed out")
		get_tree().quit(1))

func fixture(peer: int) -> Dictionary:
	var host := TestHost.new()
	add_child(host)
	var http := ScriptedHTTP.new()
	host.add_child(http)
	host._http = http
	host._key = "isolated-test-key"
	var region := AuthoritativeRegion.new()
	region.configure("outskirts", null)
	host.regions["outskirts"] = region
	var player := PlayerState.new("PersistenceTest")
	player.entity_id = "stable-character"
	region.add_player(player.entity_id, player)
	var session := {"peer": peer, "character_id": player.entity_id, "username": player.name,
		"lease_token": "test-lease", "revision": 4, "region_id": "outskirts", "player": player,
		"state": {}, "hash": "", "busy": false, "queue": [], "pending": {},
		"last_save": 0, "heartbeat": 0, "disconnected": 0, "closing": false,
		"last_sequence": -1, "saving": false}
	host.sessions[peer] = session
	return {"host": host, "http": http, "region": region, "session": session}

func _run() -> void:
	configuration_capacity()
	await pending_save_then_release()
	await terminal_save_cleans_actor()
	await terminal_heartbeat_cleans_actor()
	await late_callback_preserves_replacement()
	await transient_heartbeat_recovers()
	await successful_inflight_save_preserves_simulation()
	await heartbeat_retries_pending_release_and_finishes_logout()
	await command_intents_during_normal_save()
	await failed_pending_rejects_new_intents()
	await transport_projects_acknowledged_orders()
	print("[World host persistence] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func configuration_capacity() -> void:
	var host := TestHost.new()
	check(host._configure({}) and host.max_players == 50, "Capacity defaults to 50 without imposing a fixed maximum of 50")
	for capacity: int in [51, 200, 4079]:
		check(host._configure({"max_players": capacity}) and host.max_players == capacity, "Configured capacity %d is accepted" % capacity)
	for capacity: Variant in [0, 50.5, 4080, "200"]:
		check(not host._configure({"max_players": capacity}), "Invalid capacity %s is rejected" % str(capacity))
	for configured_port: int in [1024, 24568, 65535]:
		check(host._configure({"port": configured_port}) and host.port == configured_port, "Configured port %d is accepted" % configured_port)
	for configured_port: Variant in [1023, 24567.5, 65536]:
		check(not host._configure({"port": configured_port}), "Invalid port %s is rejected" % str(configured_port))
	host.free()

func pending_save_then_release() -> void:
	var f := fixture(1001)
	f.http.replies.assign([{"ok": false, "code": "unavailable"}, {"ok": true, "revision": 5}, {"ok": true, "revision": 6}])
	check(not await f.host._persist(f.session), "An ambiguous save remains pending")
	check(f.region.frozen.has(f.session.character_id), "Pending save freezes the actor")
	var pending: Dictionary = f.session.pending.duplicate(true)
	f.session.player.gold = 17
	await f.host._finalize(f.session)
	check(f.http.requests.size() == 3, "Logout confirms pending save before its own release")
	if f.http.requests.size() >= 2:
		check(f.http.requests[1].route == "/internal/save", "Retry uses the original save endpoint")
		check(f.http.requests[1].body == pending, "Retry preserves operation ID, revision and exact payload")
	if f.http.requests.size() == 3:
		var release: Dictionary = f.http.requests[2]
		check(release.route == "/internal/release", "A fresh operation releases ownership")
		check(release.body.operation_id != pending.operation_id, "Release has a fresh operation identifier")
		check(release.body.expected_revision == 5 and release.body.state.gold == 17, "Release saves current state at confirmed revision")
	check(not f.host.sessions.has(1001) and not f.region.players.has("stable-character"), "Successful release removes host session and region actor")
	f.host.queue_free()
	await get_tree().process_frame

func terminal_save_cleans_actor() -> void:
	var f := fixture(1002)
	f.http.replies.assign([{"ok": false, "code": "stale_lease"}])
	check(not await f.host._persist(f.session), "Stale lease save is rejected")
	check(not f.host.sessions.has(1002), "Stale save retires the gameplay session")
	check(not f.region.players.has("stable-character") and not f.region.world.players.has("stable-character"), "Stale save removes the authoritative region actor")
	var replacement := PlayerState.new("Reconnected")
	f.region.add_player("stable-character", replacement)
	check(f.region.players.get("stable-character") == replacement, "Reconnect can install the new character instance without a ghost duplicate")
	f.host.queue_free()
	await get_tree().process_frame

func terminal_heartbeat_cleans_actor() -> void:
	var f := fixture(1003)
	f.http.replies.assign([{"ok": false, "code": "stale_lease"}])
	await f.host._heartbeat(f.session)
	check(not f.host.sessions.has(1003), "Expired ownership heartbeat retires the gameplay session")
	check(not f.region.players.has("stable-character") and not f.region.world.players.has("stable-character"), "Expired heartbeat removes the region actor")
	f.host.queue_free()
	await get_tree().process_frame

func late_callback_preserves_replacement() -> void:
	var f := fixture(1004)
	var old_session: Dictionary = f.session
	var replacement := PlayerState.new("Replacement")
	f.region.remove_player("stable-character")
	f.region.add_player("stable-character", replacement)
	var next: Dictionary = old_session.duplicate()
	next.player = replacement
	next.lease_token = "new-generation-lease"
	f.host.sessions[1004] = next
	f.http.replies.assign([{"ok": false, "code": "stale_lease"}])
	await f.host._heartbeat(old_session)
	check(f.host.sessions.get(1004, {}).get("lease_token") == "new-generation-lease", "A late old heartbeat cannot remove the replacement session")
	check(f.region.players.get("stable-character") == replacement, "A late old heartbeat cannot remove the replacement actor")
	f.host.queue_free()
	await get_tree().process_frame

func transient_heartbeat_recovers() -> void:
	var f := fixture(1005)
	f.http.replies.assign([{"ok": false, "code": "unavailable"}, {"ok": true}])
	await f.host._heartbeat(f.session)
	check(f.host.sessions.has(1005) and f.region.frozen.has("stable-character"), "Uncertain heartbeat pauses a retained session")
	await f.host._heartbeat(f.session)
	check(f.host.sessions.has(1005) and not f.region.frozen.has("stable-character"), "Confirmed ownership unpauses the same actor")
	f.host.queue_free()
	await get_tree().process_frame

func successful_inflight_save_preserves_simulation() -> void:
	var f := fixture(1006)
	f.http.response_delay_frames = 4
	f.http.replies.assign([{"ok": true, "revision": 5}, {"ok": true, "revision": 6}])
	var before: Vector2 = f.session.player.get_position()
	check(f.region.submit("stable-character", {"type": "move", "direction": [1.0, 0.0]}).ok, "Existing movement intent starts before autosave")
	f.host._persist(f.session)
	check(f.session.saving and not f.region.frozen.has("stable-character"), "A normal in-flight save does not freeze authoritative simulation")
	f.region.advance(0.1)
	var during: Vector2 = f.session.player.get_position()
	check(during.distance_to(before) > 0.05, "Authoritative movement advances while HTTP save is in flight")
	while f.session.saving:
		await get_tree().process_frame
	check(f.session.player.get_position().is_equal_approx(during), "Successful save acknowledgement does not rewind the live simulation")
	check(is_equal_approx(float(f.http.requests[0].body.state.x), before.x), "In-flight save payload stays immutable while simulation advances")
	check(is_equal_approx(float(f.session.state.x), before.x), "Acknowledged state represents exactly the committed snapshot")
	check(await f.host._persist(f.session), "A later checkpoint persists the advanced simulation")
	check(is_equal_approx(float(f.http.requests[1].body.state.x), during.x) and f.http.requests[1].body.expected_revision == 5, "Next save captures the live position at the new revision")
	f.host.queue_free()
	await get_tree().process_frame

func heartbeat_retries_pending_release_and_finishes_logout() -> void:
	var f := fixture(1007)
	f.http.replies.assign([{"ok": false, "code": "unavailable"}, {"ok": true}, {"ok": true, "revision": 5}])
	await f.host._finalize(f.session)
	check(f.host.sessions.has(1007) and f.session.pending_release, "Ambiguous final release remains recoverable")
	var release: Dictionary = f.http.requests[0].duplicate(true)
	await f.host._heartbeat(f.session)
	check(f.http.requests.size() == 3, "Ownership recovery retries the pending release")
	if f.http.requests.size() == 3:
		check(f.http.requests[2] == release, "Pending release retry preserves its original endpoint and exact operation")
	check(not f.host.sessions.has(1007) and not f.region.players.has("stable-character"), "A confirmed recovered release completes logout and removes the actor")
	f.host.queue_free()
	await get_tree().process_frame

func command_intents_during_normal_save() -> void:
	var f := fixture(1008)
	f.session.player.add_item("Low Grade Fish Food", 2)
	f.http.response_delay_frames = 4
	f.http.replies.assign([{"ok": true, "revision": 5}, {"ok": true, "revision": 6}])
	f.host._persist(f.session)
	var before: Vector2 = f.session.player.get_position()
	f.host._command(1008, {"type": "move", "direction": [1.0, 0.0], "sequence": 1})
	f.region.advance(0.1)
	check(f.session.player.x > before.x + 0.05, "A fresh movement intent is accepted during a normal in-flight save")
	var moved: Vector2 = f.session.player.get_position()
	f.host._command(1008, {"type": "move", "direction": [0.0, 1.0], "sequence": 2})
	f.region.advance(0.1)
	check(f.session.player.y > moved.y + 0.05, "Movement refresh can change direction while the save is pending")
	var drop := {"type": "drop", "item_name": "Low Grade Fish Food", "quantity": 1, "sequence": 3}
	f.host._command(1008, drop)
	f.host._command(1008, drop)
	check(f.session.busy and f.session.queue.size() == 1 and int(f.session.player.backpack.get("Low Grade Fish Food", 0)) == 2, "Reliable mutation waits for the existing save and duplicate sequence is ignored")
	while f.session.busy or f.session.saving:
		await get_tree().process_frame
	check(int(f.session.player.backpack.get("Low Grade Fish Food", 0)) == 1 and f.region.drops.size() == 1, "Queued mutation executes once after the original save confirms")
	check(f.http.requests.size() == 2 and f.http.requests[1].body.expected_revision == 5, "Queued mutation commits once at the confirmed next revision")
	check(f.session.queue.is_empty() and f.session.revision == 6, "Reliable command queue drains after durable mutation acknowledgement")
	f.host.queue_free()
	await get_tree().process_frame

func failed_pending_rejects_new_intents() -> void:
	var f := fixture(1009)
	# Isolate host input gating from the region's independent frozen-actor guard.
	f.session.pending = {"operation_id": "unconfirmed-save"}
	f.session.saving = false
	var before: Vector2 = f.session.player.get_position()
	f.host._command(1009, {"type": "move", "direction": [1.0, 0.0], "sequence": 1})
	f.region.advance(0.1)
	check(f.session.player.get_position().is_equal_approx(before), "An uncertain failed save rejects new movement intents")
	f.host._command(1009, {"type": "drop", "item_name": "Low Grade Fish Food", "quantity": 1, "sequence": 2})
	check(f.session.queue.is_empty() and not f.session.busy and f.http.requests.is_empty(), "An uncertain failed save rejects reliable mutations")
	f.session.saving = true
	f.session.pending_release = true
	f.host._command(1009, {"type": "move", "direction": [1.0, 0.0], "sequence": 3})
	f.region.advance(0.1)
	check(f.session.player.get_position().is_equal_approx(before), "An in-flight final release rejects gameplay input")
	f.session.saving = false
	f.host.queue_free()
	await get_tree().process_frame

func transport_projects_acknowledged_orders() -> void:
	# Use a separate in-process client multiplayer root: real joined/snapshot RPCs,
	# scripted account responses, no account service or player storage.
	var f := fixture(1010)
	f.host.sessions.clear()
	f.region.remove_player("stable-character")
	f.session.player.dead_man_orders = load("res://scripts/dev_tools/character_persistence_smoke.gd").private_orders_fixture("stable-character")
	var state := CharacterCodec.encode(f.session.player, "outskirts")
	f.http.replies.assign([{"ok": true, "state": state, "username": "PersistenceTest",
		"character_id": "stable-character", "lease_token": "test-lease", "revision": 4},
		{"ok": true, "revision": 5}])
	var port := 36000 + int(Crypto.new().generate_random_bytes(2).decode_u16(0)) % 20000
	var error: Error = Network.host(port, 2)
	check(error == OK, "Isolated packet test binds its local test transport")
	if error != OK:
		f.host.queue_free()
		return
	Network.join_requested.connect(f.host._join)
	var root := Node.new()
	root.name = "OrdersTestClient"
	add_child(root)
	var api := SceneMultiplayer.new()
	get_tree().set_multiplayer(api, root.get_path())
	var client: Node = load("res://autoload/network_manager.gd").new()
	client.name = "Network"
	client.auto_scene = false
	client.mode = client.Mode.CLIENT
	client.world_id = Network.world_id
	client._ticket = "isolated-orders-ticket"
	root.add_child(client)
	var peer := ENetMultiplayerPeer.new()
	error = peer.create_client("127.0.0.1", port, 3)
	check(error == OK, "Isolated projection client starts")
	api.multiplayer_peer = peer
	var deadline := Time.get_ticks_msec() + 3000
	while not client.authenticated and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(client.authenticated, "Joined result reaches the real client RPC consumer")
	if client.authenticated:
		check(not client.saved_state.has("dead_man_orders") and client.saved_state.has("orders_view"), "Actual joined packet omits the private order book")
		check(client.saved_state.get("public_projection") == true, "Joined packet identifies its public projection")
		check(not JSON.stringify(client.saved_state).contains("SECRET_"), "Actual joined packet hides future directives, answers and cache")
		var session: Dictionary = f.host.sessions.values()[0]
		# Live changes are deliberately not acknowledged or persisted yet.
		session.player.dead_man_orders.generations.deckhand = 17
		session.saving = true
		f.host._service_sessions()
		deadline = Time.get_ticks_msec() + 3000
		while int(client.latest_snapshot.get("snapshot_id", -1)) < 0 and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		var sent: Dictionary = client.latest_snapshot.get("state", {})
		check(not sent.has("dead_man_orders") and sent.has("orders_view"), "Actual owner snapshot omits the private order book")
		check(int(sent.get("orders_view", {}).get("generations", {}).get("deckhand", -1)) == 1, "Snapshots project acknowledged state rather than uncommitted order changes")
		check(not JSON.stringify(sent).contains("SECRET_"), "Actual owner snapshot hides future directives, answers and cache")
		check(session.state.dead_man_orders.generations.deckhand == 1, "Projection does not mutate acknowledged state")
	Network.join_requested.disconnect(f.host._join)
	peer.close()
	Network.multiplayer.multiplayer_peer.close()
	Network.multiplayer.multiplayer_peer = null
	Network.mode = Network.Mode.OFFLINE
	get_tree().set_multiplayer(null, root.get_path())
	root.queue_free()
	f.host.queue_free()
	await get_tree().process_frame
