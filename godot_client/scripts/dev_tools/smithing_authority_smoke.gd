extends Node
class Geometry extends Node2D:
	var map_width := 1536.0
	var map_height := 1024.0
class GateHost extends "res://network/world_host.gd":
	var outcome := {}
	func _ready() -> void: set_physics_process(false)
	func _process_commands(session: Dictionary) -> void:
		outcome = {}
		while not session.queue.is_empty():
			var data: Dictionary = session.queue.pop_front()
			data.erase("sequence")
			outcome = regions[session.region_id].submit(session.character_id, data)
class Transport extends Node:
	signal action_result(sequence: int, result: Dictionary)
	var latest_snapshot := {}
	var status := ""
	var sequence := 0
	var authority: AuthoritativeRegion
	var owner_id := ""
	var gate: GateHost
	var hold_results := false
	var held_results: Array = []
	func send_action(data: Dictionary) -> bool:
		sequence += 1
		var outcome: Dictionary
		if gate != null:
			gate.outcome = {}
			var wire := data.duplicate(true)
			wire["sequence"] = sequence
			gate._command(99, JSON.parse_string(JSON.stringify(wire)))
			outcome = gate.outcome
		else:
			outcome = authority.submit(owner_id, JSON.parse_string(JSON.stringify(data)))
		latest_snapshot = authority.snapshot(owner_id)
		if not outcome.is_empty():
			if hold_results: held_results.append([sequence, outcome])
			else: action_result.emit.call_deferred(sequence, outcome)
		return true
var checks := 0
var failures := 0
var region: AuthoritativeRegion
var player: PlayerState
var stations := {}

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("[Smithing authority FAIL] " + label)

func command(data: Dictionary) -> Dictionary:
	return region.submit(player.entity_id, JSON.parse_string(JSON.stringify(data)))

