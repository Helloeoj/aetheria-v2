extends Node
## Fixed corridor ratios, measured safe reeling times, and actual-distance eligibility.
var checks := 0
var failures: Array[String] = []
var capture_dir := ""


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_dir = argument.trim_prefix("--capture=")
	get_tree().create_timer(45.0).timeout.connect(func() -> void:
		printerr("[Fishing pacing FAIL] Test timed out")
		get_tree().quit(1))
	_run.call_deferred()


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("[Fishing pacing FAIL] ", description)


func prepared(rod: String = "Beginner Rod", feet: float = 15.0) -> FishingSession:
	var player := PlayerState.new()
	player.set_skill_level("fishing", 100)
	player.add_item(rod)
	player.add_item("High Grade Fish Food", 10)
	var session := FishingSession.new(player)
	session.rod = rod
	session.bait = "High Grade Fish Food"
	session.distance = feet
	session.remaining = feet
	return session


func check_corridor() -> void:
	var session := prepared()
	for rod: String in FishingSession.RODS:
		session.rod = rod
		var base := float(GameData.get_item_by_name(rod).fishing_width)
		for level: int in [1, 20, 40, 60, 80, 100]:
			session.player.set_skill_level("fishing", level)
			var previous := minf(0.78, base + float(level - 1) * 0.0015)
			check(is_equal_approx(session.boundary() / (previous * 0.8), 0.75), "%s level %d has a corridor another 25 percent narrower than the previous tuning" % [rod, level])
	# Exercise the original cap, which ordinary level-100 catalog rods do not reach.
	session.rod = "Demon Rod"
	session.player.set_skill_level("fishing", 100)
	var rod_data := GameData.get_item_by_name(session.rod)
	var original_width: float = rod_data.fishing_width
	rod_data.fishing_width = 0.9
	check(is_equal_approx(session.boundary(), 0.468), "The previous 0.624 boundary cap is also narrowed by another 25 percent")
	rod_data.fishing_width = original_width


func measured_reel_time(rod: String, feet: float) -> float:
	var session := prepared(rod, feet)
	session.fish = GameData.get_item_by_name("Raw Reedkip").duplicate()
	session.fish.fish_strength = 0.0
	session.dart_after = 1000.0
	session.state = FishingSession.State.FIGHT
	var seconds := 0.0
	for _frame in range(3600):
		if session.state != FishingSession.State.FIGHT:
			break
		session.advance(1.0 / 60.0)
		seconds += 1.0 / 60.0
	check(session.state == FishingSession.State.CAUGHT and session.player.fishing_pale_count() == 1, "%s %.0f ft reaches one catch through real safe-window reeling" % [rod, feet])
	check(session.strain == 0.0 and session.lateral == 0.0, "Timing measurement stays inside the corridor throughout")
	return seconds


func check_pacing() -> void:
	var session := prepared()
	var endpoint_travel := {10.0: 60.0, 15.0: 63.6842105263, 60.0: 96.8421052632, 200.0: 200.0}
	for rod: String in FishingSession.RODS:
		session.rod = rod
		var native_speed := float(GameData.get_item_by_name(rod).reel_speed)
		for feet: float in endpoint_travel:
			session.distance = feet
			session.remaining = feet
			var travel: float = endpoint_travel[feet]
			check(is_equal_approx(session.reel_travel_distance(), travel), "%s %.0f ft has the intended reel travel" % [rod, feet])
			var measured := measured_reel_time(rod, feet)
			check(absf(measured - travel / native_speed) <= 1.0 / 60.0 + 0.00001, "%s %.0f ft measured landing time matches the intended pacing" % [rod, feet])
			if feet < 200.0:
				check(measured > feet / native_speed + 0.05, "Short casts reel longer than their previous actual-distance duration")
				check(session.bobber_water_depth() > feet / 200.0, "Short casts place the bobber farther from the bottom of the lake")
			else:
				check(is_equal_approx(session.reel_speed(), native_speed) and absf(measured - 200.0 / native_speed) <= 1.0 / 60.0 + 0.00001, "A 200 ft cast retains its original reel speed and total duration")
		var previous_travel := -1.0
		var previous_time := -1.0
		var previous_depth := -1.0
		var monotonic_travel := true
		var monotonic_time := true
		var monotonic_depth := true
		var actual_distance_preserved := true
		for feet in range(10, 201):
			session.distance = float(feet)
			session.remaining = float(feet)
			var travel := session.reel_travel_distance()
			var seconds := session.distance / session.reel_speed()
			var depth := session.bobber_water_depth()
			monotonic_travel = monotonic_travel and travel > previous_travel
			monotonic_time = monotonic_time and seconds > previous_time
			monotonic_depth = monotonic_depth and depth > previous_depth and depth <= 1.0
			actual_distance_preserved = actual_distance_preserved and session.distance == float(feet) and session.remaining == float(feet)
			previous_travel = travel
			previous_time = seconds
			previous_depth = depth
		check(monotonic_travel and monotonic_time, rod + " reel travel and landing duration increase smoothly from 10 to 200 ft")
		check(monotonic_depth, rod + " visual cast reach increases smoothly from 10 to 200 ft")
		check(actual_distance_preserved, "Pacing and visual helpers never change the actual cast distance")
		session.distance = 200.0
		for progress: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
			session.remaining = 200.0 * progress
			check(is_equal_approx(session.bobber_water_depth(), session.remaining / 200.0), "A 200 ft cast retains its original bobber position at %.0f percent line remaining" % (progress * 100.0))
		session.remaining = 0.0
		check(is_zero_approx(session.bobber_water_depth()), "Every rod brings the bobber to the original near-shore endpoint")
		var cap := float(GameData.get_item_by_name(rod).cast_distance)
		if cap not in endpoint_travel:
			var cap_time := measured_reel_time(rod, cap)
			session.distance = cap
			check(absf(cap_time - session.reel_travel_distance() / native_speed) <= 1.0 / 60.0 + 0.00001, rod + " reachable maximum also uses the intended measured reel time")
		session.distance = 0.0
		session.remaining = 0.0
		check(is_zero_approx(session.reel_travel_distance()) and is_zero_approx(session.bobber_water_depth()) and is_equal_approx(session.reel_speed(), native_speed), "Ready sessions with no cast distance keep finite pacing and visual values")


