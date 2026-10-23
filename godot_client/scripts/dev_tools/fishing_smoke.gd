extends Node
## Run against the real catalog and runtime. Optional -- --capture=<absolute directory>.
var checks := 0
var failures: Array[String] = []
var capture_dir := ""

var root: Window

func _ready() -> void:
	root = get_tree().root
	get_tree().create_timer(45.0).timeout.connect(func() -> void:
		printerr("[Fishing FAIL] Test timed out")
		get_tree().quit(1))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture_dir = arg.trim_prefix("--capture=")
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("[Fishing FAIL] ", description)

func prepared(seed_value: int = 42) -> FishingSession:
	var player := PlayerState.new()
	player.add_item("Beginner Rod")
	player.add_item("Low Grade Fish Food", 8)
	var session := FishingSession.new(player)
	session.rng.seed = seed_value
	return session

func cast(session: FishingSession) -> void:
	session.act()
	session.advance(0.7)
	session.act()

func hook(session: FishingSession) -> void:
	while session.state in [FishingSession.State.CASTING, FishingSession.State.WAITING]:
		session.advance(0.05)
	session.act()

func key(code: Key, pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	root.push_input(event)

func click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event)

func capture(file_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if capture_dir.is_empty():
		return
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(capture_dir.path_join(file_name))

func probability(session: FishingSession, name: String) -> float:
	var total := 0.0
	var weight := 0.0
	for entry: Dictionary in session.catch_pool():
		total += float(entry.weight)
		if String(entry.item.name) == name:
			weight = float(entry.weight)
	return weight / total if total > 0.0 else 0.0

func pool_has(session: FishingSession, fish_name: String, feet: float) -> bool:
	return session.catch_pool(feet).any(func(entry: Dictionary) -> bool: return String(entry.item.name) == fish_name)

func check_rod_fish_balance() -> void:
	var session := prepared()
	session.player.set_skill_level("fishing", 100)
	var last_healing := 0
	var last_distance := 0.0
	var last_strength := 0.0
	var last_weight := INF
	for index in range(FishingSession.raw_fish_names().size()):
		var name: String = FishingSession.raw_fish_names()[index]
		var fish := GameData.get_item_by_name(name)
		var cooked := GameData.get_item_by_name(String(fish.cooked_item))
		var feet := float(fish.minimum_catch_distance)
		var grade := int(fish.required_bait_grade)
		session.bait = FishingSession.BAITS[grade - 1]
		check(int(fish.tier) == index + 1 and int(cooked.food_healing) > last_healing and int(fish.food_healing) == 0, "Species tier follows increasing cooked healing; raw fish never heals: " + name)
		check(feet > last_distance and float(fish.fish_strength) > last_strength and float(fish.catch_weight) < last_weight, "Distance and fight strength rise while base rarity weight falls: " + name)
		check(not pool_has(session, name, feet - 0.01) and pool_has(session, name, feet), "Minimum catch distance is an inclusive hard boundary: " + name)
		check(pool_has(session, name, feet), "Required food grade allows the fish at its distance: " + name)
		for other_grade in range(1, 4):
			if other_grade == grade:
				continue
			session.bait = FishingSession.BAITS[other_grade - 1]
			check(not pool_has(session, name, 200.0), "Mismatched food grade %d cannot catch %s even at maximum distance" % [other_grade, name])
		last_healing = int(cooked.food_healing)
		last_distance = feet
		last_strength = float(fish.fish_strength)
		last_weight = float(fish.catch_weight)
	var maxima := [60.0, 90.0, 120.0, 160.0, 200.0]
	var controls := [1.2, 1.55, 2.09, 2.53, 3.08]
	var strongest_reachable := ["Raw Marlo", "Raw Kessa", "Raw Lumara", "Raw Moonfin", "Raw Sunfish"]
	for index in range(FishingSession.RODS.size()):
		var name: String = FishingSession.RODS[index]
		session.rod = name
		session.power = 0.0
		check(is_equal_approx(session.projected_cast_distance(), 10.0), "Zero power casts at the minimum: " + name)
		session.power = 1.0
		check(is_equal_approx(session.projected_cast_distance(), maxima[index]), "Maximum cast is correct: " + name)
		session.power = 0.5
		check(is_equal_approx(session.projected_cast_distance(), lerpf(10.0, maxima[index], 0.5 / FishingSession.PERFECT_CAST_POWER)), "Cast power interpolates rod distance: " + name)
		session.fish_pull = 0.8
		var effective_pull := 0.8 / session.skill_pull_tolerance()
		check(is_equal_approx(session.fight_velocity_target(-1), effective_pull - controls[index]) and is_equal_approx(session.fight_velocity_target(1), effective_pull + controls[index]), "Skill resists fish force while rod input remains predictable: " + name)
		check(is_equal_approx(session.fight_velocity_target(0), effective_pull), "Neutral input retains the resisted fish force: " + name)
		for seed_value in range(3):
			# These challenges isolate rod strength; collection capacity is tested separately.
			session.player.empty_fishing_pale_to_inventory()
			var challenge := FishingSession.new(session.player)
			challenge.rod = name
			var strongest_fish := GameData.get_item_by_name(strongest_reachable[index])
			challenge.bait = FishingSession.BAITS[int(strongest_fish.required_bait_grade) - 1]
			challenge.rng.seed = seed_value
			challenge.distance = maxima[index]
			challenge.remaining = maxima[index]
			challenge.fish = challenge.catch_pool().back().item
			check(String(challenge.fish.name) == strongest_reachable[index], "Rod challenge targets its strongest reachable fish with matching food: " + name)
			challenge.prepare_fight()
			challenge.state = FishingSession.State.FIGHT
			for frame in range(3600):
				if challenge.state != FishingSession.State.FIGHT:
					break
				var pull := clampf((-challenge.lateral * 3.0 - challenge.fish_pull - challenge.velocity * 0.7) / challenge.input_strength(), -1.0, 1.0)
				challenge.advance(1.0 / 60.0, pull)
			check(challenge.state == FishingSession.State.CAUGHT, "%s can land its strongest reachable fish with active counter-steering, seed %d" % [name, seed_value])
	# Catch eligibility must use the new release distance, not a previous cast.
	session = prepared()
	session.distance = 0.0
	session.act()
	session.advance(0.9)
	session.act()
	check(session.state == FishingSession.State.CASTING and is_equal_approx(session.distance, 15.0), "First release checks its level-adjusted distance before spending bait")

func check_cast_mastery() -> void:
	var session := prepared()
	var starts := [15.0, 60.0, 90.0, 120.0, 160.0]
	var caps := [60.0, 90.0, 120.0, 160.0, 200.0]
	var unlocks := [1, 20, 40, 60, 80]
	var masteries := [10, 30, 50, 70, 90]
	for index in range(FishingSession.RODS.size()):
		session.rod = FishingSession.RODS[index]
		var previous_distance := 0.0
		for level in range(unlocks[index], masteries[index] + 1):
			session.player.set_skill_level("fishing", level)
			var expected: float = lerpf(starts[index], caps[index], float(level - unlocks[index]) / float(masteries[index] - unlocks[index]))
			var maximum := session.effective_max_cast_distance()
			check(is_equal_approx(maximum, expected) and maximum > previous_distance, "%s gains cast distance incrementally at Fishing %d" % [session.rod, level])
			session.power = 0.5
			check(is_equal_approx(session.projected_cast_distance(), lerpf(10.0, expected, 0.5 / FishingSession.PERFECT_CAST_POWER)), "Cast power uses the current level's range")
			previous_distance = maximum
		for level in [masteries[index] + 1, 100]:
			session.player.set_skill_level("fishing", level)
			check(is_equal_approx(session.effective_max_cast_distance(), caps[index]), "%s never exceeds its authored cap after mastery" % session.rod)
		for level in [unlocks[index], masteries[index], 100]:
			session.player.set_skill_level("fishing", level)
			var base := float(GameData.get_item_by_name(session.rod).fishing_control)
			check(is_equal_approx(session.input_strength(), base), "Fishing levels do not amplify binary steering overshoot")
			session.fish_pull = 0.8
			check(is_equal_approx(session.effective_fish_pull(), 0.8 / (1.0 + float(level - 1) * 0.0025)), "Fishing level grants a small predictable resistance to fish force")
	# These are geometry gates: Marlo retains its level-1 species requirement,
	# but cannot enter the real full-power catch pool until Beginner mastery.
	session.rod = "Beginner Rod"
	session.bait = "Low Grade Fish Food"
	for level in range(1, 10):
		session.player.set_skill_level("fishing", level)
		session.power = 1.0
		var pool := session.catch_pool(session.projected_cast_distance())
		check(pool.size() == 1 and String(pool[0].item.name) == "Raw Reedkip", "Beginner full-power cast only reaches Reedkip at Fishing %d" % level)
	session.player.set_skill_level("fishing", 10)
	session.power = 1.0
	check(pool_has(session, "Raw Marlo", session.projected_cast_distance()) and not pool_has(session, "Raw Bracken", session.projected_cast_distance()), "Fishing 10 unlocks Marlo by distance on the same Beginner Rod")
	session.power = 0.94
	check(not pool_has(session, "Raw Marlo", session.projected_cast_distance()), "Below-perfect power cannot reach Marlo at mastery")
	for value: float in [0.95, 0.98, 1.0]:
		session.power = value
		check(is_equal_approx(session.projected_cast_distance(), 60.0) and pool_has(session, "Raw Marlo", session.projected_cast_distance()), "Perfect-cast band reaches Marlo without a single-frame requirement")
	var first_levels := [1, 10, 25, 30, 45, 50, 65, 70, 85, 90]
	var first_rods := [0, 0, 1, 1, 2, 2, 3, 3, 4, 4]
	for index in range(FishingSession.raw_fish_names().size()):
		var name: String = FishingSession.raw_fish_names()[index]
		session.bait = FishingSession.BAITS[int(GameData.get_item_by_name(name).required_bait_grade) - 1]
		session.rod = FishingSession.RODS[first_rods[index]]
		session.power = 1.0
		session.player.set_skill_level("fishing", first_levels[index])
		check(pool_has(session, name, session.projected_cast_distance()), "Intended range milestone reaches " + name)
		if first_levels[index] > 1:
			session.player.set_skill_level("fishing", first_levels[index] - 1)
			check(not pool_has(session, name, session.projected_cast_distance()), "Previous level cannot reach " + name)

func check_cast_and_bait_rules() -> void:
	var cycle := FishingSession.CAST_POWER_CYCLE_SECONDS
	check(is_equal_approx(cycle, 1.8), "Cast power completes its full 0-100-0 cycle in exactly 1.8 seconds")
	var fixed_timeline := {0.0: 0.0, 0.45: 0.5, 0.9: 1.0, 1.35: 0.5, 1.8: 0.0, 2.25: 0.5, 2.7: 1.0, 3.15: 0.5, 3.6: 0.0}
	for seconds: float in fixed_timeline:
		check(is_equal_approx(FishingSession.power_at_time(seconds), float(fixed_timeline[seconds])), "Fixed quarter-cycle at %.2f seconds has %.0f percent power" % [seconds, float(fixed_timeline[seconds]) * 100])
	var every_percent := true
	for percent in range(101):
		var value := float(percent) / 100.0
		every_percent = every_percent and is_equal_approx(FishingSession.power_at_time(value * cycle * 0.5), value)
		every_percent = every_percent and is_equal_approx(FishingSession.power_at_time(cycle - value * cycle * 0.5), value)
	check(every_percent, "Power meter passes every percent on both halves of its cycle")
	check(is_equal_approx(FishingSession.power_at_time(0.42), FishingSession.power_at_time(cycle * 12 + 0.42)), "Meter rhythm repeats consistently over multiple cycles")
	var session := prepared()
	session.act()
	for expected_power: float in [0.5, 1.0, 0.5, 0.0, 0.5, 1.0, 0.5, 0.0]:
		session.advance(0.45)
		check(is_equal_approx(session.power, expected_power), "Live meter reaches %.0f percent after %.2f seconds across two 1.8-second cycles" % [expected_power * 100, session.elapsed])
	session.player.set_skill_level("fishing", 100)
	session.power = 0.5
	var beginner_distance := session.projected_cast_distance()
	session.rod = "Pro Rod"
	check(session.projected_cast_distance() > beginner_distance, "Higher rod grade casts farther at identical power")
	session.power = 1.0
	check(is_equal_approx(session.projected_cast_distance(), 120.0), "Full power reaches rod maximum distance")
	var expected_pools := [["Raw Reedkip", "Raw Marlo", "Raw Bracken"], ["Raw Kessa", "Raw Veilfin", "Raw Lumara"], ["Raw Vesper", "Raw Moonfin", "Raw Velora", "Raw Sunfish"]]
	for grade in range(1, 4):
		session.bait = FishingSession.BAITS[grade - 1]
		for feet: float in [200.0, 220.0]:
			session.distance = feet
			var names: Array[String] = []
			for entry: Dictionary in session.catch_pool():
				names.append(String(entry.item.name))
			check(names == expected_pools[grade - 1], "Bait grade %d has exact eligible pool at %d ft, even at Fishing 100" % [grade, roundi(feet)])
		var respects_grade := true
		for draw in range(500):
			var fish := session._roll_fish()
			respects_grade = respects_grade and int(fish.required_bait_grade) == grade
		check(respects_grade, "Bait grade %d rolls only fish requiring that exact grade across 500 catches" % grade)
		var rare_name := String(expected_pools[grade - 1].back())
		session.distance = 180.0
		var near_odds := probability(session, rare_name)
		session.distance = 200.0
		check(probability(session, rare_name) > near_odds, "Distance raises rare catch probability for bait grade %d" % grade)
	check_bait_grade_gates()

func check_bait_grade_gates() -> void:
	var first_fish := ["Raw Reedkip", "Raw Kessa", "Raw Vesper"]
	for index in range(FishingSession.BAITS.size()):
		var bait: String = FishingSession.BAITS[index]
		var first := GameData.get_item_by_name(first_fish[index])
		var minimum := float(first.minimum_catch_distance)
		var session := prepared()
		session.player.set_skill_level("fishing", 100)
		session.player.add_item("Demon Rod")
		session.player.add_item(bait, 8)
		session.rod = "Demon Rod"
		session.bait = bait
		var food_before := int(session.player.backpack[bait])
		check(session.catch_pool(minimum - 0.01).is_empty(), "%s has no fish before its first species' minimum distance" % bait)
		if minimum > FishingSession.MIN_CAST_DISTANCE:
			session.act()
			session.power = (minimum - 0.01 - FishingSession.MIN_CAST_DISTANCE) / (200.0 - FishingSession.MIN_CAST_DISTANCE) * FishingSession.PERFECT_CAST_POWER
			session.act()
			check(session.state == FishingSession.State.READY and int(session.player.backpack[bait]) == food_before, "%s release below minimum distance spends no food and does not fall back to lower-grade fish" % bait)
		session.act()
		session.power = (minimum - FishingSession.MIN_CAST_DISTANCE) / (200.0 - FishingSession.MIN_CAST_DISTANCE) * FishingSession.PERFECT_CAST_POWER
		session.act()
		check(session.state == FishingSession.State.CASTING and int(session.player.backpack[bait]) == food_before - 1 and String(session.fish.get("name", "")) == first_fish[index], "%s can cast at its first exact distance and consumes exactly one food" % bait)
		if index > 0:
			var required_level := int(GameData.get_item_by_name(bait).fishing_level)
			var underleveled := prepared()
			underleveled.player.add_item(bait, 8)
			underleveled.bait = bait
			underleveled.player.set_skill_level("fishing", required_level - 1)
			check(underleveled.catch_pool(200.0).is_empty(), "%s cannot bypass skill requirements by excluding lower-grade fish" % bait)
			underleveled.act()
			check(underleveled.state == FishingSession.State.READY and int(underleveled.player.backpack[bait]) == 8, "%s below its skill requirement cannot charge a cast or spend food" % bait)
			underleveled.player.set_skill_level("fishing", required_level)
			check(underleveled.available(bait) and pool_has(underleveled, first_fish[index], minimum), "%s becomes eligible at its required Fishing level and distance" % bait)

func _run() -> void:
	var data := root.get_node("GameData")
	check_cast_and_bait_rules()
	check_rod_fish_balance()
	check_cast_mastery()
	for name: String in FishingSession.RODS + FishingSession.BAITS + FishingSession.raw_fish_names():
		check(not data.get_item_by_name(name).is_empty(), "Catalog contains " + name)
	var no_gear := FishingSession.new(PlayerState.new())
	no_gear.act()
	check(no_gear.state == FishingSession.State.READY, "Missing gear prevents starting")
	var session := prepared()
	session.act()
	check(session.player.backpack[session.bait] == 8, "Charging uses no bait")
	session.close()
	check(session.player.backpack[session.bait] == 8, "Cancelling power uses no bait")
	session = prepared()
	session.act()
	session.player.remove_item(session.rod)
	session.act()
	check(session.state == FishingSession.State.READY and session.player.backpack[session.bait] == 8, "Missing rod at release cannot consume bait")
	session = prepared()
	cast(session)
	check(session.state == FishingSession.State.CASTING and session.player.backpack[session.bait] == 7, "Release spends exactly one bait")
	session.advance(1.0)
	check(session.state == FishingSession.State.WAITING, "Cast flight arrives at visible bobber wait")
	while session.state == FishingSession.State.WAITING:
		session.advance(0.05)
	check(session.state == FishingSession.State.BITE, "Waiting produces timed bite alert")
	session.advance(2.0)
	check(session.state == FishingSession.State.LOST and session.player.get_skill_experience("fishing") == 0, "Missed bite awards no XP")
	for seed_value in range(12):
		session = prepared(seed_value)
		cast(session)
		hook(session)
		var original_combat := session.player.get_combat_level()
		for frame in range(3600):
			if session.state != FishingSession.State.FIGHT:
				break
			var pull := clampf((-session.lateral * 3.0 - session.fish_pull - session.velocity * 0.7) / session.input_strength(), -1.0, 1.0)
			session.advance(1.0 / 60.0, pull)
		check(session.state == FishingSession.State.CAUGHT, "Active steering lands seed %d" % seed_value)
		check(session.player.get_skill_experience("fishing") > 0 and session.player.fishing_pale.count(String(session.fish.name)) == 1 and int(session.player.backpack.get(session.fish.name, 0)) == 0, "Landing grants one pale fish and XP without filling the backpack")
		check(session.player.get_combat_level() == original_combat, "Fishing leaves combat rating unchanged")
		var xp := session.player.get_skill_experience("fishing")
		session.advance(1.0)
		check(session.player.get_skill_experience("fishing") == xp, "Finished session cannot repeat its reward")
	session = prepared()
	cast(session)
	hook(session)
	session.lateral = session.boundary() + 0.3
	session.velocity = 1.0
	session.fish_pull = 0.9
	session.fight_plan = [[60.0,0.9]]
	session.plan_index = 0
	session.dart_after = 10.0
	session.advance(1.5)
	check(session.state == FishingSession.State.LOST and session.reward_xp == 0, "Ignoring the boundaries loses fish without rewards")
	session = prepared()
	var beginner_boundary := session.boundary()
	session.player.add_item("Pro Rod")
	check(not session.available("Pro Rod"), "Advanced pole requires Fishing level")
	session.player.set_skill_level("fishing", 40)
	check(session.available("Pro Rod"), "Advanced pole unlocks at its level")
	session.rod = "Pro Rod"
	check(session.boundary() > beginner_boundary, "Better pole and skill widen control boundaries")
	var eater := PlayerState.new()
	eater.add_item("Reedkip", 3)
	check(FishingSession.eat(eater, "Reedkip") == 0 and eater.backpack["Reedkip"] == 3, "Full health consumes no food")
	eater.current_hp -= 5
	check(FishingSession.eat(eater, "Reedkip") == 5 and eater.current_hp == eater.get_max_hp() and eater.backpack["Reedkip"] == 2, "Food heals actual missing HP and spends one fish")
	eater.current_hp = 0
	check(FishingSession.eat(eater, "Reedkip") == 0 and eater.backpack["Reedkip"] == 2, "Food cannot revive dead players")
	# Full runtime integration, including shoreline collision and native input.
	root.size = Vector2i(1280, 720)
	var scene := (load("res://scenes/EastOutskirtsLayered.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	var game: Node = scene.get_node("Combat")
	game.set_physics_process(false)
	var spots: Array = game.fishing_spots()
	check(spots.size() == 2, "Runtime provides two editable fishing spots")
	var panel: FishingPanel = game.fishing_panel
	panel.set_process(false)
	game.request_fishing(spots[0])
	check(not panel.visible, "World proximity prevents remote fishing")
	for spot: FishingSpot in spots:
		var query := PhysicsShapeQueryParameters2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 10.0
		query.shape = shape
		query.transform = Transform2D(0, spot.shore_position())
		var hits: Array = scene.get_world_2d().direct_space_state.intersect_shape(query)
		check(hits.is_empty(), "Fishing shore is walkable: " + spot.spot_name)
	var at: Vector2 = game.interactions._simulation_position(spots[0].shore_position())
	var actor: CombatActor = game.combat.actors[game.player.entity_id]
	actor.x = at.x
	actor.y = at.y
	game.player.x = at.x
	game.player.y = at.y
	game._update_sprite_position(game.player.entity_id)
	game._update_map_camera()
	await get_tree().process_frame
	await capture("fishing-world.png")
	key(KEY_F)
	check(panel.visible, "F opens nearby fishing spot through runtime input")
	key(KEY_SPACE)
	check(panel.session.state == FishingSession.State.POWER, "Space starts cast power without combat input")
	panel._process(0.7)
	await capture("fishing-cast.png")
	key(KEY_SPACE)
	check(panel.session.state == FishingSession.State.CASTING, "Space releases cast through runtime input")
	while panel.session.state in [FishingSession.State.CASTING, FishingSession.State.WAITING]:
		panel._process(0.05)
	await capture("fishing-bite.png")
	var board_center := panel.origin + Vector2(640, 300)
	click(panel.get_global_transform_with_canvas() * board_center)
	check(panel.session.state == FishingSession.State.FIGHT, "Clicking water hooks the bite through native GUI dispatch")
	key(KEY_A)
	check(panel.keyboard_steering == -1.0, "Fishing receives left steering")
	key(KEY_A, false)
	check(panel.keyboard_steering == 0.0, "Releasing steering clears key")
	panel._process(0.1)
	await capture("fishing-fight.png")
	var bait_before := int(game.player.backpack.get("Low Grade Fish Food", 0))
	key(KEY_ESCAPE)
	check(not panel.visible and panel.session.state == FishingSession.State.CLOSED, "Escape closes and cancels fishing")
	check(int(game.player.backpack.get("Low Grade Fish Food", 0)) == bait_before, "Closing spent cast grants no bait refund")
	game.try_nearby_fishing()
	game.player.current_hp -= 1
	panel._process(0.02)
	check(not panel.visible, "Taking damage interrupts fishing")
	game.inventory_menu.select_page(InventoryMenu.Page.SKILLS)
	game.inventory_menu.show()
	check(game.inventory_menu._skill_session_labels.has("fishing"), "Journal renders Fishing progression")
	await capture("fishing-skills.png")
	for dimensions: Vector2i in [Vector2i(960, 540), Vector2i(1920, 1080)]:
		root.size = dimensions
		game._update_ui_scale()
		game.inventory_menu.hide()
		game.request_fishing(spots[0])
		panel._layout()
		check(panel.origin.x >= 0 and panel.origin.y >= 0 and panel.origin.x + panel.PANEL_SIZE.x <= panel.size.x, "Fishing fits viewport %s" % dimensions)
		panel.close()
	# Quick practice entry point works without locating a world marker.
	root.size = Vector2i(1280, 720)
	game._update_ui_scale()
	game.player.backpack.clear()
	game.player.set_skill_level("fishing", 1)
	actor.x -= 10.0
	game.player.x = actor.x
	game.player.y = actor.y
	game._update_sprite_position(game.player.entity_id)
	var original_position: Vector2 = game.player.get_position()
	await get_tree().process_frame
	click(game.fishing_test_button.get_global_rect().get_center())
	check(panel.visible and panel.spot == game.fishing_practice_spot, "Top-bar Test fishing button opens practice from anywhere")
	check(game.player.get_position() == original_position, "Practice does not move the player")
	check(game.player.get_skill_level("fishing") == 1, "Practice preserves Fishing level and unlock requirements")
	for name: String in FishingSession.RODS + FishingSession.BAITS:
		var wanted := 50 if name in FishingSession.BAITS else 1
		check(int(game.player.backpack.get(name, 0)) == wanted, "Practice supplies " + name)
	check(game.fishing_spots().size() == 2, "Hidden practice anchor does not become a world fishing marker")
	key(KEY_SPACE)
	panel._process(0.7)
	key(KEY_SPACE)
	while panel.session.state in [FishingSession.State.CASTING, FishingSession.State.WAITING]:
		panel._process(0.05)
	key(KEY_SPACE)
	for frame in range(3600):
		if panel.session.state != FishingSession.State.FIGHT:
			break
		panel.steering = clampf((-panel.session.lateral * 3.0 - panel.session.fish_pull - panel.session.velocity * 0.7) / panel.session.input_strength(), -1.0, 1.0)
		panel._process(1.0 / 60.0)
	var caught_name := String(panel.session.fish.get("name", ""))
	check(panel.session.state == FishingSession.State.CAUGHT and game.player.fishing_pale.count(caught_name) == 1 and int(game.player.backpack.get(caught_name, 0)) == 0, "Practice catch reaches the Fishing Pale")
	await capture("fishing-practice-caught.png")
	key(KEY_ESCAPE)
	for name: String in FishingSession.RODS + FishingSession.BAITS + FishingSession.raw_fish_names():
		var icon := ItemVisualLibrary.texture(name)
		check(icon != null and icon.get_width() == 64 and ItemVisualLibrary.has_ground_visual(name), "Fishing placeholder is available in inventory and on ground: " + name)
	key(KEY_P)
	check(panel.visible, "P reopens practice through native input")
	check(game.player.backpack["Low Grade Fish Food"] == 50 and game.player.backpack["Beginner Rod"] == 1, "Re-entry refills bait without stacking duplicate poles")
	key(KEY_ESCAPE)
	check(game.player.empty_fishing_pale_to_inventory() == 1 and int(game.player.backpack.get(caught_name, 0)) == 1, "Pale catch can be moved to the real inventory")
	game.inventory_menu.selected_item_name = caught_name
	game.inventory_menu.select_page(InventoryMenu.Page.INVENTORY)
	game.inventory_menu.show()
	await capture("fishing-placeholder-inventory.png")
	print("[Fishing] %d checks, %d failures" % [checks, failures.size()])
	scene.free()
	get_tree().quit(0 if failures.is_empty() else 1)
