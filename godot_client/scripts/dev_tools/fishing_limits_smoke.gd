extends Node
## Every rod gets the same extra travel beyond its own visible red bars.
var checks := 0
var failures := 0

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Fishing limits FAIL] ", description)

func _ready() -> void:
	for rod: String in FishingSession.RODS:
		var rod_data := GameData.get_item_by_name(rod)
		for level: int in [int(rod_data.fishing_level), int(rod_data.cast_mastery_level), 100]:
			check_rod_limits(rod, level)
	var player := PlayerState.new()
	player.set_skill_level("fishing", 100)
	var session := FishingSession.new(player)
	var previous_limit := 0.0
	for rod: String in FishingSession.RODS:
		session.rod = rod
		session.state = FishingSession.State.FIGHT
		session.remaining = 200.0
		session.distance = 200.0
		session.lateral = 0.0
		session.velocity = 10.0
		session.fish_pull = 10.0
		session.dart_after = 100.0
		session.strain = 0.0
		session.advance(0.2)
		check(session.lateral > previous_limit, rod + " has a farther outer stop than the previous rod at the same level")
		previous_limit = session.lateral
	print("[Fishing limits] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func check_rod_limits(rod: String, level: int) -> void:
	for side: float in [-1.0, 1.0]:
		var player := PlayerState.new()
		player.set_skill_level("fishing", level)
		var session := FishingSession.new(player)
		session.rod = rod
		session.fish = GameData.get_item_by_name("Raw Sunfish").duplicate()
		session.state = FishingSession.State.FIGHT
		session.distance = 200.0
		session.remaining = 200.0
		# 0.24 lateral units = 68.4 lake pixels: the red-to-green guide gap.
		var expected_limit := session.boundary() + 0.24
		session.lateral = side * (expected_limit - 0.01)
		session.velocity = side * 3.0
		session.fish_pull = side * 3.0
		session.dart_after = 100.0
		session.advance(0.2, side)
		check(is_equal_approx(absf(session.lateral), expected_limit), rod + " stops at its own red bar plus the guide gap at level %d" % level)
		check(is_equal_approx((absf(session.lateral) - session.boundary()) * 285.0, 68.4), rod + " keeps the same screen-space gap beyond the red bars")
		var screen_x := 360.0 + session.lateral * 285.0
		check(screen_x > 12.0 and screen_x < 708.0, rod + " keeps the whole bobber inside the lake")
		check(absf(session.velocity) < 0.000001, rod + " discards outward momentum at the limit")
		check(session.strain > 0.0, rod + " still gains strain outside the red bars")
		# Correcting inward must work immediately, without first cancelling hidden momentum.
		session.fish_pull = 0.0
		var at_edge := absf(session.lateral)
		session.advance(1.0 / 60.0, -side)
		check(absf(session.lateral) < at_edge, rod + " can immediately steer back from the edge")
		# Ignoring the fish still loses it; the outer limit is not a safe zone.
		session.lateral = side * expected_limit
		session.fish_pull = side * 3.0
		session.advance(2.0, side)
		check(session.state == FishingSession.State.LOST and session.reward_xp == 0, rod + " still loses an ignored fish without rewards")
		check(absf(session.lateral) <= expected_limit + 0.000001, rod + " remains bounded after escape")
