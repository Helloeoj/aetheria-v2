extends Node
## Compare current force tolerance with original fish forces using visible-motion
## feedback sampled every 200 ms. Both sides intentionally inherit the current
## corridor width and reel pace: this isolates force tuning rather than freezing
## an earlier release's complete difficulty. This is not a human playtest.

class PreviousBalanceSession extends FishingSession:
	func skill_pull_tolerance() -> float:
		return 1.0

const SEEDS := 100
const SAMPLE_FRAMES := 12
const STEP := 1.0 / 60.0
const FIRST_ACCESS_LEVELS := [1, 10, 25, 30, 45, 50, 65, 70, 85, 90]
const FIRST_ACCESS_RODS := [0, 0, 1, 1, 2, 2, 3, 3, 4, 4]
var checks := 0
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("[Fishing difficulty FAIL] ", description)

func trial(fish_index: int, seed_value: int, previous_balance: bool, digital: bool = false) -> Dictionary:
	var player := PlayerState.new()
	player.set_skill_level("fishing", FIRST_ACCESS_LEVELS[fish_index])
	var session: FishingSession = PreviousBalanceSession.new(player) if previous_balance else FishingSession.new(player)
	session.rod = FishingSession.RODS[FIRST_ACCESS_RODS[fish_index]]
	session.fish = GameData.get_item_by_name(FishingSession.raw_fish_names()[fish_index]).duplicate(true)
	if previous_balance:
		# Only the previous raw force and lack of level tolerance differ. Rod,
		# skill width, distance, reel speed, RNG seed and controller stay equal.
		session.fish["fish_strength"] = float(session.fish.fish_strength) / 0.85
	session.distance = float(session.fish.minimum_catch_distance)
	session.remaining = session.distance
	session.state = FishingSession.State.FIGHT
	session.rng.seed = seed_value
	var held_input := 0.0
	var previous_observed_position := 0.0
	var highest_strain := 0.0
	var outside_seconds := 0.0
	for frame in range(3600):
		if session.state != FishingSession.State.FIGHT:
			break
		if frame % SAMPLE_FRAMES == 0:
			# Estimate velocity from the bobber positions a player can see.
			# Do not read fish_pull or the hidden dart timing to counter them.
			var observed_velocity := (session.lateral - previous_observed_position) / (float(SAMPLE_FRAMES) * STEP)
			previous_observed_position = session.lateral
			if digital:
				# A novice A/D controller corrects position without anticipating
				# velocity, making overshoot visible in this separate comparison.
				held_input = 0.0 if absf(session.lateral) < 0.06 else -signf(session.lateral)
			else:
				held_input = clampf((-session.lateral * 3.0 - observed_velocity * 0.7) / session.input_strength(), -1.0, 1.0)
		session.advance(STEP, held_input)
		highest_strain = maxf(highest_strain, session.strain)
		if absf(session.lateral) > session.boundary():
			outside_seconds += STEP
	return {"caught": session.state == FishingSession.State.CAUGHT, "strain": highest_strain, "outside_seconds": outside_seconds}

func sample(fish_index: int, previous_balance: bool, digital: bool = false) -> Dictionary:
	var caught := 0
	var strain := 0.0
	var outside_seconds := 0.0
	for seed_value in range(SEEDS):
		var result := trial(fish_index, seed_value, previous_balance, digital)
		caught += int(result.caught)
		strain += float(result.strain)
		outside_seconds += float(result.outside_seconds)
	return {"caught": caught, "strain": strain / SEEDS, "outside_seconds": outside_seconds / SEEDS}

func _run() -> void:
	var previous_caught := 0
	var current_caught := 0
	var previous_strain := 0.0
	var current_strain := 0.0
	for fish_index in range(FishingSession.raw_fish_names().size()):
		var before := sample(fish_index, true)
		var after := sample(fish_index, false)
		previous_caught += int(before.caught)
		current_caught += int(after.caught)
		previous_strain += float(before.strain)
		current_strain += float(after.strain)
		var fish_name: String = FishingSession.raw_fish_names()[fish_index]
		print("[Fishing difficulty] %s at Fishing %d: previous %d/%d, current %d/%d; mean peak strain %.3f -> %.3f; outside seconds %.3f -> %.3f" % [fish_name, FIRST_ACCESS_LEVELS[fish_index], int(before.caught), SEEDS, int(after.caught), SEEDS, float(before.strain), float(after.strain), float(before.outside_seconds), float(after.outside_seconds)])
		check(int(after.caught) >= int(before.caught), "Delayed visible-motion steering does not lower catch count: " + fish_name)
	check(current_caught > previous_caught, "Balance changes improve aggregate delayed-steering catch count")
	check(current_strain < previous_strain, "Balance changes reduce aggregate delayed-steering peak strain")
	var novice_before := sample(1, true, true)
	var novice_after := sample(1, false, true)
	print("[Fishing difficulty] Marlo digital 200 ms: previous %d/%d, current %d/%d; mean peak strain %.3f -> %.3f" % [int(novice_before.caught), SEEDS, int(novice_after.caught), SEEDS, float(novice_before.strain), float(novice_after.strain)])
	check(int(novice_after.caught) >= int(novice_before.caught), "Marlo digital steering does not regress")
	check(int(novice_after.caught) >= int(SEEDS * 0.9), "Marlo is consistently catchable with delayed digital steering")
	print("[Fishing difficulty] Total previous %d/%d, current %d/%d" % [previous_caught, SEEDS * FishingSession.raw_fish_names().size(), current_caught, SEEDS * FishingSession.raw_fish_names().size()])
	print("[Fishing difficulty] %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
