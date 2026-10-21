extends Node

const TRIALS := 500
const STEP_SECONDS := 0.03
const LEVEL_40_TRIALS := 1000
var checks := 0
var failures: Array[String] = []
var adapter: Node

class FixedSkillsPlayer extends PlayerState:
	func add_skill_experience(skill: String, _amount: int) -> int:
		return get_skill_level(skill)

func _ready() -> void:
	adapter = load("res://scenes/main.tscn").instantiate()
	_check_profiles()
	_check_defences()
	_check_attack_rotation()
	if "--benchmark-goblins" in OS.get_cmdline_user_args():
		_benchmark()
	if "--steel-level-40" in OS.get_cmdline_user_args():
		_benchmark_level_40()
	adapter.free()
	print("[Goblin combat] %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr(label)

func _goblin(suffix: String) -> CombatActor:
	var monster := MonsterState.new(GameData.get_monster_by_name("Goblin " + suffix))
	return adapter._create_actor_from_stats("goblin", monster.name, 10.0, 10.0,
		monster.get_combat_stats(), true, monster.damage_type)

func _check_profiles() -> void:
	for fixture: Array in [["Scout", 5, 60, 3], ["Worker", 12, 120, 6],
			["Warrior", 25, 200, 12], ["Shaman", 45, 700, 15], ["Chieftain", 50, 1000, 50]]:
		var monster := MonsterState.new(GameData.get_monster_by_name("Goblin " + fixture[0]))
		var actor := _goblin(fixture[0])
		_check(monster.level == fixture[1], actor.name + " has its approved encounter level")
		_check(actor.hp == fixture[2] and actor.max_hp == fixture[2], actor.name + " spawns with skill-derived full health")
		_check(actor.defence_level == fixture[3], actor.name + " retains its Defence through the gameplay adapter")
	for fixture: Array in [["Worker", 8, 1280.0], ["Warrior", 12, 1920.0], ["Chieftain", 42, 5952.0]]:
		var actor := _goblin(fixture[0])
		_check(actor.melee_max_damage == fixture[1], actor.name + " derives its melee maximum from unarmed Strength")
		_check(actor.melee_attack_roll == fixture[2], actor.name + " derives melee accuracy from Attack, not display level")
	var shaman := _goblin("Shaman")
	_check(shaman.min_damage == 20 and shaman.max_damage == 36 and is_equal_approx(shaman.accuracy, 0.70), "Shaman retains its dangerous magic profile in combat")
	var chieftain := _goblin("Chieftain")
	_check(chieftain.min_damage == 16 and chieftain.max_damage == 28 and is_equal_approx(chieftain.accuracy, 0.65), "Chieftain keeps a distinct secondary magic profile")

func _check_defences() -> void:
	var engine := CombatEngine.new()
	engine.random.seed = 815
	var probe := CombatActor.new().configure({"attack_style": "slash", "melee_attack_roll": 3072.0})
	for suffix: String in ["Scout", "Worker", "Warrior", "Shaman", "Chieftain"]:
		var target := _goblin(suffix)
		var slash_chance := engine.calculate_hit_chance(probe, target)
		_check(is_equal_approx(engine.calculate_hit_chance(probe, target, 1.0, "magic"), 0.99), suffix + ": magic absorption does not also lower hit chance")
		for style: String in PlayerStats.MELEE_STYLES:
			probe.attack_style = style
			_check(is_equal_approx(engine.calculate_hit_chance(probe, target), slash_chance), suffix + ": physical styles face the same low/base Defence without legacy resistance offsets")
		for style: String in ["slash", "stab", "blunt", "magic"]:
			var expected_damage := 100
			if suffix == "Chieftain":
				expected_damage = 75
			elif suffix == "Shaman" and style == "magic":
				expected_damage = 40
			var landed := 0
			var correct := true
			for attempt in range(100):
				var outcome := engine.calculate_hit_outcome(probe, target, 100, 1.0, style, 100)
				if outcome.hit:
					landed += 1
					correct = correct and outcome.damage == expected_damage
			_check(landed > 0 and correct, suffix + ": " + style + " absorption applies exactly once to landed damage")
	var shaman := _goblin("Shaman")
	var chieftain := _goblin("Chieftain")
	_check(engine.calculate_hit_chance(probe, shaman) > engine.calculate_hit_chance(probe, chieftain), "Shaman is easier to hit physically than Chieftain")

func _check_attack_rotation() -> void:
	for suffix: String in ["Scout", "Shaman", "Chieftain"]:
		var engine := CombatEngine.new()
		engine.random.seed = 912
		var target := CombatActor.new().configure({"entity_id": "player", "x": 9.0, "y": 10.0,
			"max_hp": 100000, "min_damage": 0, "max_damage": 0})
		var monster := _goblin(suffix)
		engine.add_actor(target)
		engine.add_actor(monster)
		engine._resolve_attack(null, target, monster)
		var melee_attacks := 0
		var projectiles_spawned := 0
		var projectiles_resolved := 0
		var styles: Array[String] = []
		for tick in range(12):
			var events := engine.process_tick(null)
			for event: Dictionary in events:
				if event.get("attacker_id", "") != "goblin":
					continue
				if event.type == "entity_hit":
					melee_attacks += 1
					styles.append(monster.attack_style)
				elif event.type == "projectile_spawned":
					projectiles_spawned += 1
					styles.append(event.damage_type)
			for event: Dictionary in engine._process_projectiles(null, 0.6):
				if event.type == "projectile_hit":
					projectiles_resolved += 1
		if suffix == "Chieftain":
			_check(melee_attacks == 3 and projectiles_spawned == 1 and styles == ["slash", "slash", "slash", "magic"], "Chieftain uses three real melee attacks followed by a magic projectile")
		else:
			_check(melee_attacks == 0 and projectiles_spawned == 4, suffix + " attacks with projectiles every 1.8 seconds")
		_check(projectiles_spawned == projectiles_resolved, suffix + " projectiles actually reach and resolve against the player")

func _player(material: String, level: int) -> FixedSkillsPlayer:
	var player := FixedSkillsPlayer.new("Goblin balance")
	for skill: String in ["attack", "strength", "defense"]:
		player.set_skill_level(skill, level)
	player.set_skill_level("health", maxi(10, level))
	for suffix: String in ["Helmet", "Platebody", "Platelegs", "Cape", "Ring", "Ring", "Necklace", "Longsword", "Kiteshield"]:
		player.give_and_equip(material + " " + suffix)
	_check(String(player.equipment.weapon.get("name", "")) == material + " Longsword", "Benchmark legally equips " + material + " at skill " + str(level))
	player.set_attack_style("slash")
	return player

func _duels(material: String, level: int, suffix: String) -> Dictionary:
	var player := _player(material, level)
	var stats := player.get_combat_stats()
	var wins := 0
	var timeouts := 0
	var kill_seconds := 0.0
	var damage_on_wins := 0
	for trial in range(TRIALS):
		player.current_hp = player.get_max_hp()
		var attacker: CombatActor = adapter._create_actor_from_stats(player.entity_id, "Player", 9.0, 10.0, stats)
		var monster := _goblin(suffix)
		player.current_target = monster.entity_id
		var world := {"player": player, "monsters": []}
		var engine := CombatEngine.new()
		engine.random.seed = 612000 + trial
		engine.add_actor(attacker)
		engine.add_actor(monster)
		var step := 0
		while attacker.is_alive and monster.is_alive and step < 20000:
			engine.process_realtime(world, 0.0 if step == 0 else STEP_SECONDS)
			if step % 20 == 0:
				engine.process_tick(world)
			step += 1
		if not monster.is_alive and attacker.is_alive:
			wins += 1
			kill_seconds += float(step - 1) * STEP_SECONDS
			damage_on_wins += attacker.max_hp - attacker.hp
		elif attacker.is_alive and monster.is_alive:
			timeouts += 1
	_check(timeouts == 0, material + " versus " + suffix + " resolves before ten minutes")
	return {"monster": "Goblin " + suffix, "equipment": material + " Longsword, Kiteshield, full armour and jewelry",
		"attack_strength_defence": level, "health_level": maxi(10, level), "player_hp": player.get_max_hp(),
		"trials": TRIALS, "wins": wins, "win_rate": float(wins) / TRIALS,
		"mean_kill_seconds_on_wins": kill_seconds / maxi(1, wins),
		"mean_damage_taken_on_wins": float(damage_on_wins) / maxi(1, wins), "timeouts": timeouts}

func _benchmark() -> void:
	var results: Array[Dictionary] = []
	for fixture: Array in [["Bronze", 1, "Scout"], ["Iron", 12, "Worker"], ["Steel", 25, "Warrior"]]:
		var result := _duels(fixture[0], fixture[1], fixture[2])
		results.append(result)
		print("[Goblin duel] " + JSON.stringify(result))
	for level: int in [40, 45, 50]:
		for material: String in ["Blacksteel", "Mithril"]:
			for suffix: String in ["Shaman", "Chieftain"]:
				var result := _duels(material, level, suffix)
				results.append(result)
				print("[Goblin duel] " + JSON.stringify(result))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://combat_balance"))
	var report := FileAccess.open("user://combat_balance/goblins.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"model": "No food, no spells, no movement, one-on-one, player initiates at melee distance, fixed skills, real ticks and projectiles, 0.03s frames", "results": results}, "  "))
	report.close()

func _level_40_player(build: Array) -> FixedSkillsPlayer:
	var player := _player("Steel", 45)
	player.set_skill_level("attack", int(build[1]))
	player.set_skill_level("strength", int(build[2]))
	player.set_skill_level("defense", int(build[3]))
	_check(player.get_combat_level() == 40, String(build[0]) + " is exactly displayed combat level 40")
	_check(player.get_skill_level("range") == 1 and player.get_skill_level("magic") == 1, String(build[0]) + " keeps non-melee combat skills at 1")
	_check(player.get_max_hp() == 900, String(build[0]) + " has the controlled 45 Health / 900 HP")
	for slot: String in ["head", "chest", "legs", "cape", "neck", "ring1", "ring2", "weapon", "shield"]:
		var item: Dictionary = player.equipment.get(slot, {})
		_check(not item.is_empty() and String(item.get("material", "")) == "Steel", String(build[0]) + " wears Steel in " + slot)
	_check(player.get_skill_level("attack") >= 20 and player.get_skill_level("defense") >= 20, String(build[0]) + " meets Steel requirements with its final skills")
	return player

func _level_40_duels(build: Array) -> Dictionary:
	var player := _level_40_player(build)
	var stats := player.get_combat_stats()
	var wins := 0
	var timeouts := 0
	var kill_seconds := 0.0
	var death_seconds := 0.0
	var remaining_hp_on_wins := 0
	var remaining_boss_hp_on_losses := 0
	var sample_player_chance := 0.0
	var sample_melee_chance := 0.0
	for trial in range(LEVEL_40_TRIALS):
		player.current_hp = player.get_max_hp()
		var attacker: CombatActor = adapter._create_actor_from_stats(player.entity_id, "Player", 9.0, 10.0, stats)
		var monster := _goblin("Chieftain")
		player.current_target = monster.entity_id
		var world := {"player": player, "monsters": []}
		var engine := CombatEngine.new()
		engine.random.seed = 740000 + trial
		engine.add_actor(attacker)
		engine.add_actor(monster)
		if trial == 0:
			sample_player_chance = engine.calculate_hit_chance(attacker, monster)
			sample_melee_chance = engine.calculate_hit_chance(monster, attacker, null, "slash")
		var elapsed := 0.0
		var next_tick := 0.0
		var delta := 0.0
		while attacker.is_alive and monster.is_alive and elapsed < 600.0:
			elapsed += delta
			engine.process_realtime(world, delta)
			if elapsed + 0.000001 >= next_tick:
				engine.process_tick(world)
				next_tick += GameTickConfig.TICK_DURATION_SECONDS
			delta = minf(attacker.attack_cooldown_seconds, maxf(0.0, next_tick - elapsed))
			if not engine.projectiles.is_empty():
				delta = minf(delta, STEP_SECONDS)
		if not monster.is_alive and attacker.is_alive:
			wins += 1
			kill_seconds += elapsed
			remaining_hp_on_wins += attacker.hp
		elif not attacker.is_alive:
			death_seconds += elapsed
			remaining_boss_hp_on_losses += monster.hp
		else:
			timeouts += 1
	_check(timeouts == 0, String(build[0]) + " finishes every level-40 duel")
	return {"build": build[0], "combat_level": player.get_combat_level(),
		"attack": player.get_skill_level("attack"), "strength": player.get_skill_level("strength"),
		"defense": player.get_skill_level("defense"), "health_level": player.get_skill_level("health"),
		"range": 1, "magic": 1, "player_hp": player.get_max_hp(), "trials": LEVEL_40_TRIALS,
		"wins": wins, "win_rate": float(wins) / LEVEL_40_TRIALS, "timeouts": timeouts,
		"player_melee_hit_chance": sample_player_chance, "chieftain_melee_hit_chance": sample_melee_chance,
		"raw_max_hit": stats.max_damage, "max_hit_after_absorption": floori(float(stats.max_damage) * 0.75),
		"mean_kill_seconds_on_wins": kill_seconds / wins if wins > 0 else null,
		"mean_hp_remaining_on_wins": float(remaining_hp_on_wins) / wins if wins > 0 else null,
		"mean_death_seconds_on_losses": death_seconds / (LEVEL_40_TRIALS - wins) if wins < LEVEL_40_TRIALS else null,
		"mean_boss_hp_remaining_on_losses": float(remaining_boss_hp_on_losses) / (LEVEL_40_TRIALS - wins) if wins < LEVEL_40_TRIALS else null}

func _benchmark_level_40() -> void:
	var results: Array[Dictionary] = []
	for build: Array in [["Balanced", 45, 45, 45], ["Attack focus", 65, 35, 35],
			["Strength focus", 35, 65, 35], ["Defence focus", 35, 35, 65],
			["Attack + Strength", 55, 55, 25], ["Attack + Defence", 55, 25, 55],
			["Strength + Defence", 25, 55, 55], ["Extreme Attack", 95, 20, 20],
			["Extreme Strength", 20, 95, 20], ["Extreme Defence", 20, 20, 95]]:
		var result := _level_40_duels(build)
		results.append(result)
		print("[Steel combat 40] " + JSON.stringify(result))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://combat_balance"))
	var report := FileAccess.open("user://combat_balance/steel_level_40_chieftain.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"model": "Full Steel Longsword/Kiteshield set including armour and jewelry; no food, spells or movement; Health 45; Range/Magic 1; fixed skills; player initiates at melee distance; real engine player cooldowns, monster ticks, hybrid rotation and projectiles; idle frames skipped, in-flight shots advanced at up to 0.03s", "results": results}, "  "))
	report.close()
