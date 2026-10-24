extends Node

var checks := 0
var failures := 0
var service: RefCounted
var defs: MiningDefinitions
var players := {}
var eligible := true
var in_range := true
var paused := false
var events: Array[Dictionary] = []

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("[Mining service FAIL] ", label)

func _ready() -> void:
	if not ResourceLoader.exists("res://scripts/mining_service.gd"):
		check(false, "Shared extraction service exists")
	else:
		_run()
	print("[Mining service] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func setup(probability: float = 1.0) -> void:
	defs = preload("res://scripts/dev_tools/mining_tool_fixture.gd").new()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mining.json"))
	data.ores[0].success.p_at_unlock = probability
	data.ores[0].success.p_at_mastery = probability
	defs.load_records(data)
	players = {"a": PlayerState.new("Miner A"), "b": PlayerState.new("Miner B")}
	eligible = true
	in_range = true
	paused = false
	events.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 123
	service = load("res://scripts/mining_service.gd").new()
	service.configure(defs, context, reward, rng)
	service.register_deposit("bronze", 235)

func context(id: String, _deposit: String) -> Dictionary:
	return {"player": players.get(id), "eligible": eligible, "in_range": in_range, "paused": paused}

func reward(id: String, event: Dictionary) -> void:
	check(not service.active("a") and not service.active("b"), "Competing sessions close before callback")
	check(service.deposit_snapshots()[0].state == "depleted", "Claim precedes callback")
	events.append(event)
	check(players[id].backpack.get("Bronze Ore", 0) > 0, "Inventory grant precedes notification")

func advance(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.000001:
		var step := minf(0.1, remaining)
		service.advance(step)
		remaining -= step

func begin(id: String = "a") -> Dictionary:
	return service.start(id, "bronze", 0)

func _run() -> void:
	setup()
	check(begin().ok, "Valid extraction starts")
	advance(2.9)
	check(players.a.backpack.is_empty() and players.a.get_skill_experience("mining") == 0, "Full interval before first roll")
	check(begin().ok, "Repeated target accepted")
	advance(0.1)
	check(players.a.backpack.get("Bronze Ore", 0) == 1 and players.a.get_skill_experience("mining") == 121, "One Bronze ore and configured XP")
	check(events.size() == 1 and events[0].experience_gained == 121, "One post-grant event with actual XP")
	check(not service.active("a") and service.deposit_snapshots()[0].generation == 1, "Success depletes and cancels")
	check(not begin().ok, "Replayed generation cannot reward")
	advance(3.9)
	check(service.deposit_snapshots()[0].state == "depleted", "Respawn waits full duration")
	advance(0.1)
	check(service.deposit_snapshots()[0].state == "available" and service.deposit_snapshots()[0].generation == 2, "Respawn advances generation")
	check(not begin().ok and service.start("a", "bronze", 2).ok, "Only fresh generation restarts")
	check(not service.register_deposit("bronze", 235).ok, "Duplicate deposit rejected")

	setup(0.000001)
	begin()
	advance(6.0)
	check(service.active("a") and players.a.backpack.is_empty() and events.is_empty(), "Misses repeat without rewards")
	check(service.snapshot("a").attempt_sequence == 2, "Repeated attempts use complete intervals")
	setup()
	begin("a")
	begin("b")
	advance(3.0)
	check(int(players.a.backpack.get("Bronze Ore", 0)) + int(players.b.backpack.get("Bronze Ore", 0)) == 1, "Two simultaneous miners get one total ore")
	check(players.a.get_skill_experience("mining") + players.b.get_skill_experience("mining") == 121 and events.size() == 1, "One total XP award per generation")

	for interruption: String in ["range", "eligibility", "death", "movement", "tool", "equipment", "full", "missing"]:
		setup()
		begin()
		match interruption:
			"range": in_range = false
			"eligibility": eligible = false
			"death": players.a.current_hp = 0
			"movement": players.a.x += 0.2
			"tool": defs.owned = false
			"equipment": players.a.equipment.weapon = GameData.get_item_by_name("Bronze Dagger")
			"full": players.a.backpack["Bronze Ore"] = CharacterCodec.MAX_COUNT
			"missing": players.erase("a")
		advance(0.1)
		check(not service.active("a") and events.is_empty() and service.deposit_snapshots()[0].state == "available", "Interrupt without reward/depletion: " + interruption)
	setup()
	players.a.backpack["Bronze Ore"] = CharacterCodec.MAX_COUNT
	check(not begin().ok, "Full stack rejected before start")
	setup()
	defs.tool_level = 18
	check(not begin().ok, "Pickaxe level requirement enforced")
	setup()
	defs.owned = false
	check(not begin().ok, "Missing pickaxe rejected")
	setup()
	defs._ores[235].required_level = 12
	check(not begin().ok, "Ore requirement independent of tool")
	setup()
	begin()
	advance(2.9)
	paused = true
	var p: PlayerState = players.a
	players.erase("a")
	advance(10)
	check(service.active("a") and events.is_empty(), "Freeze takes precedence over missing actor")
	players.a = p
	paused = false
	advance(0.1)
	advance(2.9)
	check(events.is_empty(), "Resume waits a new full interval")
	advance(0.1)
	check(events.size() == 1, "Resumed attempt completes once")
	setup()
	begin()
	service.advance(NAN)
	service.advance(0)
	service.advance(-1)
	service.advance(100)
	check(service.snapshot("a").attempt_sequence == 0 and events.is_empty(), "Invalid delta and stalls cannot accelerate")
	setup()
	defs.interval = 1.5
	begin()
	advance(1.5)
	check(events.size() == 1, "Better tool shortens interval")
	setup()
	players.a.set_skill_level("mining", 100)
	begin()
	advance(3)
	check(players.a.get_skill_experience("mining") == 19450000 and events[0].experience_gained == 0, "Cap preserves ore, reports actual zero XP")
