extends Node
## Verify real food consumption, shared action timing, and the expanded catch pool.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("[Fish food FAIL] ", description)

func _ready() -> void:
	var eater := PlayerState.new()
	eater.set_skill_level("health", 100)
	for name: String in FishingSession.FISH:
		eater.current_hp = 1000
		eater.food_cooldown_seconds = 0.0
		eater.food_attack_cooldown_seconds = 0.0
		eater.add_item(name)
		var heal := int(GameData.get_item_by_name(name).food_healing)
		check(FishingSession.eat(eater, name) == heal and eater.current_hp == 1000 + heal,
			name + " heals its authored amount without a Fishing requirement to eat")
		check(not eater.backpack.has(name), name + " consumes exactly one fish")
	var engine := CombatEngine.new()
	var world := {"player": eater, "monsters": []}
	eater.add_item("Reedkip", 2)
	eater.add_item("Sunfish")
	eater.current_hp = eater.get_max_hp()
	eater.food_cooldown_seconds = 0.0
	eater.food_attack_cooldown_seconds = 0.0
	check(FishingSession.eat(eater, "Reedkip") == 0 and eater.backpack["Reedkip"] == 2
		and eater.food_cooldown_seconds == 0.0, "Full health consumes no food and starts no cooldown")
	eater.current_hp -= 5
	check(FishingSession.eat(eater, "Reedkip") == 5 and eater.current_hp == eater.get_max_hp()
		and eater.backpack["Reedkip"] == 1, "Overhealing is capped and spends one fish")
	eater.current_hp -= 500
	check(FishingSession.eat(eater, "Sunfish") == 0 and eater.backpack.has("Sunfish"),
		"Switching species cannot bypass the shared eating cooldown")
	engine.process_realtime(world, FishingSession.EATING_COOLDOWN_SECONDS)
	check(FishingSession.eat(eater, "Sunfish") == 440, "A different fish can be eaten after the cooldown")
	eater.current_hp = 0
	check(FishingSession.eat(eater, "Reedkip") == 0 and eater.backpack["Reedkip"] == 1,
		"Food cannot revive dead players")
	_check_weapon_delays()
	var session := FishingSession.new(PlayerState.new())
	session.bait = "Low Grade Fish Food"
	session.distance = 200.0
	session.rng.seed = 723
	var respects_level := true
	for draw in range(100):
		respects_level = respects_level and int(session._roll_fish().fishing_level) <= 1
	check(respects_level, "Beginner catch selection respects unlocks")
	session.player.set_skill_level("fishing", 100)
	session.bait = "High Grade Fish Food"
	session.cast_power = 1.0
	var seen := {}
	for bait_name: String in FishingSession.BAITS:
		session.bait = bait_name
		for draw in range(2000):
			seen[session._roll_fish().name] = true
	check(seen.size() == 10, "All ten species are reachable in the real catch pool")
	var loot := LootSystem.new()
	var fish_excluded := true
	for tier in range(1, 11):
		for item: Dictionary in loot._tier_pools(tier).general:
			fish_excluded = fish_excluded and String(item.name) not in FishingSession.FISH
	check(fish_excluded, "Fishing species stay out of generic monster loot")
	print("[Fish food] %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func food_fixture(weapon_name: String, remaining: float = 0.6) -> Dictionary:
	var eater := PlayerState.new()
	eater.set_skill_level("health", 100)
	eater.current_hp = 1000
	eater.current_target = "food_dummy"
	if not weapon_name.is_empty():
		eater.equipment["weapon"] = GameData.get_item_by_name(weapon_name)
	eater.add_item("Reedkip", 5)
	var stats := eater.get_combat_stats()
	var actor := CombatActor.new().configure({"entity_id": eater.entity_id,
		"hp": eater.current_hp, "max_hp": eater.get_max_hp(), "attack_style": stats.style,
		"attack_range": 10.0, "attack_interval_seconds": stats.attack_interval_seconds,
		"attack_cooldown_seconds": remaining, "projectile_speed": stats.projectile_speed})
	var target := CombatActor.new().configure({"entity_id": "food_dummy",
		"x": 1.0, "hp": 10000, "max_hp": 10000, "is_monster": true})
	var engine := CombatEngine.new()
	engine.add_actor(actor)
	engine.add_actor(target)
	return {"player": eater, "actor": actor, "engine": engine,
		"world": {"player": eater, "monsters": []}, "interval": float(stats.attack_interval_seconds)}

func _check_weapon_delays() -> void:
	for weapon_name: String in ["", "Bronze Dagger", "Bronze Shortsword", "Bronze Longsword",
			"Bronze Mace", "Bronze Warmaul", "Bronze Bow", "Bronze Crossbow",
			"Bronze Magic Wand", "Bronze Magic Staff"]:
		var fixture := food_fixture(weapon_name)
		var eater: PlayerState = fixture.player
		var actor: CombatActor = fixture.actor
		var engine: CombatEngine = fixture.engine
		var interval := float(fixture.interval)
		var label := "Unarmed" if weapon_name.is_empty() else weapon_name
		check(FishingSession.eat(eater, "Reedkip", engine) == 40 and actor.hp == eater.current_hp,
			label + " food heals immediately")
		check(is_equal_approx(actor.attack_cooldown_seconds, 0.6 + interval),
			label + " food adds its actual weapon interval and preserves the remaining timer")
		check(engine.process_realtime(fixture.world, interval).is_empty(), label + " cannot attack during the food penalty")
		check(engine.process_realtime(fixture.world, 0.5).is_empty(), label + " retains its original remaining wait")
		check(not engine.process_realtime(fixture.world, 0.11).is_empty(), label + " attacks resume only after both waits")
	# Equip a slow weapon just before eating, while the actor still has cached fast stats.
	var fixture := food_fixture("Bronze Dagger", 0.7)
	var eater: PlayerState = fixture.player
	var actor: CombatActor = fixture.actor
	var engine: CombatEngine = fixture.engine
	eater.equipment["weapon"] = GameData.get_item_by_name("Bronze Warmaul")
	check(FishingSession.eat(eater, "Reedkip", engine) == 40 and is_equal_approx(actor.attack_cooldown_seconds, 3.7),
		"Eating reads current equipment rather than stale actor speed")
	eater.equipment["weapon"] = GameData.get_item_by_name("Bronze Dagger")
	actor.attack_interval_seconds = 1.35
	check(engine.process_realtime(fixture.world, 0.5).is_empty() and is_equal_approx(actor.attack_cooldown_seconds, 3.2),
		"Switching to a faster weapon cannot shorten the pending food delay")
	# A slower weapon selected during the pending food penalty extends it once.
	fixture = food_fixture("Bronze Dagger", 0.4)
	eater = fixture.player
	actor = fixture.actor
	engine = fixture.engine
	FishingSession.eat(eater, "Reedkip", engine)
	engine.process_realtime(fixture.world, 0.2)
	eater.equipment["weapon"] = GameData.get_item_by_name("Bronze Warmaul")
	actor.attack_interval_seconds = 3.0
	engine.process_realtime(fixture.world, 0.0)
	check(is_equal_approx(actor.attack_cooldown_seconds, 3.2), "Switching to a slower weapon extends the pending food interval")
	engine.process_realtime(fixture.world, 0.0)
	check(is_equal_approx(actor.attack_cooldown_seconds, 3.2), "Refreshing the same weapon does not repeatedly extend the food delay")
	actor.attack_cooldown_seconds = 0.0
	check(engine.process_realtime(fixture.world, 0.0).is_empty() and is_equal_approx(actor.attack_cooldown_seconds, 3.2),
		"Recreating or refreshing an actor cannot clear the player's pending food lock")
	engine.process_realtime(fixture.world, 1.8)
	check(is_zero_approx(eater.food_cooldown_seconds) and eater.food_attack_cooldown_seconds > 0.0,
		"Meal cooldown and slow-weapon attack lock are independent")
	check(FishingSession.eat(eater, "Reedkip", engine) == 40 and is_equal_approx(actor.attack_cooldown_seconds, 4.4),
		"Repeated eating extends the existing slow-weapon lock instead of replacing it")
	fixture = food_fixture("Bronze Warmaul", 0.0)
	eater = fixture.player
	actor = fixture.actor
	engine = fixture.engine
	engine.active_spell_casts[eater.entity_id] = {}
	check(FishingSession.eat(eater, "Reedkip", engine) == 0, "Eating cannot bypass an active spell cast")
	engine.active_spell_casts.clear()
	check(FishingSession.eat(eater, "Reedkip", engine) == 40, "Eating is available after casting finishes")
	engine.process_realtime(fixture.world, 1.8)
	var mana := eater.current_mana
	var blocked := engine.cast_spell(fixture.world, eater.entity_id, "air_razorwind", "food_dummy")
	check(not blocked.ok and String(blocked.error).contains("eating") and eater.current_mana == mana,
		"Spell casting cannot bypass the remaining slow-weapon food lock after the meal cooldown ends")
	engine.process_realtime(fixture.world, 1.21)
	check(engine.cast_spell(fixture.world, eater.entity_id, "air_razorwind", "food_dummy").ok,
		"Spell casting resumes when the weapon-dependent food lock expires")
