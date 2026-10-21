extends Node

const MATERIALS := ["Bronze", "Iron", "Steel", "Blacksteel", "Mithril", "Adamantite", "Runite"]
const TRIALS := 2000
var checks := 0
var failures: Array[String] = []
var results: Array[Dictionary] = []
var adapter: Node

func _ready() -> void:
	adapter = load("res://scenes/main.tscn").instantiate()
	if "--calibrate-titan" in OS.get_cmdline_user_args():
		for strength: int in [460, 468, 476]:
			var result := _duels(_player("Adamantite", "Warmaul"), 0, strength)
			result["titan_strength"] = strength
			print("[Titan calibration] " + JSON.stringify(result))
		adapter.free()
		get_tree().quit(0)
		return
	if "--runite-skill-check" in OS.get_cmdline_user_args():
		for health_level: int in [60, 70, 80, 100]:
			var player := _player("Runite", "Warmaul")
			player.set_skill_level("attack", 60)
			player.set_skill_level("defense", 70)
			player.set_skill_level("strength", 70)
			player.set_skill_level("health", health_level)
			for budget: int in [0, 800]:
				var result := _duels(player, budget)
				result["health_level"] = health_level
				result["max_hp"] = player.get_max_hp()
				result["attack_level"] = 60
				result["defense_level"] = 70
				result["strength_level"] = 70
				print("[Runite skill check] " + JSON.stringify(result))
		adapter.free()
		get_tree().quit(0)
		return
	_check_formulas()
	_check_catalog()
	_check_monsters()
	_check_balance()
	var report := {"trials_per_loadout": TRIALS, "healing_model": "Optional 800 HP budget, four instant 200 HP heals at 1000 HP; no eating delay; not an implemented food action", "results": results, "checks": checks, "failures": failures}
	var report_path := "user://combat_balance/titan.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://combat_balance"))
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("[Titan balance] Report: " + ProjectSettings.globalize_path(report_path))
	adapter.free()
	print("[Titan balance] %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr(label)

func _actor(stats: Dictionary, monster: bool) -> CombatActor:
	return adapter._create_actor_from_stats("titan" if monster else "player", "Balance actor", 10.0 if monster else 9.0, 10.0, stats, monster, "blunt" if monster else "")

func _player(material: String, weapon: String) -> PlayerState:
	var player := PlayerState.new("Tier balance")
	for skill: String in SkillProgression.SKILL_IDS:
		player.set_skill_level(skill, 100)
	if not material.is_empty():
		for suffix: String in ["Helmet", "Platebody", "Platelegs", "Cape", "Ring", "Ring", "Necklace"]:
			player.give_and_equip(material + " " + suffix)
		if not weapon.is_empty():
			player.give_and_equip(material + " " + weapon)
		if weapon != "Warmaul":
			player.give_and_equip(material + " Kiteshield")
	if weapon in ["Mace", "Warmaul"]:
		player.set_attack_style("crush")
	if weapon == "Warmaul":
		_check(String(player.equipment.weapon.get("name", "")) == material + " Warmaul", material + " duel explicitly equips its warmaul")
		_check(player.equipment.shield.is_empty(), material + " warmaul duel has no shield")
		_check(player.get_combat_stats().style == "blunt", material + " warmaul duel uses Crush")
		_check(is_equal_approx(player.get_combat_stats().attack_interval_seconds, 3.0), material + " warmaul duel uses its real cadence")
	return player

func _check_formulas() -> void:
	var engine := CombatEngine.new()
	var template := GameData.get_monster_by_name("Golem Titan").duplicate(true)
	var base := MonsterState.new(template).get_combat_stats()
	_check(base.health.max == 3600 and base.max_damage == 119, "Titan health and max hit derive from skills")
	_check(base.melee_attack_roll == PlayerStats.melee_attack_roll(500, 0), "Titan has no hidden weapon accuracy bonus")
	template.skills.attack += 100
	var accurate := MonsterState.new(template).get_combat_stats()
	_check(accurate.max_damage == base.max_damage and accurate.melee_attack_roll > base.melee_attack_roll, "Monster Attack changes accuracy only")
	template.skills.attack -= 100
	template.skills.strength += 100
	var strong := MonsterState.new(template).get_combat_stats()
	_check(strong.max_damage > base.max_damage and strong.melee_attack_roll == base.melee_attack_roll, "Monster Strength changes damage only")
	var boss := _actor(base, true)
	var probe := CombatActor.new().configure({"attack_style": "slash", "melee_attack_roll": PlayerStats.melee_attack_roll(100, 0), "crit_chance": 0.0})
	var slash_chance := engine.calculate_hit_chance(probe, boss)
	probe.attack_style = "blunt"
	_check(is_equal_approx(engine.calculate_hit_chance(probe, boss), slash_chance), "Damage reductions do not also penalize accuracy")
	for style: String in PlayerStats.MELEE_STYLES:
		var correct := true
		for attempt in range(100):
			var outcome := engine.calculate_hit_outcome(probe, boss, 100, 1.0, style, 100)
			correct = correct and (not outcome.hit or outcome.damage == (80 if style == "blunt" else 40))
		_check(correct, style + " reduction applies to landed damage exactly once")
	var target := _actor(_player("Runite", "Mace").get_combat_stats(), false)
	_check(engine.calculate_hit_chance(boss, target) > 0.6, "Titan has meaningful accuracy against max-level Runite")
	var all_capped := true
	for attempt in range(500):
		var hit := engine.calculate_hit_outcome(boss, target)
		all_capped = all_capped and hit.damage <= boss.max_damage
	_check(all_capped, "Monster melee hits and criticals obey the same max-hit cap as players")
	var round_trip := CombatActor.new().configure(boss.to_dictionary())
	_check(round_trip.melee_max_damage == boss.melee_max_damage and round_trip.melee_attack_roll == boss.melee_attack_roll, "Monster melee fields survive serialization")

func _check_catalog() -> void:
	var count := 0
	for item: Dictionary in GameData.items:
		if item.type != "Weapon" or not PlayerStats.valid_styles_for_weapon(item).any(func(style: String) -> bool: return style in PlayerStats.MELEE_STYLES):
			continue
		count += 1
		_check(item.has("melee_strength_bonus"), String(item.name) + " has authored melee strength")
		var player := _player("", "")
		player.give_and_equip(item)
		var maximum := -1
		for style: String in PlayerStats.valid_styles_for_weapon(item):
			player.set_attack_style(style)
			var stats := player.get_combat_stats()
			_check(stats.min_damage == 1 and stats.damage_roll_level == 0 and stats.melee_attack_roll > 0.0, String(item.name) + " uses shared melee formulas")
			_check(maximum < 0 or stats.max_damage == maximum, String(item.name) + " keeps damage separate from style")
			maximum = stats.max_damage
	_check(count == 40, "All 35 standard and five artifact melee weapons converted")
	for suffix: String in ["Dagger", "Shortsword", "Longsword", "Mace", "Warmaul"]:
		var previous_max := 0
		var previous_roll := 0.0
		for material: String in MATERIALS:
			var stats := _player(material, suffix).get_combat_stats()
			_check(stats.max_damage > previous_max and stats.melee_attack_roll > previous_roll, material + " " + suffix + " improves strength and accuracy")
			previous_max = stats.max_damage
			previous_roll = stats.melee_attack_roll
	var player := _player("Runite", "Mace")
	player.give_and_equip("Ashrender Maul")
	_check(player.equipment.shield.is_empty(), "Artifact maul obeys two-handed rules")

func _check_monsters() -> void:
	for template: Dictionary in GameData.monsters:
		var monster := MonsterState.new(template)
		var stats := monster.get_combat_stats()
		_check(monster.max_hp == PlayerStats.max_health(int(template.skills.health)), String(monster.name) + " derives HP from Health")
		_check(stats.melee_max_damage == PlayerStats.melee_max_hit(int(template.skills.strength), 0), String(monster.name) + " has unarmed skill-derived melee power")
		_check(stats.melee_attack_roll == PlayerStats.melee_attack_roll(int(template.skills.attack), 0), String(monster.name) + " has skill-derived accuracy")
		if monster.damage_type in PlayerStats.MELEE_STYLES:
			_check(monster.min_damage == 1 and monster.max_damage == stats.melee_max_damage, String(monster.name) + " has no fixed melee damage profile")
	var titan := MonsterState.new(GameData.get_monster_by_name("Golem Titan"))
	_check(titan.level == 180 and int(titan.skills.attack) > 100 and int(titan.skills.strength) > 100, "Monster skills can exceed the player cap independently of combat level")
	_check(titan.damage_reductions.slash == 0.6 and titan.damage_reductions.stab == 0.6 and titan.damage_reductions.blunt == 0.2, "Titan has requested landed-damage reductions")
	var previous_level := 0
	var previous_hp := 0
	for suffix: String in ["Shardling", "Boulderkin", "Stoneguard", "Runeshell", "Titan"]:
		var golem := MonsterState.new(GameData.get_monster_by_name("Golem " + suffix))
		_check(golem.level > previous_level and golem.max_hp > previous_hp, "Golem family progresses through " + suffix)
		previous_level = golem.level
		previous_hp = golem.max_hp

func _duels(player: PlayerState, healing_budget: int, strength_override: int = -1) -> Dictionary:
	var engine := CombatEngine.new()
	var player_stats := player.get_combat_stats()
	var titan_template := GameData.get_monster_by_name("Golem Titan").duplicate(true)
	if strength_override > 0:
		titan_template.skills.strength = strength_override
	var titan_stats := MonsterState.new(titan_template).get_combat_stats()
	var attacker := _actor(player_stats, false)
	var titan := _actor(titan_stats, true)
	engine.add_actor(attacker)
	engine.add_actor(titan)
	var wins := 0
	var kill_seconds := 0.0
	var damage_taken := 0
	for trial in range(TRIALS):
		engine.random.seed = 20261020 + trial
		attacker.hp = attacker.max_hp
		attacker.is_alive = true
		titan.hp = titan.max_hp
		titan.is_alive = true
		var player_time := 0.0
		var titan_time := 0.6
		var elapsed := 0.0
		var remaining_healing := healing_budget
		while attacker.is_alive and titan.is_alive and elapsed < 3600.0:
			if attacker.hp <= 1000 and remaining_healing > 0:
				var healing := mini(200, remaining_healing)
				attacker.hp = mini(attacker.max_hp, attacker.hp + healing)
				remaining_healing -= healing
			if player_time <= titan_time + 0.00001:
				elapsed = player_time
				player_time += float(player_stats.attack_interval_seconds)
				engine.fight_turn("player", "titan")
			else:
				elapsed = titan_time
				titan_time += 1.8
				engine.fight_turn("titan", "player")
		if not titan.is_alive:
			wins += 1
			kill_seconds += elapsed
			damage_taken += attacker.max_hp + healing_budget - remaining_healing - attacker.hp
	return {
		"weapon": String(player.equipment.weapon.get("name", "Unarmed")),
		"style": String(player_stats.style), "shield": player.equipment.shield.get("name", null),
		"attack_interval_seconds": player_stats.attack_interval_seconds,
		"raw_max_hit": player_stats.max_damage,
		"max_hit_after_absorption": floori(float(player_stats.max_damage) * (1.0 - float(titan.damage_reductions.get(String(player_stats.style), 0.0))) + 0.000001),
		"player_hit_chance": engine.calculate_hit_chance(attacker, titan),
		"titan_hit_chance": engine.calculate_hit_chance(titan, attacker),
		"wins": wins, "trials": TRIALS, "win_rate": float(wins) / float(TRIALS),
		"mean_kill_seconds": kill_seconds / maxi(1, wins),
		"mean_damage_taken_on_wins": float(damage_taken) / maxi(1, wins), "healing_budget": healing_budget
	}

func _check_balance() -> void:
	for material: String in [""] + MATERIALS:
		for budget: int in [0, 800]:
			var result := _duels(_player(material, "" if material.is_empty() else "Warmaul"), budget)
			result["loadout"] = "Naked unarmed" if material.is_empty() else material + " Warmaul set"
			results.append(result)
			print("[Titan duel] " + JSON.stringify(result))
			if material in ["", "Bronze"]:
				_check(result.win_rate <= 0.01, "Unarmed/bronze cannot sustain the Titan encounter")
			if material == "Mithril" and budget == 800:
				_check(result.win_rate < 0.8, "Mithril remains below reliable Titan equipment")
			if material == "Adamantite" and budget == 800:
				_check(result.win_rate >= 0.85 and result.win_rate < 0.995, "Adamantite with a fixed healing budget remains challenging")
			if material == "Adamantite" and budget == 0:
				_check(result.win_rate >= 0.27 and result.win_rate <= 0.33, "Adamantite without healing stays near the 30% survival target")
			if material == "Runite" and budget == 800:
				_check(result.win_rate >= 0.97, "Runite with a fixed healing budget is safer")