func check_actual_distance_pool() -> void:
	var session := prepared()
	for bait: String in FishingSession.BAITS:
		session.bait = bait
		var grade := int(GameData.get_item_by_name(bait).tier)
		for feet: float in [10.0, 15.0, 59.99, 60.0, 89.99, 90.0, 139.99, 140.0, 200.0]:
			session.distance = feet
			session.remaining = feet
			session.reel_travel_distance()
			session.reel_speed()
			session.bobber_water_depth()
			var expected: Array[String] = []
			for fish_name: String in FishingSession.raw_fish_names():
				var fish := GameData.get_item_by_name(fish_name)
				if int(fish.required_bait_grade) == grade and float(fish.minimum_catch_distance) <= feet:
					expected.append(fish_name)
			var actual: Array[String] = []
			var weights_unchanged := true
			for entry: Dictionary in session.catch_pool():
				actual.append(String(entry.item.name))
				var reference := float(entry.item.catch_weight) * (1.0 + float(int(entry.item.tier) - 1) * feet / 200.0 * 0.35)
				weights_unchanged = weights_unchanged and is_equal_approx(float(entry.weight), reference)
			check(actual == expected, "%s %.2f ft eligibility uses actual distance, never the padded reel travel" % [bait, feet])
			check(weights_unchanged, "Padded reeling distance never increases rarity weights")


func capture_panel() -> void:
	if capture_dir.is_empty():
		return
	var root := get_tree().root
	root.size = Vector2i(1280, 720)
	var scene := (load("res://scenes/EastOutskirtsLayered.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	var game: Node = scene.get_node("Combat")
	game.start_fishing_test()
	var panel: FishingPanel = game.fishing_panel
	# Freeze only the capture view at known progress, while retaining real scene/UI drawing.
	panel.set_process(false)
	for feet: float in [15.0, 200.0]:
		panel.session.player.set_skill_level("fishing", 1 if feet < 200.0 else 100)
		panel.session.rod = "Beginner Rod" if feet < 200.0 else "Demon Rod"
		panel.rod_picker.select(FishingSession.RODS.find(panel.session.rod))
		panel.session.distance = feet
		panel.session.fish = GameData.get_item_by_name("Raw Reedkip")
		panel.session.state = FishingSession.State.FIGHT
		panel.session.message = "Pull against the fish. Keep the bobber between the red lines!"
		for progress: float in [1.0, 0.5]:
			panel.session.remaining = feet * progress
			panel._process(0.0)
			await get_tree().process_frame
			await get_tree().process_frame
			RenderingServer.force_draw(false)
			var name := "fishing-%s-cast-%s.png" % ["short" if feet < 200.0 else "long", "start" if progress == 1.0 else "middle"]
			root.get_texture().get_image().save_png(capture_dir.path_join(name))
	panel.close()
	scene.free()


func _run() -> void:
	check_corridor()
	check_pacing()
	check_actual_distance_pool()
	await capture_panel()
	print("[Fishing pacing] %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
