extends Node

var checks := 0
var failures: Array[String] = []

func _ready() -> void:
	_check_catalog()
	_check_unarmed()
	_check_bronze_styles()
	_check_melee_separation()
	_check_melee_baselines()
	_check_equipment()
	await _check_chase()
	print("[Bronze combat] %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr(label)

func _check_catalog() -> void:
	for item: Dictionary in GameData.items:
		for style: String in PlayerStats.ALL_STYLES:
			_check(item.attack_bonuses.has(style) and item.defence_bonuses.has(style), "%s: complete %s stats" % [item.name, style])
	var registered := GameData.register_item("Combat test weapon", "Weapon", "Test", 0, {
		"slot": "weapon", "attack_bonuses": {"blunt": 1},
		"combat_profiles": {"blunt": {"min_damage": 1, "max_damage": 3, "accuracy": 0.6}}
	})
	_check(registered.combat_profiles.blunt.max_damage == 3, "Dynamic registration retains profiles")

func _check_unarmed() -> void:
	var player := PlayerState.new("Unarmed")
	var stats := player.get_combat_stats()
	_check(stats.style == "blunt", "Unarmed uses blunt resistance")
	_check(stats.min_damage == 1 and stats.max_damage == 2, "Unarmed base damage 1–2")
	_check(stats.melee_strength_bonus == 0 and stats.melee_attack_roll == 576.0, "Unarmed has zero gear bonuses and a skill-based attack roll")
	_check(is_equal_approx(stats.attack_interval_seconds, 1.8), "Unarmed cadence 1.8 seconds")
	_check(stats.projectile_speed == 0.0, "Unarmed is not a projectile")
	_check(not player.set_attack_style("magic"), "Unarmed cannot launch magic autoattacks")
	_check_attack(player, "Unarmed")
	player.give_and_equip("Bronze Bow")
	player.unequip_slot("weapon")
	_check(player.get_combat_stats().style == "blunt", "Unequipping bow restores unarmed")
	_check_attack(player, "Unarmed after bow")

func _check_bronze_styles() -> void:
	var weapon_count := 0
	for item: Dictionary in GameData.items:
		if int(item.id) > 9 or item.type != "Weapon" or bool(item.get("legacy_placeholder", false)):
			continue
		weapon_count += 1
		var player := PlayerState.new(String(item.name))
		player.give_and_equip(item)
		for style: String in PlayerStats.valid_styles_for_weapon(item):
			_check(player.set_attack_style(style), "%s supports %s" % [item.name, style])
			var profile := PlayerStats.base_attack_profile(item, style)
			var base := player.get_combat_stats()
			if style in PlayerStats.MELEE_STYLES:
				_check(profile.is_empty(), "%s has no fixed melee damage profile" % item.name)
				_check(base.max_damage == PlayerStats.melee_max_hit(1, int(item.melee_strength_bonus)), "%s derives max hit from strength" % item.name)
			else:
				_check(not profile.is_empty(), "%s/%s retains existing base stats" % [item.name, style])
				_check(base.max_damage == int(profile.max_damage), "%s/%s level 1 max damage" % [item.name, style])
				_check(is_equal_approx(base.accuracy, float(profile.accuracy)), "%s/%s base accuracy" % [item.name, style])
			_check_attack(player, "%s/%s" % [item.name, style])
			for skill: String in ["attack", "strength", "range", "magic"]:
				player.set_skill_level(skill, 100)
			var trained := player.get_combat_stats()
			_check(trained.max_damage > base.max_damage, "%s/%s power grows" % [item.name, style])
			_check(trained.accuracy > base.accuracy, "%s/%s accuracy grows" % [item.name, style])
			for skill: String in ["attack", "strength", "range", "magic"]:
				player.set_skill_level(skill, 1)
			var previous := base
			for level in range(2, 101):
				for skill: String in ["attack", "strength", "range", "magic"]:
					player.set_skill_level(skill, level)
				var current := player.get_combat_stats()
				_check(current.max_damage >= previous.max_damage and current.accuracy >= previous.accuracy, "%s/%s monotonic growth at %d" % [item.name, style, level])
				previous = current
			for skill: String in ["attack", "strength", "range", "magic"]:
				player.set_skill_level(skill, 1)
	_check(weapon_count == 8, "Eight active starter weapon families checked after wand/staff consolidation")
	_check(int(GameData.get_item_by_name("Bronze Magic Wand").id) == 9 and GameData.get_item_by_name("Bronze Magic Wand").get("weapon_family", "") == "staff", "Historical wand is a legacy staff retaining its original ID and stats")

func _check_attack(player: PlayerState, label: String) -> void:
	var stats := player.get_combat_stats()
	var actor := CombatActor.new().configure({
		"entity_id": player.entity_id, "x": 10.0, "y": 10.0,
		"max_hp": player.get_max_hp(), "hp": player.current_hp,
		"attack_style": stats.style, "min_damage": stats.min_damage,
		"max_damage": stats.max_damage, "accuracy": stats.accuracy,
		"melee_attack_roll": stats.melee_attack_roll,
		"damage_roll_level": stats.damage_roll_level,
		"attack_interval_seconds": stats.attack_interval_seconds,
		"attack_range": stats.attack_range, "projectile_speed": stats.projectile_speed
	})
	var target := CombatActor.new().configure({
		"entity_id": "dummy", "x": 12.0, "y": 10.0,
		"max_hp": 10000, "is_monster": true
	})
	var engine := CombatEngine.new()
	engine.random.seed = 773
	engine.add_actor(actor)
	engine.add_actor(target)
	var world := {"player": player, "monsters": []}
	var health_xp_before := player.get_skill_experience("health")
	player.current_target = "dummy"
	var first := engine.process_realtime(world, 0.0)
	var is_projectile: bool = stats.style in ["ranged", "magic"]
	_check(first.size() > 0 and first[0].type == ("projectile_spawned" if is_projectile else "entity_hit"), label + " resolves correct attack path")
	var cooldown_events := engine._process_player_attacks(world, stats.attack_interval_seconds * 0.5)
	_check(cooldown_events.is_empty(), label + " honors cooldown")
	for attempt in range(30):
		engine.process_realtime(world, float(stats.attack_interval_seconds) + 0.01)
	_check(target.hp < target.max_hp, label + " actually damages target")
	_check(player.get_skill_experience("health") > health_xp_before, label + " awards damage XP")
	actor.attack_cooldown_seconds = 0.0
	target.x = actor.x + float(stats.attack_range) + 1.0
	_check(engine._process_player_attacks(world, 0.0).is_empty(), label + " cannot attack outside range")
	player.current_target = ""
	_check(engine._process_player_attacks(world, 0.0).is_empty(), label + " cannot attack without target")

func _check_equipment() -> void:
	var player := PlayerState.new("Armour")
	var naked := player.get_combat_stats()
	for suffix: String in ["Helmet", "Platebody", "Platelegs", "Kiteshield", "Cape"]:
		player.give_and_equip("Bronze " + suffix)
	var armoured := player.get_combat_stats()
	_check(armoured.resistances.slash > naked.resistances.slash, "Bronze armour reduces physical hit chance")
	_check(armoured.resistances.magic < naked.resistances.magic, "Metal armour has magic vulnerability")
	player.give_and_equip("Bronze Ring")
	_check(player.get_combat_stats().accuracy > armoured.accuracy, "Bronze jewelry improves accuracy")
	player.give_and_equip("Bronze Warmaul")
	_check(player.equipment.shield.is_empty(), "Warmaul requires both hands")
	player.give_and_equip("Bronze Kiteshield")
	_check(player.equipment.shield.is_empty(), "Shield cannot pair with warmaul")

func _check_melee_separation() -> void:
	var player := PlayerState.new("Melee separation")
	player.give_and_equip("Bronze Longsword")
	player.set_attack_style("slash")
	var base := player.get_combat_stats()
	player.set_attack_style("stab")
	var stabbing := player.get_combat_stats()
	_check(stabbing.max_damage == base.max_damage, "Style selection cannot change max hit")
	_check(stabbing.melee_attack_roll < base.melee_attack_roll, "Style accuracy uses the selected bonus")
	player.set_attack_style("slash")
	player.equipment.weapon = player.equipment.weapon.duplicate(true)
	player.equipment.weapon.attack_bonuses.slash += 100
	var accurate := player.get_combat_stats()
	_check(accurate.max_damage == base.max_damage, "Slash bonus cannot increase damage")
	_check(accurate.melee_attack_roll > base.melee_attack_roll, "Slash bonus raises attack roll")
	player.equipment.weapon.attack_bonuses.slash -= 100
	player.equipment.weapon.melee_strength_bonus += 64
	var powerful := player.get_combat_stats()
	_check(powerful.max_damage > base.max_damage, "Melee strength bonus raises max hit")
	_check(powerful.melee_attack_roll == base.melee_attack_roll, "Melee strength cannot increase accuracy")
	player.equipment.weapon.melee_strength_bonus -= 64
	player.set_skill_level("attack", 100)
	var skilled := player.get_combat_stats()
	_check(skilled.max_damage == base.max_damage and skilled.damage_roll_level == 0, "Attack skill cannot increase melee damage or bias its roll")
	_check(skilled.melee_attack_roll > base.melee_attack_roll, "Attack skill raises accuracy")
	player.set_skill_level("attack", 1)
	player.set_skill_level("strength", 100)
	var strong := player.get_combat_stats()
	_check(strong.max_damage > base.max_damage, "Strength skill raises max hit")
	_check(strong.melee_attack_roll == base.melee_attack_roll, "Strength skill cannot increase accuracy")
	player.set_skill_level("strength", 1)
	player.give_and_equip("Bronze Ring")
	var jewelry := player.get_combat_stats()
	_check(jewelry.max_damage == base.max_damage, "Accuracy-only jewelry does not increase melee damage")
	_check(jewelry.melee_attack_roll > base.melee_attack_roll, "Jewelry contributes to attack roll")
	var engine := CombatEngine.new()
	var attacker := CombatActor.new().configure({"attack_style": "slash", "melee_attack_roll": base.melee_attack_roll, "accuracy": 0.5})
	var target := CombatActor.new().configure({"defence_level": 1})
	var neutral := engine.calculate_hit_chance(attacker, target)
	target.defence_level = 50
	_check(engine.calculate_hit_chance(attacker, target) < neutral, "Target defence level reduces hit chance")
	target.defence_level = 1
	target.resistances = {"slash": 0.3, "stab": -0.1}
	_check(engine.calculate_hit_chance(attacker, target) < neutral, "Selected-style resistance reduces hit chance")
	attacker.attack_style = "stab"
	_check(engine.calculate_hit_chance(attacker, target) > neutral, "Target style weakness increases hit chance")
	attacker.attack_style = "slash"
	_check(is_equal_approx(engine.calculate_hit_chance(attacker, target, 0.5), 0.2), "Explicit accuracy override keeps its existing behavior")
	_check(is_equal_approx(engine.calculate_hit_chance(attacker, target, null, "magic"), 0.5), "Magic ignores the melee roll")
	var defender := PlayerState.new("Defender")
	var bare_defence := float(defender.get_combat_stats().melee_defence_rolls.slash)
	defender.give_and_equip("Bronze Platebody")
	_check(float(defender.get_combat_stats().melee_defence_rolls.slash) > bare_defence, "Armour contributes once to melee defence roll")
	defender.set_skill_level("defense", 50)
	_check(float(defender.get_combat_stats().melee_defence_rolls.slash) > bare_defence * 2.0, "Defence skill scales defence roll")
	var restored := CombatActor.new().configure(attacker.to_dictionary())
	_check(restored.melee_attack_roll == attacker.melee_attack_roll, "Actor serialization retains melee roll")
	_check(PlayerStats.melee_hit_chance(0.0, 1000.0) == 0.05, "Melee hit chance has a 5% floor")
	_check(PlayerStats.melee_hit_chance(1000000.0, 0.0) == 0.99, "Melee hit chance has a 99% ceiling")
	player.give_and_equip("Bronze Mace")
	_check(not player.set_attack_style("slash"), "Mace cannot slash")
	_check(player.set_attack_style("crush") and player.get_combat_stats().style == "blunt", "Crush selects the existing blunt damage channel")

func _check_melee_baselines() -> void:
	var baselines := {"Dagger": [3, 20, 37], "Shortsword": [4, 25, 47], "Longsword": [5, 33, 61], "Mace": [6, 36, 68], "Warmaul": [9, 58, 108]}
	for suffix: String in baselines:
		var player := PlayerState.new("Baseline")
		player.give_and_equip("Bronze " + suffix)
		for index in range(3):
			var level := int([1, 50, 100][index])
			player.set_skill_level("strength", level)
			_check(player.get_combat_stats().max_damage == int(baselines[suffix][index]), "%s documented max hit at Strength %d" % [suffix, level])

func _check_chase() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	scene.set_process(false)
	scene.set_physics_process(false)
	var actor: CombatActor = scene.combat.actors["player"]
	_check(actor.melee_attack_roll == float(scene.player.get_combat_stats().melee_attack_roll), "Live scene creates actor with melee roll")
	scene.player.give_and_equip("Bronze Dagger")
	scene._refresh_player_actor_from_player()
	_check(actor.melee_attack_roll == float(scene.player.get_combat_stats().melee_attack_roll), "Live equipment refresh synchronizes melee roll")
	var target := CombatActor.new().configure({"entity_id": "chase-dummy", "x": actor.x + 3.0, "y": actor.y, "max_hp": 100, "is_monster": true})
	scene.combat.add_actor(target)
	scene.player.current_target = target.entity_id
	scene.auto_chase_target = true
	scene._update_auto_chase(1.0)
	_check(CombatEngine.distance(actor, target) < actor.attack_range, "Chase enters attack range")
	target.x += 1.0
	scene._update_auto_chase(1.0)
	_check(CombatEngine.distance(actor, target) < actor.attack_range, "Chase follows moving target")
	scene.player.give_and_equip("Bronze Bow")
	scene._refresh_player_actor_from_player()
	_check(actor.melee_attack_roll < 0.0, "Equipping a bow clears the melee roll")
	target.x = actor.x + 10.0
	var before := Vector2(actor.x, actor.y)
	scene._update_auto_chase(1.0)
	_check(before == Vector2(actor.x, actor.y), "Bow chase respects ranged reach")
	scene.queue_free()
	await get_tree().process_frame