func start(recipe: String, station: String, token: String, quantity: int = 1) -> Dictionary:
	return command({"type":"smith_start", "station_id":stations[station], "recipe_id":recipe, "start_token":token, "quantity":quantity})

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var geometry := Geometry.new()
	add_child(geometry)
	for id: String in ["anvil", "furnace"]:
		var station := CraftingStation.new()
		station.name = id
		station.setup(id, id, Vector2(10, 10))
		geometry.add_child(station)
	region = AuthoritativeRegion.new()
	region.configure("smithing", geometry)
	for id: String in region.stations: stations[region.stations[id].station] = id
	player = PlayerState.new()
	region.add_player("smith", player)
	player.add_item("Bronze Ore", 3)
	check(not command({"type":"craft", "station_id":stations.furnace, "recipe_id":"smelt_bronze", "quantity":3}).ok and player.backpack == {"Bronze Ore":3}, "Instant server craft cannot bypass the furnace")
	check(start("smelt_bronze", "furnace", "ore-batch", 3).ok and player.backpack.is_empty(), "Server reserves chosen batch without awarding output")
	var session: SmithingSession = region.activities.smithing.sessions[player.entity_id]
	check(start("smelt_bronze", "furnace", "ore-batch", 3).ok and region.activities.smithing.sessions[player.entity_id] == session, "Replayed start resumes the same reservation")
	var encounter := int(region.activities.snapshot(player.entity_id).encounter_id)
	command({"type":"smith_bellows", "encounter_id":encounter, "input_id":1, "bellows":1})
	region.advance(0.2)
	check(session.temperature > 0, "Server bellows input increases temperature")
	var before := session.temperature
	region.frozen[player.entity_id] = true
	region.advance(1.0)
	check(session.temperature == before and session.progress == 0, "Persistence freeze pauses heat/progress")
	region.frozen.erase(player.entity_id)
	region.advance(0.1)
	check(session.temperature < before, "A held input expires during persistence freeze")
	session.config.cooling_per_second = 0.0
	session.temperature = 0.6
	for index in range(12): region.advance(1.0)
	check(session.state == SmithingSession.State.FINISHED and player.backpack == {"Bronze Ingot":3}, "Only server clock and correct heat award the batch")
	var earned := player.get_skill_experience("smithing")
	region.advance(1.0)
	check(player.backpack == {"Bronze Ingot":3} and player.get_skill_experience("smithing") == earned, "Server completion cannot replay item or XP rewards")
	check(start("bronze_longsword", "anvil", "sword").ok and player.backpack.is_empty(), "Server forging reserves exact recipe cost")
	session = region.activities.smithing.sessions[player.entity_id]
	encounter = int(region.activities.snapshot(player.entity_id).encounter_id)
	check(not command({"type":"smith_strike", "encounter_id":encounter-1, "target_index":0, "action_id":1, "x":0.5, "y":0.5, "aspect":2.5}).ok and session.hits == 0, "Old encounter cannot strike new work")
	var action := 1
	var strike := {"type":"smith_strike", "encounter_id":encounter, "target_index":session.target_serial, "action_id":action, "x":-1, "y":-1, "aspect":2.5}
	command(strike)
	check(session.hits == 0 and player.backpack.is_empty(), "Incorrect hammering never destroys or produces materials")
	while session.state == SmithingSession.State.FORGING:
		action += 1
		var point := session.target_position()
		strike = {"type":"smith_strike", "encounter_id":encounter, "target_index":session.target_serial, "action_id":action, "x":point.x, "y":point.y, "aspect":2.5}
		command(strike)
		var hits := session.hits
		command(strike)
		check(session.hits == hits, "Repeated network strike only counts once")
	check(session.state == SmithingSession.State.QUENCHING and player.backpack.is_empty(), "Last hammer target begins quench rather than awarding immediately")
	region.frozen[player.entity_id] = true
	region.advance(1.0)
	check(session.quench_elapsed == 0, "Frozen quench cannot skip the animation clock")
	region.frozen.erase(player.entity_id)
	for index in range(4): region.advance(1.0)
	check(player.backpack == {"Bronze Longsword":1} and player.get_skill_experience("smithing") == earned + 3 * SmithingRules.xp_per_bar(1), "Quench grants one finished object and per-ingot XP")
	_persistence(geometry)
	await _remote(geometry)
	_travel_pending(geometry)
	region.remove_player(player.entity_id)
	geometry.queue_free()
	print("[Smithing authority] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _persistence(geometry: Node) -> void:
	var codec := preload("res://network/character_codec.gd")
	var station: CraftingStation = geometry.get_node("furnace")
	var p := PlayerState.new()
	var old := codec.encode(p, "smithing")
	old.version = 4
	old.skill_experience.erase("smithing")
	check(codec.decode(old, "old", "old").ok and codec.decode(old, "old", "old").player.get_skill_level("smithing") == 1, "Version 4 saves migrate missing Smithing without losing other skills")
	old.version = 5
	check(not codec.decode(old, "old", "old").ok, "Current-version missing Smithing XP remains corruption")
	p.add_item("Bronze Ore", 2)
	var session := SmithingSession.new(p, station)
	check(session.start("smelt_bronze", 2).is_empty(), "Durable furnace fixture starts")
	var reserved := codec.encode(p, "smithing")
	var recovered: Dictionary = codec.decode(reserved, "recovered", "restored")
	check(recovered.ok and recovered.player.backpack == {"Bronze Ore":2}, "Unfinished reservation restores its ingredients after a real reload")
	var twice: Dictionary = codec.decode(codec.encode(recovered.player, "smithing"), "recovered", "restored")
	check(twice.ok and twice.player.backpack == {"Bronze Ore":2}, "Recovery followed by another save/load cannot duplicate the refund")
	session.temperature = 1.0
	session.overheated_seconds = 1.9
	var hot := codec.encode(p, "smithing")
	recovered = codec.decode(hot, "recovered", "restored")
	check(recovered.ok and recovered.player.backpack.is_empty(), "Doomed hot reservation burns on recovery instead of resetting grace")
	session.temperature = 0.6
	session.cancel()
	station = geometry.get_node("anvil")
	p.backpack = {"Bronze Ingot":3}
	session = SmithingSession.new(p, station)
	session.start("bronze_longsword")
	while session.state == SmithingSession.State.FORGING: session.strike(session.target_position())
	var quench := codec.encode(p, "smithing")
	var projected: Dictionary = codec.decode_public(codec.public_state(quench), "client", "client")
	check(projected.ok and projected.player.backpack.is_empty(), "Live save projection never grants a pending item early")
	recovered = codec.decode(quench, "recovered", "restored")
	check(recovered.ok and recovered.player.backpack == {"Bronze Longsword":1}, "Real reload preserves a hammer-completed workpiece")
	twice = codec.decode(codec.encode(recovered.player, "smithing"), "recovered", "restored")
	check(twice.ok and twice.player.backpack == recovered.player.backpack and twice.player.skill_experience == recovered.player.skill_experience, "Recovered finished reward and XP settle exactly once")
	quench.inventory = [{"item_id":int(GameData.get_item_by_name("Bronze Longsword").id), "count":2147483647}]
	recovered = codec.decode(quench, "full", "full")
	check(recovered.ok and not recovered.player.pending_smithing_record.is_empty(), "Full output stack retains a durable claim")
	recovered.player.backpack.clear()
	check(preload("res://scripts/smithing_settlement.gd").retry(recovered.player) and recovered.player.backpack == {"Bronze Longsword":1}, "Durable claim can be collected once space exists")
	region.activities.close(player.entity_id, true)
	player.backpack = {"Bronze Ore":1}
	start("smelt_bronze", "furnace", "depart-hot")
	var active: SmithingSession = region.activities.smithing.sessions[player.entity_id]
	active.temperature = 1.0
	region.frozen[player.entity_id] = true
	region.activities.close(player.entity_id, true)
	region.activities.close(player.entity_id, true)
	check(active.state == SmithingSession.State.FAILED and player.backpack.is_empty(), "Frozen departure and repeated close preserve burn liability")
	region.frozen.erase(player.entity_id)

func _remote(geometry: Node) -> void:
	region.activities.close(player.entity_id, true)
	player.backpack = {"Bronze Ingot":3}
	var client := PlayerState.new()
	var transport := Transport.new()
	transport.authority = region
	transport.owner_id = player.entity_id
	add_child(transport)
	var remote: RefCounted = load("res://network/remote_smithing_session.gd").new(client, geometry.get_node("anvil"), transport)
	check(remote.start("bronze_longsword").is_empty(), "Remote interface sends a start intent")
	remote.advance(0.0)
	check(remote.state == SmithingSession.State.FORGING and player.backpack.is_empty() and client.backpack.is_empty(), "Remote view uses the authoritative reserved workpiece")
	while remote.state == SmithingSession.State.FORGING:
		remote.strike(remote.target_position(), 2.5)
		remote.advance(0.0)
	check(remote.state == SmithingSession.State.QUENCHING and client.backpack.is_empty(), "Network hammer clicks open the same quench view without client rewards")
	remote.advance(1000.0)
	check(remote.state == SmithingSession.State.QUENCHING and player.backpack.is_empty() and client.backpack.is_empty(), "Client clock cannot finish or award quenching")
	for index in range(4): region.advance(1.0)
	transport.latest_snapshot = region.snapshot(player.entity_id)
	remote.advance(0.0)
	check(remote.state == SmithingSession.State.FINISHED and player.backpack == {"Bronze Longsword":1} and client.backpack.is_empty(), "Only authoritative completion confirms the finished item")
	await get_tree().process_frame
	var denied: RefCounted = load("res://network/remote_smithing_session.gd").new(client, geometry.get_node("anvil"), transport)
	denied.start("bronze_longsword")
	await get_tree().process_frame
	check(denied.state == SmithingSession.State.FAILED and not denied.is_active(), "Rejected remote starts unlock the Back button rather than trapping the UI")
	player.backpack = {"Bronze Ore":1}
	var cancelled: RefCounted = load("res://network/remote_smithing_session.gd").new(client, geometry.get_node("furnace"), transport)
	cancelled.start("smelt_bronze")
	cancelled.advance(0.0)
	region.frozen[player.entity_id] = true
	cancelled.cancel()
	check(player.backpack.is_empty(), "A persistence freeze rejects immediate cancellation without refunding early")
	region.frozen.erase(player.entity_id)
	cancelled.advance(0.4)
	cancelled.advance(0.0)
	check(cancelled.state == SmithingSession.State.CANCELLED and player.backpack == {"Bronze Ore":1}, "Retained cancel intent retries after thaw and returns safe ingredients once")
	await get_tree().process_frame
	await _host_freeze_intents(geometry, client, transport)
	player.backpack.clear()
	transport.hold_results = true
	var delayed: RefCounted = load("res://network/remote_smithing_session.gd").new(client, geometry.get_node("anvil"), transport)
	delayed.start("bronze_longsword")
	delayed.advance(0.6)
	delayed.advance(0.6)
	check(transport.held_results.size() >= 3, "Slow rejected start has several same-token attempts awaiting results")
	var first: Array = transport.held_results.pop_front()
	transport.action_result.emit(int(first[0]), first[1])
	check(delayed.state == SmithingSession.State.FAILED and not delayed.is_active(), "A definitive delayed rejection from an earlier attempt ends waiting")
	for entry: Array in transport.held_results: transport.action_result.emit(int(entry[0]), entry[1])
	transport.held_results.clear()
	transport.queue_free()

func _host_freeze_intents(geometry: Node, client: PlayerState, transport: Transport) -> void:
	region.activities.close(player.entity_id, true)
	player.backpack = {"Bronze Ore":1}
	var host := GateHost.new()
	add_child(host)
	host.regions["smithing"] = region
	var owner := {"closing":false, "ownership_paused":true, "pending":{}, "saving":false, "last_sequence":-1, "queue":[], "busy":false, "region_id":"smithing", "character_id":player.entity_id}
	host.sessions[99] = owner
	transport.gate = host
	var remote: RefCounted = load("res://network/remote_smithing_session.gd").new(client, geometry.get_node("furnace"), transport)
	remote.start("smelt_bronze")
	remote.advance(0.1)
	check(remote.is_active() and player.backpack == {"Bronze Ore":1}, "Actual ownership-freeze gate silently drops an unconfirmed start")
	owner.ownership_paused = false
	remote.advance(0.6)
	remote.advance(0.0)
	check(remote.state == SmithingSession.State.SMELTING and player.backpack.is_empty(), "Same-token start retries after the real host gate opens")
	owner.pending = {"operation_id":"ambiguous-save"}
	remote.cancel()
	check(player.backpack.is_empty(), "Actual unresolved-save gate drops cancellation without early refund")
	owner.pending = {}
	remote.advance(0.4)
	remote.advance(0.0)
	check(remote.state == SmithingSession.State.CANCELLED and player.backpack == {"Bronze Ore":1}, "Cancel retry survives the real host persistence gate")
	await get_tree().process_frame
	transport.gate = null
	host.queue_free()

func _travel_pending(geometry: Node) -> void:
	for earned: bool in [false, true]:
		region.activities.close(player.entity_id, true)
		player.backpack = {"Bronze Ingot":3}
		check(start("bronze_longsword", "anvil", "travel-pending-" + str(earned)).ok, "Pending travel fixture starts")
		var work: SmithingSession = region.activities.smithing.sessions[player.entity_id]
		if earned:
			while work.state == SmithingSession.State.FORGING: work.strike(work.target_position())
		var name_key := "Bronze Longsword" if earned else "Bronze Ingot"
		player.backpack[name_key] = 2147483647
		region.remove_player(player.entity_id)
		check(player.pending_smithing_session == work, "Full stack retains the work across region removal")
		var destination := AuthoritativeRegion.new()
		destination.configure("destination", geometry)
		destination.add_player(player.entity_id, player)
		player.backpack.clear()
		destination.advance(0.1)
		var expected := {name_key:1 if earned else 3}
		check(player.backpack == expected and player.pending_smithing_session == null and player.active_smithing_session == null, "New region retries blocked output/refund after space becomes available")
		destination.advance(0.1)
		check(player.backpack == expected, "New region cannot repeat a recovered settlement")
		destination.remove_player(player.entity_id)
		region.add_player(player.entity_id, player)
