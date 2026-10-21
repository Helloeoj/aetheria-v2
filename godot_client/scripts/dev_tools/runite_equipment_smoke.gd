extends Node
## Run the matching scene to include the project's normal GameData autoload.
## Godot --headless --path godot_client res://scenes/dev_tools/runite_equipment_smoke.tscn

const WEAPON_STYLES := {
	"Dagger": "stab", "Shortsword": "slash", "Longsword": "slash",
	"Mace": "blunt", "Warmaul": "blunt", "Bow": "ranged",
	"Crossbow": "ranged", "Magic Staff": "magic", "Magic Wand": "magic"
}
const ARMOR_PIECES := ["Helmet", "Platebody", "Platelegs", "Kiteshield", "Square Shield", "Cape"]
const MATERIALS := ["Bronze", "Iron", "Steel", "Blacksteel", "Mithril", "Adamantite", "Runite"]

var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	_check_catalog_and_equipping()
	_check_weapon_progression()
	_check_armor_progression()
	_check_two_handed_equipment()
	_check_armour_rating_and_skills()
	_check_hit_models_and_combat()
	await _check_live_scene()
	if failures.is_empty():
		print("[Runite equipment] PASS: %d checks." % checks)
		get_tree().quit(0)
	else:
		printerr("[Runite equipment] FAIL: %d of %d checks." % [failures.size(), checks])
		get_tree().quit(1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("[Runite equipment] " + label)


func _equip_fixture(player: PlayerState, item_ref: Variant) -> void:
	var saved_levels := player.levels.duplicate(true)
	for skill: String in SkillProgression.SKILL_IDS:
		player.set_skill_level(skill, 100)
	var item := GameData.get_item(item_ref)
	var item_name := String(item.get("name", ""))
	if int(player.backpack.get(item_name, 0)) > 0:
		player.equip_item(item_name)
	else:
		player.give_and_equip(item_ref)
	for skill: String in SkillProgression.SKILL_IDS:
		player.set_skill_level(skill, int(saved_levels[skill]))


func _player_with_item(material: String, suffix: String, level: int = 100) -> PlayerState:
	var player := PlayerState.new("Equipment check")
	for skill: String in SkillProgression.SKILL_IDS:
		player.set_skill_level(skill, level)
	_equip_fixture(player, material + " " + suffix)
	if WEAPON_STYLES.has(suffix):
		player.attack_style = String(WEAPON_STYLES[suffix])
	return player


func _check_catalog_and_equipping() -> void:
	var ids := {}
	var names := {}
	var runite_count := 0
	var adamantite_count := 0
	for item: Dictionary in GameData.items:
		var item_id := int(item.get("id", -1))
		var item_name := String(item.get("name", ""))
		_check(not ids.has(item_id), "Unique item ID: %d" % item_id)
		_check(not names.has(item_name), "Unique item name: " + item_name)
		ids[item_id] = true
		names[item_name] = true
		if item_id >= 94 and item_id <= 111:
			adamantite_count += 1
		if item_id < 180 or item_id > 196:
			continue
		runite_count += 1
		_check(int(item.get("tier", 0)) == 7, item_name + " is Tier 7")
		_check(GameData.get_item(item_id) == item, item_name + " resolves by ID")
		var player := PlayerState.new("Slot check")
		_equip_fixture(player, item_id)
		var slot := String(item.get("slot", ""))
		if slot == "ring":
			slot = "ring1"
		var equipped: Dictionary = player.equipment.get(slot, {})
		_check(String(equipped.get("name", "")) == GameData.canonical_item_name(item_name), item_name + " equips in " + slot)
		_check(player.backpack.is_empty(), item_name + " moves out of the backpack")
	_check(runite_count == 17, "All 17 historical tier-7 item IDs are retained after migration")
	_check(runite_count == adamantite_count, "Every historical tier-6 item has its retained tier-7 counterpart")


func _check_weapon_progression() -> void:
	var engine := CombatEngine.new()
	engine.random.seed = 20261018
	for suffix: String in WEAPON_STYLES:
		for level: int in [50, 100]:
			var adamantite := _player_with_item("Adamantite", suffix, level)
			var runite := _player_with_item("Runite", suffix, level)
			var old_stats := adamantite.get_combat_stats()
			var new_stats := runite.get_combat_stats()
			var label := "%s at skill %d" % [suffix, level]
			_check(int(new_stats.max_damage) > int(old_stats.max_damage), label + " has a higher max hit")
			_check(int(new_stats.min_damage) >= int(old_stats.min_damage), label + " preserves the damage floor")
			_check(float(new_stats.accuracy) > float(old_stats.accuracy), label + " has higher weapon-only accuracy")
			_check(is_equal_approx(new_stats.attack_interval_seconds, old_stats.attack_interval_seconds), label + " preserves attack cadence")
			_check(is_equal_approx(new_stats.attack_range, old_stats.attack_range), label + " preserves weapon-class range")
			_check(is_equal_approx(new_stats.projectile_speed, old_stats.projectile_speed), label + " preserves projectile speed")
			print("[Runite equipment] %s: damage %d-%d -> %d-%d; accuracy %.3f -> %.3f" % [
				label, old_stats.min_damage, old_stats.max_damage, new_stats.min_damage,
				new_stats.max_damage, old_stats.accuracy, new_stats.accuracy
			])
			if level != 100:
				continue
			var attacker := CombatActor.new().configure({
				"entity_id": "runite-check", "hp": 100, "max_hp": 100,
				"min_damage": new_stats.min_damage, "max_damage": new_stats.max_damage,
				"accuracy": new_stats.accuracy, "attack_style": new_stats.style,
				"damage_roll_level": level, "crit_chance": 0.0
			})
			var dummy := CombatActor.new().configure({
				"entity_id": "dummy", "hp": 10000, "max_hp": 10000, "is_monster": true
			})
			var exceeded_old_max := false
			for _hit in range(256):
				var outcome := engine.calculate_hit_outcome(attacker, dummy)
				if outcome.hit:
					_check(outcome.damage <= int(new_stats.max_damage), label + " hit stays inside its max")
					exceeded_old_max = exceeded_old_max or outcome.damage > int(old_stats.max_damage)
			_check(exceeded_old_max, label + " produces real hits above Adamantite's max")
		var adamantite_jewelry := _player_with_item("Adamantite", suffix)
		var runite_jewelry := _player_with_item("Runite", suffix)
		for jewelry in ["Ring", "Ring", "Necklace"]:
			_equip_fixture(adamantite_jewelry, "Adamantite " + jewelry)
			_equip_fixture(runite_jewelry, "Runite " + jewelry)
		_check(runite_jewelry.get_combat_stats().max_damage > adamantite_jewelry.get_combat_stats().max_damage,
			suffix + " also improves with both rings and necklace equipped")


func _check_armor_progression() -> void:
	for suffix: String in ARMOR_PIECES:
		var adamantite := _player_with_item("Adamantite", suffix, 50)
		var runite := _player_with_item("Runite", suffix, 50)
		var old_stats := adamantite.get_combat_stats()
		var new_stats := runite.get_combat_stats()
		for style in ["slash", "stab", "blunt", "ranged"]:
			_check(float(new_stats.resistances[style]) > float(old_stats.resistances[style]),
				suffix + " improves mixed-loadout " + style + " defense")
		_check(float(new_stats.resistances.magic) >= float(old_stats.resistances.magic),
			suffix + " does not worsen magic defense")
	var engine := CombatEngine.new()
	for level: int in [1, 50, 100]:
		for shield: String in ["", "Square Shield", "Kiteshield"]:
			var previous: CombatActor
			for material: String in MATERIALS:
				var target := _target_from_player(_armoured_player(material, level, shield))
				_check(target.uses_armour_rating, material + " carries its armor model into combat")
				for style: String in PlayerStats.ALL_STYLES:
					_check(float(target.resistances[style]) < PlayerStats.MAX_ARMOUR_RESISTANCE,
						material + " standard armor stays below the defense ceiling")
					if previous == null:
						continue
					_check(float(target.resistances[style]) > float(previous.resistances[style]),
						"Full %s improves %s defense at level %d, shield '%s'" % [material, style, level, shield])
					for accuracy: float in [0.3, 0.9]:
						var attacker := {"accuracy": accuracy, "attack_style": style}
						var old_chance := engine.calculate_hit_chance(attacker, previous)
						var new_chance := engine.calculate_hit_chance(attacker, target)
						var bounded := is_equal_approx(new_chance, CombatEngine.MIN_HIT_CHANCE) or is_equal_approx(new_chance, CombatEngine.MAX_HIT_CHANCE)
						_check(new_chance < old_chance or (bounded and is_equal_approx(new_chance, old_chance)),
							material + " reduces incoming " + style + " hit chance unless already at a hit-chance bound")
				if level == 100 and shield == "Kiteshield":
					print("[Armor progression] %s: slash resistance %.4f, incoming hit chance %.4f at enemy accuracy 0.30" % [
						material, target.resistances.slash,
						engine.calculate_hit_chance({"accuracy": 0.3, "attack_style": "slash"}, target)
					])
				previous = target
		for suffix: String in ARMOR_PIECES:
			var shield := "Square Shield" if suffix == "Square Shield" else "Kiteshield"
			var player := _armoured_player("Adamantite", level, shield)
			var before := player.get_combat_stats()
			_equip_fixture(player, "Runite " + suffix)
			var after := player.get_combat_stats()
			for style in ["slash", "stab", "blunt", "ranged"]:
				_check(float(after.resistances[style]) > float(before.resistances[style]),
					"One Runite " + suffix + " improves a full Adamantite set's " + style + " defense")
			var slot := String(GameData.get_item_by_name("Runite " + suffix).slot)
			player.unequip_slot(slot)
			_equip_fixture(player, "Adamantite " + suffix)
			for style: String in PlayerStats.ALL_STYLES:
				_check(is_equal_approx(player.get_combat_stats().resistances[style], before.resistances[style]),
					"Removing Runite " + suffix + " restores the previous " + style + " defense")


func _armoured_player(material: String, level: int, shield: String) -> PlayerState:
	var player := PlayerState.new("Armor check")
	for skill: String in SkillProgression.SKILL_IDS:
		player.set_skill_level(skill, level)
	for suffix in ["Helmet", "Platebody", "Platelegs", "Cape"]:
		_equip_fixture(player, material + " " + suffix)
	if not shield.is_empty():
		_equip_fixture(player, material + " " + shield)
	return player


func _target_from_player(player: PlayerState) -> CombatActor:
	var stats := player.get_combat_stats()
	return CombatActor.new().configure({
		"entity_id": "armor-target", "hp": 10000, "max_hp": 10000,
		"resistances": stats.resistances, "uses_armour_rating": stats.uses_armour_rating
	})


func _check_armour_rating_and_skills() -> void:
	_check(is_equal_approx(PlayerStats.armour_resistance_from_rating(0.0), 0.0), "Zero rating has no resistance")
	_check(is_equal_approx(PlayerStats.armour_resistance_from_rating(1.0), 0.5), "Rating one yields half resistance")
	_check(is_equal_approx(PlayerStats.armour_resistance_from_rating(3.0), 0.75), "Ratings have diminishing returns")
	for rating: float in [-10000.0, -2.0, -1.0, -0.25, 0.0, 4.0, 10000.0]:
		var resistance := PlayerStats.armour_resistance_from_rating(rating)
		_check(is_finite(resistance) and resistance >= -0.5 and resistance <= 0.8,
			"Extreme ratings stay finite and bounded")
	var raw := PlayerStats.aggregate_defence_bonuses([
		{"defence_bonuses": {"slash": 0.6}}, {"defence_bonuses": {"slash": 0.6}}
	])
	_check(is_equal_approx(raw.slash, 1.2), "Raw item ratings are not capped or converted early")
	var player := _armoured_player("Adamantite", 1, "Kiteshield")
	var initial := player.get_combat_stats()
	_check(float(initial.resistances.magic) < 0.0, "Low-Magic metal armor retains its magic vulnerability")
	player.set_skill_level("defense", 100)
	var defense_only := player.get_combat_stats()
	_check(float(defense_only.resistances.slash) > float(initial.resistances.slash), "Defense skill adds physical protection")
	_check(is_equal_approx(defense_only.resistances.magic, initial.resistances.magic), "Defense skill does not add magic protection")
	player.set_skill_level("magic", 100)
	var both := player.get_combat_stats()
	_check(float(both.resistances.magic) > 0.0, "Magic skill offsets armor vulnerability before conversion")
	_check(is_equal_approx(both.resistances.slash, defense_only.resistances.slash), "Magic skill does not add physical protection")
	var unarmoured := PlayerState.new("Unarmored check")
	unarmoured.set_skill_level("defense", 100)
	_check(is_equal_approx(unarmoured.get_combat_stats().resistances.slash, 0.2), "Unarmored skill defense converts only once")


func _check_hit_models_and_combat() -> void:
	var engine := CombatEngine.new()
	var attacker := {"accuracy": 0.8, "attack_style": "slash", "crit_chance": 0.0}
	var flat_target := {"resistances": {"slash": 0.5}}
	var armour_target := {"resistances": {"slash": 0.5}, "uses_armour_rating": true}
	_check(is_equal_approx(engine.calculate_hit_chance(attacker, flat_target), 0.3), "Legacy/NPC dictionaries retain subtraction")
	_check(is_equal_approx(engine.calculate_hit_chance(attacker, armour_target), 0.4), "Player armor reduces a fraction of incoming accuracy")
	var npc := CombatActor.new().configure({"is_monster": true, "resistances": {"slash": 0.5}})
	_check(not npc.uses_armour_rating and is_equal_approx(engine.calculate_hit_chance(attacker, npc), 0.3),
		"Monster actors retain their authored resistance behavior")
	_check(is_equal_approx(engine.calculate_hit_chance(attacker, armour_target, 0.01), 0.05), "Minimum hit chance remains enforced")
	_check(is_equal_approx(engine.calculate_hit_chance(attacker,
		{"resistances": {"slash": -0.5}, "uses_armour_rating": true}, 1.0), 0.99), "Maximum hit chance remains enforced")
	var projectile := CombatProjectile.new().configure({"accuracy": 0.8, "damage_type": "fire"})
	var spell_target := {"resistances": {"magic": 0.25, "slash": 0.0}, "uses_armour_rating": true}
	_check(is_equal_approx(engine.calculate_hit_chance(projectile, spell_target, projectile.accuracy, projectile.damage_type), 0.6),
		"Elemental projectile uses its actual target's magic armor model")
	var old_target := _target_from_player(_armoured_player("Adamantite", 100, "Kiteshield"))
	var new_target := _target_from_player(_armoured_player("Runite", 100, "Kiteshield"))
	for accuracy: float in [0.3, 0.9]:
		attacker.accuracy = accuracy
		var old_hits := 0
		var new_hits := 0
		var nested_hits := true
		var damage_preserved := true
		for attack_index in range(10000):
			engine.random.seed = 20261018 + attack_index
			var old_outcome := engine.calculate_hit_outcome(attacker, old_target, 10)
			engine.random.seed = 20261018 + attack_index
			var new_outcome := engine.calculate_hit_outcome(attacker, new_target, 10)
			old_hits += int(old_outcome.hit)
			new_hits += int(new_outcome.hit)
			nested_hits = nested_hits and (not new_outcome.hit or old_outcome.hit)
			damage_preserved = damage_preserved and (not new_outcome.hit or new_outcome.damage == 10)
		_check(new_hits < old_hits and nested_hits, "Full Runite prevents additional real incoming hits")
		_check(damage_preserved, "Armor changes hit frequency rather than landed-hit damage")
		_check(absf(float(old_hits) / 10000.0 - engine.calculate_hit_chance(attacker, old_target)) < 0.015, "Adamantite real hit rate matches its probability")
		_check(absf(float(new_hits) / 10000.0 - engine.calculate_hit_chance(attacker, new_target)) < 0.015, "Runite real hit rate matches its probability")
		print("[Armor combat] Enemy accuracy %.2f: Adamantite %d hits, Runite %d hits out of 10000 paired attacks." % [accuracy, old_hits, new_hits])


func _check_live_scene() -> void:
	# Leave the test scene's initial tree setup before adding another scene.
	await get_tree().process_frame
	var packed := load("res://scenes/EastOutskirtsLayered.tscn") as PackedScene
	var map_scene := packed.instantiate()
	get_tree().root.add_child(map_scene)
	await get_tree().process_frame
	var game: Node = map_scene.get_node("Combat")
	var actor: CombatActor = game.combat.actors.get(game.player.entity_id)
	_check(actor != null and actor.uses_armour_rating, "Actual game player receives the armor model on creation")
	game.player.set_skill_level("defense", 100)
	for suffix in ["Helmet", "Platebody", "Platelegs", "Kiteshield", "Cape"]:
		_equip_fixture(game.player, "Runite " + suffix)
	game._refresh_player_actor_from_player()
	var expected: Dictionary = game.player.get_combat_stats()
	_check(actor.uses_armour_rating and is_equal_approx(actor.resistances.slash, expected.resistances.slash),
		"Equipment refresh transfers calculated armor protection to the game actor")
	_check(actor.to_dictionary().get("uses_armour_rating", false), "Actor serialization preserves the armor model")
	map_scene.queue_free()
	await get_tree().process_frame


func _check_two_handed_equipment() -> void:
	for suffix in ["Warmaul", "Bow", "Magic Staff"]:
		var player := _player_with_item("Runite", "Kiteshield")
		_equip_fixture(player, "Runite " + suffix)
		_check(player.equipment.shield.is_empty(), suffix + " returns the equipped shield to inventory")
		_check(int(player.backpack.get(GameData.canonical_item_name("Runite Kiteshield"), 0)) == 1, suffix + " preserves the shield item")
		player.equip_item("Runite Kiteshield")
		_check(player.equipment.shield.is_empty(), suffix + " rejects equipping an incompatible shield")
