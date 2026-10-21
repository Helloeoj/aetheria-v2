class_name CombatSmokeDemo
extends RefCounted

func run_demo() -> void:
	var engine := CombatEngine.new()
	var player := PlayerState.new("SmokeTester")
	player.entity_id = "player-1"
	player.give_and_equip("Bronze Shortsword")
	var player_actor := _build_player_actor(player)
	var monster_state := MonsterState.new({
		"id": -1,
		"name": "Training Dummy",
		"tier": 1,
		"level": 1,
		"max_hp": 60,
		"min_damage": 3,
		"max_damage": 7,
		"damage_type": "slash",
		"accuracy": 0.5,
		"resistances": {"slash": 0.1},
		"attack_speed": 5,
		"crit_chance": 0.05,
		"crit_multiplier": 1.5
	}, 12.0, 10.0)
	monster_state.entity_id = "mob-1"
	var monster_actor := _build_monster_actor("Training Dummy", "mob-1", 12, 10)
	engine.add_actor(player_actor)
	engine.add_actor(monster_actor)
	var monsters: Array[MonsterState] = [monster_state]
	var world := WorldState.new(player, monsters)
	player.current_target = monster_actor.entity_id

	print("Starting smoke loop...\n")
	for tick in range(10):
		var events := engine.process_tick(world)
		print("Tick %d: %s" % [tick, str(events)])
		if monster_actor.hp <= 0 or player_actor.hp <= 0:
			break
	print("\nSmoke test complete.")

func _build_player_actor(player: PlayerState) -> CombatActor:
	var stats := player.get_combat_stats()
	var health: Dictionary = stats.health
	return CombatActor.new().configure({
		"entity_id": player.entity_id,
		"name": player.name,
		"x": player.x,
		"y": player.y,
		"hp": health.current,
		"max_hp": health.max,
		"attack_style": stats.style,
		"damage_roll_level": stats.damage_roll_level,
		"magic_level": stats.magic_level,
		"magic_accuracy": stats.magic_accuracy,
		"min_damage": stats.min_damage,
		"max_damage": stats.max_damage,
		"accuracy": stats.accuracy,
		"crit_chance": stats.crit_chance,
		"crit_multiplier": stats.crit_multiplier,
		"resistances": stats.resistances,
		"uses_armour_rating": bool(stats.get("uses_armour_rating", false)),
		"attack_speed": stats.attack_speed,
		"is_monster": false
	})

func _build_monster_actor(actor_name: String, entity_id: String, x: int, y: int) -> CombatActor:
	return CombatActor.new().configure({
		"entity_id": entity_id,
		"name": actor_name,
		"x": x,
		"y": y,
		"hp": 60,
		"max_hp": 60,
		"attack_style": "slash",
		"min_damage": 3,
		"max_damage": 7,
		"accuracy": 0.5,
		"crit_chance": 0.05,
		"crit_multiplier": 1.5,
		"resistances": {"slash": 0.1},
		"attack_speed": 5,
		"is_monster": true,
		"monster_attack_type": "slash"
	})
