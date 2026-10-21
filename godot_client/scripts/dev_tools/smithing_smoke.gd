extends Node
## Real recipe, heat, hammer, inventory and XP regression coverage.
var checks := 0
var failures := 0
var session_script: Script
var rules: Script
var station: Node2D

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Smithing FAIL] " + label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	check(ResourceLoader.exists("res://scripts/smithing_session.gd"), "Smithing minigame session exists")
	if failures > 0:
		_finish()
		return
	session_script = load("res://scripts/smithing_session.gd")
	rules = load("res://scripts/smithing_rules.gd")
	station = load("res://scripts/crafting_station.gd").new()
	station.setup("furnace", "Test furnace", Vector2(10, 10))
	add_child(station)
	_heat_and_batches()
	_all_tiers()
	_burning_and_mastery()
	_forging()
	_guards()
	_edge_cases()
	_lifecycle()
	_pacing()
	_finish()

func _finish() -> void:
	print("[Smithing] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func make_session(player: PlayerState, options: Dictionary = {}) -> RefCounted:
	return session_script.new(player, station, null, options)

func _heat_and_batches() -> void:
	var widths := [0.30, 0.30, 0.25, 0.22, 0.20, 0.18, 0.16]
	var levels := [1, 10, 20, 30, 40, 50, 60]
	for tier in range(1, 8):
		var heat: Dictionary = rules.heat_profile(tier, levels[tier - 1])
		check(is_equal_approx(heat.high - heat.low, widths[tier - 1]), "Heat width covers gauge fraction for tier %d" % tier)
		var practiced: Dictionary = rules.heat_profile(tier, levels[tier - 1] + 15)
		check(practiced.high - practiced.low > widths[tier - 1] and practiced.grace > heat.grace, "Proficiency widens range and grace tier %d" % tier)
		check(rules.required_level(tier) == levels[tier - 1], "Tier unlock matches equipment tier %d" % tier)
	var last_duration := 0.0
	for batch in range(1, 11):
		var player := PlayerState.new()
		player.add_item("Bronze Ore", 10)
		var session := make_session(player, {"cooling_per_second": 0.0})
		check(session.start("smelt_bronze", batch).is_empty(), "Batch starts: %d" % batch)
		check(player.backpack.get("Bronze Ore", 0) == 10 - batch, "Whole batch reserved exactly once")
		check(session.duration > last_duration, "Each extra bar increases duration")
		last_duration = session.duration
		session.temperature = 0.0
		session.advance(1.0)
		check(session.progress == 0.0, "Cold furnace pauses progress")
		session.temperature = 0.6
		session.advance(session.duration)
		check(session.state == session_script.State.FINISHED and player.backpack.get("Bronze Ingot", 0) == batch, "Correct heat completes exact batch")
		var xp := player.get_skill_experience("smithing")
		check(xp == batch * rules.xp_per_bar(1), "XP is awarded per successful bar")
		session.advance(1000.0)
		session.cancel()
		check(player.backpack.get("Bronze Ingot", 0) == batch and player.get_skill_experience("smithing") == xp, "No repeated rewards or refunds after completion")
	var player := PlayerState.new()
	player.add_item("Bronze Ore", 10)
	for invalid in [-1, 0, 11]:
		check(not make_session(player).start("smelt_bronze", invalid).is_empty() and player.backpack == {"Bronze Ore": 10}, "Invalid batch rejected atomically")
	var bellows := make_session(player)
	check(bellows.start("smelt_bronze", 1).is_empty(), "Bellows session starts")
	bellows.advance(0.5, true)
	var raised: float = bellows.temperature
	bellows.advance(0.5, false)
	check(raised > 0.0 and bellows.temperature < raised, "Bellows raises heat, released bellows cools")
	bellows.cancel()
	check(player.backpack == {"Bronze Ore": 10}, "Cancellation refunds reserved unprocessed ore once")
	bellows.cancel()
	check(player.backpack == {"Bronze Ore": 10}, "Repeated cancellation cannot duplicate ore")

func _burning_and_mastery() -> void:
	for extra in [0, 29, 30, 31]:
		var player := PlayerState.new()
		player.set_skill_level("smithing", 1 + extra)
		player.add_item("Bronze Ore", 10)
		var session := make_session(player, {"cooling_per_second": 0.0})
		check(session.start("smelt_bronze", 10).is_empty(), "Overheat session starts")
		session.temperature = 1.0
		session.advance(0.1)
		check(session.progress == 0.0, "Overheating always pauses")
		if extra < 30:
			check(not session.cancel(), "Hot batch cannot escape burn timer by cancelling")
			session.advance(20.0)
			check(session.state == session_script.State.FAILED and player.backpack.is_empty() and player.get_skill_experience("smithing") == SkillProgression.experience_for_level(extra + 1), "Overheat destroys entire reserved batch without rewards at +%d" % extra)
		else:
			session.advance(200.0)
			check(session.state == session_script.State.SMELTING and player.backpack.is_empty(), "+30 or more never burns or finishes while hot")
			session.temperature = 0.6
			session.advance(session.duration)
			check(player.backpack.get("Bronze Ingot", 0) == 10, "Master must return to valid heat to finish")
	var player := PlayerState.new()
	player.add_item("Bronze Ore")
	var recovering := make_session(player, {"cooling_per_second": 0.0})
	recovering.start("smelt_bronze")
	recovering.temperature = 1.0
	recovering.advance(0.3)
	recovering.temperature = 0.6
	recovering.advance(0.1)
	check(recovering.overheated_seconds == 0.0, "Returning to heat range resets consecutive overheating")
	recovering.cancel()

func _all_tiers() -> void:
	for entry: Array in [["bronze", "Bronze", 1], ["iron", "Iron", 10], ["steel", "Steel", 20], ["blacksteel", "Blacksteel", 30], ["mithril", "Mithril", 40], ["adamantite", "Adamantite", 50], ["starforged", "Starforged", 60]]:
		var player := PlayerState.new()
		player.set_skill_level("smithing", int(entry[2]))
		player.add_item(String(entry[1]) + " Ore")
		var session := make_session(player, {"cooling_per_second": 0.0})
		check(session.start("smelt_" + String(entry[0])).is_empty(), "Existing ore tier starts at approved unlock: " + entry[1])
		session.temperature = 0.6
		session.advance(10.0)
		check(player.backpack == {String(entry[1]) + " Ingot": 1}, "One ore yields exactly one ingot: " + entry[1])

func _forging() -> void:
	station.station_id = "anvil"
	var player := PlayerState.new()
	player.add_item("Bronze Ingot", 3)
	var forge := make_session(player)
	check(forge.start("bronze_longsword").is_empty() and player.backpack.is_empty(), "Forging reserves exact existing three-bar cost")
	var starting_stage: int = forge.shape_stage()
	check(not forge.strike(Vector2(-1, -1)) and forge.hits == 0, "Wrong hammer strike makes no progress")
	forge.advance(5.0)
	check(forge.hits == 0 and forge.state == session_script.State.FORGING, "Missing a target never destroys material or progresses")
	var guard := 0
	while forge.state == session_script.State.FORGING and guard < 100:
		check(forge.strike(forge.target_position()), "Guided target advances hammering")
		guard += 1
	check(forge.shape_stage() > starting_stage and forge.state == session_script.State.QUENCHING, "Hammering passes shaping stages into quenching")
	check(not player.backpack.has("Bronze Longsword"), "Hammer completion does not award before quench")
	check(not forge.strike(forge.target_position()), "Quench rejects extra strikes")
	forge.advance(1.0)
	check(not player.backpack.has("Bronze Longsword"), "Lowering animation precedes item reward")
	forge.advance(10.0)
	check(forge.state == session_script.State.FINISHED and player.backpack == {"Bronze Longsword": 1}, "Quench awards finished item exactly once")
	check(player.get_skill_experience("smithing") == 3 * rules.xp_per_bar(1), "Forging XP scales with bars consumed")
	forge.advance(100.0)
	forge.cancel()
	check(player.backpack == {"Bronze Longsword": 1}, "Quench cannot be replayed for rewards")
	var patterns: Array = []
	for item_name: String in ["Bronze Longsword", "Bronze Axe", "Bronze Helmet", "Bronze Platebody"]:
		var pattern: Array = rules.pattern_for(item_name)
		check(not pattern.is_empty(), "Equipment category has meaningful targets: " + item_name)
		check(not patterns.has(pattern), "Category uses a distinct pattern: " + item_name)
		patterns.append(pattern)
	station.station_id = "furnace"

func _guards() -> void:
	var player := PlayerState.new()
	player.add_item("Iron Ore", 10)
	check(not make_session(player).start("smelt_iron").is_empty() and player.backpack == {"Iron Ore": 10}, "Tier level requirement enforced before spending ore")
	player.set_skill_level("smithing", 10)
	var session := make_session(player)
	check(session.start("smelt_iron").is_empty(), "Tier unlock permits correct ore")
	check(not make_session(player).start("smelt_iron").is_empty(), "Concurrent sessions rejected")
	check(not CraftingService.craft(player, "smelt_iron", "furnace").ok, "Immediate crafting cannot bypass smelting")
	session.cancel()
	station.station_id = "anvil"
	player.add_item("Bronze Ingot", 3)
	check(not CraftingService.craft(player, "bronze_longsword", "anvil").ok, "Immediate crafting cannot bypass hammering or quench")
	var pending := make_session(player)
	check(not pending.start("bronze_helmet").is_empty(), "Pending equipment costs remain disabled")
	var missing := make_session(player)
	check(not missing.start("bronze_longsword", 2).is_empty(), "One workpiece per forging session")
	var forge := make_session(player)
	forge.start("bronze_longsword")
	player.in_combat = true
	forge.advance(0.1)
	check(forge.state == session_script.State.CANCELLED and player.backpack.get("Bronze Ingot", 0) == 3, "Interrupted forging refunds bars without duplication")
	forge.cancel()
	check(player.backpack.get("Bronze Ingot", 0) == 3, "Repeated interrupted close cannot repeat refund")
	station.station_id = "furnace"

func _edge_cases() -> void:
	var player := PlayerState.new()
	check(player.get_skill_level("smithing") == 1 and player.get_skill_progress("smithing").name == "Smithing", "Smithing uses the existing player skill registry")
	var combat_level := player.get_combat_level()
	player.set_skill_level("smithing", 100)
	check(player.get_combat_level() == combat_level, "Smithing does not affect combat level")
	player.add_item("Bronze Ore", 2)
	var session := make_session(player, {"cooling_per_second": 0.0})
	session.start("smelt_bronze", 2)
	player.backpack["Bronze Ingot"] = 9223372036854775807
	session.temperature = 0.6
	session.advance(20.0)
	check(player.backpack["Bronze Ingot"] == 9223372036854775807 and session.reward_xp == 0, "Overflow preserves reserved reward without wrapping or XP")
	session.temperature = 1.0
	session.advance(20.0)
	player.backpack.erase("Bronze Ingot")
	session.advance(0.1)
	check(player.backpack.get("Bronze Ingot", 0) == 2 and session.state == session_script.State.FINISHED, "Completed smelt waits safely for output space, even if heat changes")
	var underleveled := PlayerState.new()
	underleveled.add_item("Bronze Ore")
	var raw: Dictionary = GameData.items_by_name["Bronze Ingot"]
	GameData.items_by_name.erase("Bronze Ingot")
	check(not make_session(underleveled).start("smelt_bronze").is_empty() and underleveled.backpack == {"Bronze Ore": 1}, "Missing output cannot consume ore")
	GameData.items_by_name["Bronze Ingot"] = raw
	var cooling := make_session(underleveled)
	cooling.start("smelt_bronze")
	cooling.temperature = 1.0
	cooling.advance(NAN)
	cooling.advance(-1.0)
	check(cooling.overheated_seconds == 0.0, "Invalid delta cannot advance or reverse state")
	cooling.advance(0.5)
	check(cooling.overheated_seconds > 0.0, "A real hot half-second counts toward grace")
	cooling.temperature = 0.6
	cooling.cancel()
	station.station_id = "anvil"
	var forger := PlayerState.new()
	forger.add_item("Bronze Ingot")
	var forging := make_session(forger)
	forging.start("bronze_dagger")
	var target: Vector2 = forging.target_position()
	check(not forging.strike(target + Vector2(0.05, 0), 3.0), "Wide workpiece hit test uses the visible circular target radius")
	forging.cancel()
	station.station_id = "furnace"

func _pacing() -> void:
	# Independent progression simulation using real batches/rewards, not the
	# calibrator's interval integral. Each batch takes 30 reference seconds.
	var experience := 0
	var seconds := 0.0
	var highest_tier := 1
	while experience < SkillProgression.MAX_EXPERIENCE:
		var level := SkillProgression.level_for_experience(experience)
		for tier in range(1, 8):
			if level >= rules.required_level(tier): highest_tier = tier
		experience += rules.xp_per_bar(highest_tier) * 10
		seconds += 30.0
	check(absf(seconds / 3600.0 - 60.0) < 0.5, "Reference active smelting reaches level 100 in approximately sixty hours")
	print("[Smithing pacing] %.2f reference hours; tier XP/bar: %s" % [seconds / 3600.0, str([rules.xp_per_bar(1), rules.xp_per_bar(2), rules.xp_per_bar(3), rules.xp_per_bar(4), rules.xp_per_bar(5), rules.xp_per_bar(6), rules.xp_per_bar(7)])])

func _lifecycle() -> void:
	var player := PlayerState.new()
	player.add_item("Bronze Ore")
	var hot := make_session(player)
	hot.start("smelt_bronze")
	hot.temperature = 0.76
	check(not hot.cancel(), "Recoverable hot cancellation waits for cooling")
	hot.advance(0.5)
	check(hot.state == session_script.State.CANCELLED and hot.progress == 0.0 and player.backpack == {"Bronze Ore": 1} and player.active_smithing_session == null, "Closing a recoverable hot batch cools then refunds without hidden progress")
	check("pending_smithing_session" in player, "Player retains unsettled Smithing across scene travel")
	if not "pending_smithing_session" in player:
		return
	var output := make_session(player, {"cooling_per_second": 0.0})
	output.start("smelt_bronze")
	player.backpack["Bronze Ingot"] = 9223372036854775807
	output.temperature = 0.6
	output.advance(10.0)
	output.retain_for_later()
	var pending: WeakRef = weakref(output)
	output = null
	check(pending.get_ref() != null and player.pending_smithing_session == pending.get_ref(), "Pending output survives loss of old UI ownership")
	player.backpack.erase("Bronze Ingot")
	player.pending_smithing_session.advance(0.1)
	check(player.backpack == {"Bronze Ingot": 1} and player.pending_smithing_session == null, "Recreated UI can settle pending output once")
	station.station_id = "anvil"
	var refund := make_session(player)
	refund.start("bronze_dagger")
	player.backpack["Bronze Ingot"] = 9223372036854775807
	check(not refund.cancel(), "Blocked input refund is preserved")
	refund.retain_for_later()
	var refund_ref: WeakRef = weakref(refund)
	refund = null
	check(refund_ref.get_ref() != null, "Blocked refund survives old UI release")
	player.backpack.erase("Bronze Ingot")
	player.pending_smithing_session.advance(0.1)
	check(player.backpack == {"Bronze Ingot": 1} and player.pending_smithing_session == null, "Blocked refund automatically retries without reward XP")
	station.station_id = "furnace"
