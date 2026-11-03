extends Node

var checks := 0
var failures: Array[String] = []

func _ready() -> void:
	_check_skills()
	_check_armour()
	_check_accuracy_and_damage()
	_check_projectiles()
	await _check_runtime()
	print("[Combat triangle] %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr(message)

func _player(gear: Array[String] = [], level: int = 100) -> PlayerState:
	var player := PlayerState.new("Triangle")
	for skill: String in SkillProgression.SKILL_IDS:
		player.set_skill_level(skill, level)
	for item: String in gear:
		player.give_and_equip(item)
	return player

func _actor(player: PlayerState, id: String = "target") -> CombatActor:
	var data := player.get_combat_stats().duplicate(true)
	data.merge({"entity_id": id, "attack_style": data.style, "hp": 100000, "max_hp": 100000}, true)
	return CombatActor.new().configure(data)

func _check_skills() -> void:
	var player := _player([], 1)
	var base := player.get_combat_stats()
	player.set_skill_level("magic", 11)
	var magic := player.get_combat_stats()
	player.set_skill_level("magic", 1)
	player.set_skill_level("defense", 11)
	var defence := player.get_combat_stats()
	var magic_gain := float(magic.get("magic_defence_roll", 0.0)) - float(base.get("magic_defence_roll", 0.0))
	var defence_gain := float(defence.get("magic_defence_roll", 0.0)) - float(base.get("magic_defence_roll", 0.0))
	_check(magic_gain > 0.0 and is_equal_approx(magic_gain / 7.0, defence_gain / 3.0), "Magic defence uses the 70/30 skill split exactly once")
	_check(is_equal_approx(float(base.get("magic_defence_roll", 0.0)), 576.0), "Naked level-one magic defence roll is 576")
	_check(is_equal_approx(float(magic.get("ranged_defence_roll", 0.0)), float(base.get("ranged_defence_roll", 0.0))), "Magic training does not protect against arrows")
	_check(float(defence.get("ranged_defence_roll", 0.0)) > float(base.get("ranged_defence_roll", 0.0)), "Defence training protects against arrows")
	var enemy := MonsterState.new({"level": 140, "skills": {"magic": 120, "defense": 50}, "max_hp": 10})
	var enemy_actor := CombatActor.new().configure(enemy.get_combat_stats().merged({"is_monster": true}))
	_check(enemy_actor.magic_level == 120, "Monster Magic is authored independently and is not capped at player level 100")
	_check(is_equal_approx(float(enemy.get_combat_stats().get("magic_defence_roll", 0.0)), 128.0 * 64.0), "Monster magic defence uses Magic rather than physical Defence")

func _check_armour() -> void:
	var leather := GameData.get_item_by_name("Tanned Leather Tunic")
	var bronze := GameData.get_item_by_name("Bronze Platebody")
	_check(float(leather.defence_bonuses.magic) > 0.0, "Leather protects against magic")
	_check(float(leather.defence_bonuses.slash) < float(bronze.defence_bonuses.slash), "Leather sacrifices melee defence compared with same-tier plate")
	_check(float(leather.defence_bonuses.ranged) < float(bronze.defence_bonuses.ranged), "Same-tier plate protects better against arrows than leather")
	var mage := GameData.get_item_by_name("Starlight Shroud Robe")
	var ranger := GameData.get_item_by_name("Galehunter’s Garb Vest")
	var plate := GameData.get_item_by_name("Titanbound Plate Cuirass")
	_check(float(ranger.defence_bonuses.magic) > float(mage.defence_bonuses.magic) and float(mage.defence_bonuses.magic) > float(plate.defence_bonuses.magic), "Equal-tier magic protection ranks ranged, robes, plate")
	for channel: String in ["stab", "slash", "blunt", "ranged"]:
		_check(float(plate.defence_bonuses[channel]) > float(ranger.defence_bonuses[channel]) and float(ranger.defence_bonuses[channel]) > float(mage.defence_bonuses[channel]), "Equal-tier physical protection ranks plate, ranged, robes: " + channel)
	_check(int(mage.attack_bonuses.magic) > 0 and int(ranger.attack_bonuses.ranged) > 0, "Robes and ranged armour support their attacks")
	_check(int(plate.attack_bonuses.magic) < 0 and int(plate.attack_bonuses.ranged) < 0, "Plate penalises casting and shooting")
	_check(int(ranger.attack_bonuses.magic) < 0, "Ranged armour penalises casting")
	_check(float(mage.get("magic_damage_bonus", 0.0)) > 0.0, "Robes explicitly boost magic damage separately from accuracy")

func _check_accuracy_and_damage() -> void:
	var engine := CombatEngine.new()
	var ranger := _player(["Bronze Bow"])
	var source := _actor(ranger, "ranger")
	source.crit_chance = 0.0
	var low := _actor(_player([], 1))
	var high := _actor(_player())
	_check(engine.calculate_hit_chance(source, low) > engine.calculate_hit_chance(source, high), "Player ranged accuracy compares against target Defence")
	var mage := _player(["Bronze Magic Staff"])
	var caster := _actor(mage, "mage")
	_check(engine.calculate_hit_chance(caster, low) > engine.calculate_hit_chance(caster, high), "Player magic accuracy compares against target Magic and Defence")
	var bare := _actor(_player())
	var plate := _actor(_player(["Bronze Helmet", "Bronze Platebody", "Bronze Platelegs"]))
	var cloth := _actor(_player(["Starlight Shroud Hood", "Starlight Shroud Robe", "Starlight Shroud Wraps"]))
	_check(engine.calculate_hit_chance(source, cloth) > engine.calculate_hit_chance(source, plate), "Arrows land more often against robes than plate")
	_check(engine.calculate_hit_chance(caster, plate) > engine.calculate_hit_chance(caster, bare), "Plate remains a magic liability even with trained Magic")
	var bare_hits := 0
	var plate_hits := 0
	var landed_damage_unchanged := true
	for index in range(400):
		engine.random.seed = 5700 + index
		var unarmoured := engine.calculate_hit_outcome(source, bare, 20)
		engine.random.seed = 5700 + index
		var armoured := engine.calculate_hit_outcome(source, plate, 20)
		bare_hits += int(unarmoured.hit)
		plate_hits += int(armoured.hit)
		landed_damage_unchanged = landed_damage_unchanged and (not armoured.hit or armoured.damage == 20)
	_check(plate_hits < bare_hits and landed_damage_unchanged, "Actual seeded arrows hit plate less often without new damage absorption")
	var spell := {"damage": 100}
	var base_max := engine._get_spell_max_damage(caster, spell)
	mage.give_and_equip("Starlight Shroud Robe")
	var robed := _actor(mage)
	_check(engine._get_spell_max_damage(robed, spell) > base_max, "Robes boost actual selected spell damage")
	_check(robed.max_damage > caster.max_damage, "Robes also boost automatic magic damage")
	var robed_stats := mage.get_combat_stats()
	mage.give_and_equip("Bronze Longsword")
	var melee := mage.get_combat_stats()
	_check(mage.get_magic_level() == 100 and float(melee.get("magic_attack_roll", -1.0)) > 0.0 and float(melee.get("magic_defence_roll", -1.0)) == float(robed_stats.get("magic_defence_roll", -2.0)), "Switching weapons keeps independently trained spell accuracy")
	_check(float(melee.melee_attack_roll) >= 0.0, "Switching to melee immediately restores its attack roll")
	var golem := {"resistances": {}, "damage_reductions": {"ranged": 0.5}}
	engine.random.seed = 1
	var outcome := engine.calculate_hit_outcome(source, golem, 20, 0.99)
	_check(outcome.hit and outcome.damage == 10, "Existing explicit monster absorption remains separate")
	_check(is_equal_approx(engine.calculate_hit_chance({"accuracy": 0.8, "attack_style": "magic"}, {"resistances": {"magic": 0.25}, "uses_armour_rating": true}), 0.6), "Legacy authored accuracy remains supported")

func _check_projectiles() -> void:
	var engine := CombatEngine.new()
	var player := _player(["Bronze Bow"])
	var shooter := _actor(player, "shooter")
	var target := _actor(_player([], 1), "target")
	shooter.x = 0.0
	target.x = 2.0
	engine.add_actor(shooter)
	engine.add_actor(target)
	var projectile := engine._spawn_projectile(shooter, target)
	var captured := float(projectile.get("attack_roll")) if "attack_roll" in projectile else -1.0
	_check(captured > 0.0, "Projectile captures an offensive attack roll at launch")
	var before := engine.calculate_hit_chance(projectile, target, null, projectile.damage_type)
	target.configure(_actor(_player(), "target").to_dictionary())
	var after := engine.calculate_hit_chance(projectile, target, null, projectile.damage_type)
	_check(before > after, "Projectile uses current target defences at impact")
	player.give_and_equip("Bronze Longsword")
	shooter.configure(_actor(player, "shooter").to_dictionary())
	_check(captured > 0.0 and (float(projectile.get("attack_roll")) if "attack_roll" in projectile else -1.0) == captured, "Swapping weapons cannot alter an in-flight arrow")
	var spell_projectile := engine._spawn_spell_projectile(shooter, target, {"id": "triangle-test", "damage": 10, "school": "fire"})
	_check((float(spell_projectile.get("attack_roll")) if "attack_roll" in spell_projectile else -1.0) > 0.0, "Elemental spell captures magic accuracy even while wielding a sword")
	# Exercise the actual swept-collision impact path against an intervening actor.
	engine.projectiles.clear()
	shooter.x = 0.0
	target.x = 4.0
	var blocker := _actor(_player(["Bronze Helmet", "Bronze Platebody", "Bronze Platelegs"]), "blocker")
	blocker.x = 2.0
	engine.add_actor(blocker)
	var actual_impacts_match := true
	for style: String in ["ranged", "magic", "fire"]:
		for seed_index in range(12):
			var shot := engine._spawn_spell_projectile(shooter, target, {"damage": 20, "school": style}) if style != "ranged" else engine._spawn_projectile(_actor(_player(["Bronze Bow"]), "shooter"), target)
			engine.random.seed = 9100 + seed_index
			var expected := engine.calculate_hit_outcome(shot, blocker, shot.damage, null, style)
			engine.random.seed = 9100 + seed_index
			var events := engine._process_projectiles({}, 0.3)
			var impacts: Array = events.filter(func(event: Dictionary) -> bool: return event.type == "projectile_hit")
			actual_impacts_match = actual_impacts_match and impacts.size() == 1
			if impacts.size() == 1:
				actual_impacts_match = actual_impacts_match and impacts[0].target_id == "blocker" and bool(impacts[0].hit) == expected.hit and int(impacts[0].damage) == expected.damage
	_check(actual_impacts_match, "Actual ranged, magic and elemental collisions use captured rolls against the actor struck")
	var snapshot := CombatActor.new().configure(shooter.to_dictionary())
	_check(float(snapshot.get("magic_attack_roll")) > 0.0 if "magic_attack_roll" in snapshot else false, "Actor serialization retains independent magic attack roll")

func _check_runtime() -> void:
	var main_scene := load("res://scenes/Main.tscn") as PackedScene
	var game := main_scene.instantiate()
	get_tree().root.add_child.call_deferred(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var player := _player(["Bronze Bow"])
	var stats := player.get_combat_stats()
	var actor: CombatActor = game._create_actor_from_stats("triangle-runtime", "Triangle", 5.0, 5.0, stats)
	_check(float(actor.get("ranged_attack_roll")) > 0.0 if "ranged_attack_roll" in actor else false, "Real game actor adapter carries ranged roll")
	var old_player: PlayerState = game.player
	game.player = player
	game.combat.add_actor(_actor(player, player.entity_id))
	player.give_and_equip("Bronze Magic Staff")
	game._refresh_player_actor_from_player()
	var refreshed: CombatActor = game.combat.actors[player.entity_id]
	_check(float(refreshed.get("magic_attack_roll")) > 0.0 if "magic_attack_roll" in refreshed else false, "Real equipment refresh carries magic roll")
	game.player = old_player
	game.queue_free()
	await get_tree().process_frame
