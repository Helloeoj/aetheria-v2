class_name TextCombatDemo
extends RefCounted

func run_demo() -> void:
	var player := PlayerState.new("CLI Tester")
	player.set_level("attack", 25)
	player.set_level("strength", 25)
	player.entity_id = "player-%s" % str(Time.get_ticks_usec())
	var monster_id := int(GameData.get_monster_by_name("Goblin Scout").get("id", -1))
	if monster_id < 0:
		push_error("Goblin Scout not found in the monster database")
		return
	var monster := GameData.create_monster_instance(monster_id, player.x + 1, player.y)
	if monster == null:
		return
	monster.entity_id = "monster-%s" % str(Time.get_ticks_usec())

	var engine := CombatEngine.new()
	engine.random.seed = 1
	var combat_context := {"player": player}
	var player_actor := _as_actor(
		player.name, player.get_combat_stats(), player.entity_id, player.x, player.y
	)
	var monster_actor := _as_actor(
		monster.name, monster.get_combat_stats(), monster.entity_id,
		int(monster.x), int(monster.y), true, monster.damage_type
	)
	engine.add_actor(player_actor)
	engine.add_actor(monster_actor)

	_print_header("Aetheria Core — Text Combat Client")
	print("Player: %s" % str(player.summary()))
	print("Monster: %s" % str(monster.summary()))
	print()

	var player_turn: Array = engine.fight_turn(
		player_actor.entity_id, monster_actor.entity_id, combat_context
	)
	_print_header("Player Turn")
	print("%s hits %s for %d damage%s." % [
		player_actor.name, monster_actor.name, int(player_turn[0]),
		" (CRIT)" if bool(player_turn[1]) else ""
	])
	if bool(player_turn[2]):
		print("%s is defeated!" % monster_actor.name)
	else:
		var retaliation: Array = engine.fight_turn(
			monster_actor.entity_id, player_actor.entity_id, combat_context
		)
		_print_header("Monster Turn")
		print("%s hits back for %d damage%s." % [
			monster_actor.name, int(retaliation[0]),
			" (CRIT)" if bool(retaliation[1]) else ""
		])
		if bool(retaliation[2]):
			print("%s falls in battle." % player_actor.name)

	_print_header("Post-combat HP")
	print("%s: %d/%d" % [player_actor.name, player_actor.hp, player_actor.max_hp])
	print("%s: %d/%d" % [monster_actor.name, monster_actor.hp, monster_actor.max_hp])
	print("Skills: %s" % str(player.get_skills_progress()))

func _as_actor(actor_name: String, stats: Dictionary, entity_id: String,
		x: int, y: int, is_monster: bool = false,
		monster_attack_type: String = "") -> CombatActor:
	var health: Dictionary = stats.get("health", {})
	return CombatActor.new().configure({
		"entity_id": entity_id,
		"name": actor_name,
		"x": x,
		"y": y,
		"hp": int(health.get("current", 0)),
		"max_hp": int(health.get("max", 0)),
		"attack_style": String(stats.get("style", "slash")),
		"damage_roll_level": int(stats.get("damage_roll_level", 0)),
		"magic_level": int(stats.get("magic_level", 1)),
		"magic_accuracy": float(stats.get("magic_accuracy", 0.5)),
		"min_damage": int(stats.get("min_damage", 1)),
		"max_damage": int(stats.get("max_damage", 1)),
		"accuracy": float(stats.get("accuracy", 0.1)),
		"crit_chance": float(stats.get("crit_chance", 0.05)),
		"crit_multiplier": float(stats.get("crit_multiplier", 1.5)),
		"resistances": stats.get("resistances", {}).duplicate(true),
		"uses_armour_rating": bool(stats.get("uses_armour_rating", false)),
		"attack_speed": int(stats.get("attack_speed", 4)),
		"is_monster": is_monster,
		"monster_attack_type": monster_attack_type
	})

func _print_header(title: String) -> void:
	print("=".repeat(60))
	print(title)
	print("=".repeat(60))
