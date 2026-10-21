extends Node
## Real projectile, attack, movement and damage paths; no fake status implementation.

var checks := 0
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("[Orb FAIL] " + label)

func _run() -> void:
	var fixture := make_fixture("fire")
	var events := empower(fixture)
	check(has_event(events, "orb_effect_applied"), "A successful enchanted staff projectile can apply its effect")
	if not has_event(events, "orb_effect_applied"):
		finish()
		return
	check_chances()
	check_burn()
	check_nonstacking()
	check_ice()
	check_monster_engagement_cadence()
	check_lightning()
	check_hurricane()
	check_eligibility()
	check_selected_staff_spells()
	check_lifecycle()
	finish()

func finish() -> void:
	print("[Orb combat] %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func make_fixture(element: String = "", damage: int = 10) -> Dictionary:
	var player := PlayerState.new("Orb regression")
	player.entity_id = "orb_player"
	var world := WorldState.new(player)
	var attacker := CombatActor.new().configure({"entity_id": player.entity_id,
		"x": 10.0, "y": 10.0, "max_hp": player.get_max_hp(),
		"attack_style": "magic", "orb_element": element, "accuracy": 0.99,
		"min_damage": damage, "max_damage": damage, "crit_chance": 0.0,
		"attack_interval_seconds": 1.8, "projectile_speed": 100.0})
	var monster := MonsterState.new({"name": "Orb dummy", "max_hp": 1000000}, 12, 10)
	monster.entity_id = "orb_dummy"
	var target := CombatActor.new().configure({"entity_id": monster.entity_id,
		"x": 12.0, "y": 10.0, "max_hp": 1000000,
		"is_monster": true, "defence_level": 100,
		"melee_defence_rolls": {"slash": 6912.0}})
	world.register_player_actor(attacker)
	world.register_monster_actor(monster, target)
	world.combat.player_auto_attack_enabled = false
	world.combat.random.seed = 719
	player.current_target = target.entity_id
	return {"world": world, "engine": world.combat, "attacker": attacker,
		"target": target, "monster": monster, "player": player}

func shoot(f: Dictionary) -> Array[Dictionary]:
	f.engine._resolve_attack(f.world, f.attacker, f.target)
	return f.engine._process_projectiles(f.world, 0.1)

func empower(f: Dictionary) -> Array[Dictionary]:
	for trial in range(300):
		var events := shoot(f)
		if has_event(events, "orb_effect_applied"):
			return events
	return []

func has_event(events: Array, kind: String) -> bool:
	for event: Dictionary in events:
		if event.get("type", "") == kind:
			return true
	return false

func effects(actor: CombatActor) -> Dictionary:
	var value: Variant = actor.get("active_orb_effects")
	return value if value is Dictionary else {}

func check_chances() -> void:
	for element: String in ["fire", "ice", "lightning", "hurricane"]:
		var f := make_fixture(element)
		var hits := 0
		var procs := 0
		for trial in range(2000):
			effects(f.target).clear()
			var events := shoot(f)
			for event: Dictionary in events:
				if event.type == "projectile_hit" and event.hit and event.damage > 0:
					hits += 1
			if has_event(events, "orb_effect_applied"):
				procs += 1
		var observed := float(procs) / float(hits)
		check(observed > 0.075 and observed < 0.125, element + " rolls 10% per successful damaging hit")

func check_burn() -> void:
	var f := make_fixture("fire", 10)
	empower(f)
	var hp := int(f.target.hp)
	for tick in range(5):
		var events: Array = f.engine.process_realtime(f.world, 0.6)
		check(f.target.hp == hp - tick - 1, "Burn deals one damage per tick from a ten damage hit")
		check(has_event(events, "entity_hit"), "Burn travels through entity hit event path")
	check(not effects(f.target).has("fire"), "Burn expires after five ticks")
	var fractional := make_fixture("fire", 3)
	empower(fractional)
	var fractional_hp := int(fractional.target.hp)
	for tick in range(3):
		fractional.engine.process_realtime(fractional.world, 0.6)
	check(fractional.target.hp == fractional_hp, "Fractional burn never forces minimum one damage per tick")
	fractional.engine.process_realtime(fractional.world, 1.2)
	check(fractional.target.hp == fractional_hp - 1, "Fractional burn retains budget across all five ticks")
	var overkill := make_fixture("fire", 100)
	overkill.target.hp = 4
	shoot(overkill)
	check(effects(overkill.target).is_empty(), "A killing direct hit never leaves a live burn")
	var reduced := make_fixture("fire", 20)
	reduced.target.damage_reductions = {"magic": 0.5}
	empower(reduced)
	var reduced_hp := int(reduced.target.hp)
	reduced.engine.process_realtime(reduced.world, 3.0)
	check(reduced.target.hp == reduced_hp - 5, "Burn bases its budget on damage after mitigation and does not mitigate it twice")

func check_nonstacking() -> void:
	var f := make_fixture("fire")
	empower(f)
	f.engine.process_realtime(f.world, 0.6)
	var remaining := float(effects(f.target).fire.remaining)
	var source := String(effects(f.target).fire.source_id)
	var other := CombatActor.new().configure(f.attacker.to_dictionary())
	other.entity_id = "second_staff_attacker"
	f.engine.add_actor(other)
	f.attacker = other
	for trial in range(50):
		shoot(f)
	check(is_equal_approx(float(effects(f.target).fire.remaining), remaining), "Other attackers cannot refresh active fire")
	check(String(effects(f.target).fire.source_id) == source, "Original burn source survives another attacker")
	other.set("orb_element", "ice")
	empower(f)
	check(effects(f.target).has("fire") and effects(f.target).has("ice"), "Different orb types coexist")
	check(effects(f.target).size() == 2, "Target holds one instance of each type")

func check_ice() -> void:
	var f := make_fixture("ice")
	empower(f)
	check(is_equal_approx(float(f.target.call("effective_attack_interval_seconds")), 2.0), "Ice reduces attack rate 10%, taking 1.8 seconds to 2 seconds")
	# Apply to the real player actor to verify its attack cooldown rather than a label.
	f.attacker.set("active_orb_effects", effects(f.target).duplicate(true))
	f.player.current_target = "orb_dummy"
	f.engine.player_auto_attack_enabled = true
	f.attacker.attack_cooldown_seconds = 0.0
	f.engine.process_realtime(f.world, 0.0)
	check(is_equal_approx(f.attacker.attack_cooldown_seconds, 2.0), "Player attacks schedule the slowed interval")
	f.engine.player_auto_attack_enabled = false
	f.engine.process_realtime(f.world, 10.0)
	check(is_equal_approx(float(f.attacker.call("effective_attack_interval_seconds")), 1.8), "Ice expires and restores base attack interval")
	check(is_equal_approx(f.attacker.attack_interval_seconds, 1.8), "Ice never mutates equipped weapon interval")
	var baseline := make_fixture()
	shoot(baseline)
	var slowed := make_fixture("ice")
	empower(slowed)
	var normal_attacks := 0
	var slow_attacks := 0
	for fixture: Dictionary in [baseline, slowed]:
		fixture.target.max_damage = 0
		fixture.target.min_damage = 0
	for tick in range(30):
		for event: Dictionary in baseline.engine.process_tick(baseline.world):
			if event.type == "entity_hit":
				normal_attacks += 1
		for event: Dictionary in slowed.engine.process_tick(slowed.world):
			if event.type == "entity_hit":
				slow_attacks += 1
	check(normal_attacks == 10 and slow_attacks == 9, "Actual monster attack cadence runs at a 0.9 rate on the fixed tick grid")
	var expiry := make_fixture("ice")
	empower(expiry)
	expiry.attacker.set("active_orb_effects", effects(expiry.target).duplicate(true))
	effects(expiry.attacker).ice.remaining = 0.1
	expiry.attacker.attack_cooldown_seconds = 2.0
	expiry.engine.process_realtime(expiry.world, 0.2)
	check(is_equal_approx(expiry.attacker.attack_cooldown_seconds, 1.61), "Mid-frame Ice expiry restores the base rate for only the recovered portion")

func check_lightning() -> void:
	var f := make_fixture("lightning")
	empower(f)
	f.attacker.set("active_orb_effects", effects(f.target).duplicate(true))
	f.target.x = 20.0
	f.monster.x = 20.0
	var original := Vector2(f.attacker.x, f.attacker.y)
	check(f.world.move_actor_continuous(f.attacker.entity_id, Vector2.RIGHT) == original, "Lightning blocks actual player movement")
	f.engine.player_auto_attack_enabled = true
	check(not has_event(f.engine.process_realtime(f.world, 0.6), "projectile_spawned"), "Lightning blocks player autoattack")
	check(f.target.x == 20.0, "Lightning blocks actual monster pursuit")
	check(f.engine.process_tick(f.world).is_empty(), "Lightning blocks monster tick attacks")
	check(not f.engine.cast_spell(f.world, f.attacker.entity_id, "arcane_bolt", f.target.entity_id).ok, "Lightning blocks casting")
	f.engine.player_auto_attack_enabled = false
	f.engine.process_realtime(f.world, 1.21)
	check(bool(f.attacker.call("can_move")), "Lightning expires after three ticks")
	check(f.world.move_actor_continuous(f.attacker.entity_id, Vector2.RIGHT) != original, "Player movement resumes after paralysis")
	# A large frame may only move the unblocked remainder, not all of the frame.
	var large := make_fixture("lightning")
	empower(large)
	large.target.x = 20.0
	large.monster.x = 20.0
	large.engine.process_realtime(large.world, 2.0)
	check(is_equal_approx(large.target.x, 19.5), "Large delta preserves the 1.8 second paralysis before monster recovery")

func check_monster_engagement_cadence() -> void:
	var f := make_fixture()
	shoot(f)
	f.target.min_damage = 0
	f.target.max_damage = 0
	f.engine.current_tick = 10
	check(has_event(f.engine.process_tick(f.world), "entity_hit"), "An uniced monster can first engage at world tick ten")
	check(not has_event(f.engine.process_tick(f.world), "entity_hit"), "First engagement leaves tick eleven on cooldown")
	check(not has_event(f.engine.process_tick(f.world), "entity_hit"), "First engagement leaves tick twelve on cooldown")
	check(has_event(f.engine.process_tick(f.world), "entity_hit"), "First engagement repeats at tick thirteen after a full 1.8 seconds")
	f.player.current_target = ""
	f.engine.current_tick = 20
	f.engine.process_tick(f.world)
	shoot(f)
	f.player.current_target = f.target.entity_id
	f.engine.current_tick = 30
	check(has_event(f.engine.process_tick(f.world), "entity_hit"), "An uniced monster reengages after a long idle")
	check(not has_event(f.engine.process_tick(f.world), "entity_hit"), "Idle reengagement leaves tick thirty-one on cooldown")
	check(not has_event(f.engine.process_tick(f.world), "entity_hit"), "Idle reengagement leaves tick thirty-two on cooldown")
	check(has_event(f.engine.process_tick(f.world), "entity_hit"), "Idle reengagement repeats at tick thirty-three after a full 1.8 seconds")

func check_hurricane() -> void:
	var f := make_fixture("hurricane")
	var melee := CombatActor.new().configure({"attack_style": "slash", "melee_attack_roll": 6000.0})
	var before: float = f.engine.calculate_hit_chance(melee, f.target)
	empower(f)
	check(f.target.call("effective_defence_level") == 90, "Hurricane reduces effective level 100 to 90")
	check(f.engine.calculate_hit_chance(melee, f.target) > before, "Hurricane changes actual melee accuracy despite cached defence rolls")
	check(f.target.defence_level == 100, "Hurricane does not mutate base defense level")
	f.engine.process_realtime(f.world, 10.0)
	check(is_equal_approx(f.engine.calculate_hit_chance(melee, f.target), before), "Hurricane restores exact original hit chance after ten seconds")
	var low := make_fixture("hurricane")
	low.target.defence_level = 1
	empower(low)
	check(low.target.call("effective_defence_level") == 1, "Hurricane minimum effective defense is one")

func check_eligibility() -> void:
	for element: String in ["", "unknown"]:
		var plain := make_fixture(element)
		for trial in range(50):
			shoot(plain)
		check(effects(plain.target).is_empty(), "Plain/invalid orb never grants status")
	var zero := make_fixture("fire", 0)
	for trial in range(50):
		shoot(zero)
	check(effects(zero.target).is_empty(), "Zero damage never triggers an orb")
	var misses := make_fixture("fire")
	misses.attacker.accuracy = 0.0
	for trial in range(150):
		effects(misses.target).clear()
		var events := shoot(misses)
		for event: Dictionary in events:
			if event.type == "projectile_hit" and not event.hit:
				check(effects(misses.target).is_empty(), "A missed staff projectile never procs")
	var captured := make_fixture("fire")
	for trial in range(100):
		captured.attacker.set("orb_element", "fire")
		captured.engine._resolve_attack(captured.world, captured.attacker, captured.target)
		captured.attacker.set("orb_element", "")
		if has_event(captured.engine._process_projectiles(captured.world, 0.1), "orb_effect_applied"):
			break
	check(effects(captured.target).has("fire"), "Projectile captures the firing staff orb before a weapon swap")
	var spell := make_fixture("")
	for trial in range(100):
		spell.engine._spawn_spell_projectile(spell.attacker, spell.target,
			{"id": "test_spell", "damage": 10, "school": "fire", "projectile_speed": 100.0})
		spell.engine._process_projectiles(spell.world, 0.1)
	check(effects(spell.target).is_empty(), "Spells without an enchanted staff never receive an orb proc")

func check_selected_staff_spells() -> void:
	var f := make_fixture("fire")
	f.player.set_skill_level("magic", 100)
	f.attacker.magic_level = 100
	f.attacker.magic_accuracy = 0.99
	var procced := false
	for trial in range(150):
		f.player.current_mana = 10000
		f.attacker.set("orb_element", "fire")
		var cast: Dictionary = f.engine.cast_spell(f.world, f.attacker.entity_id, "fire_scorch", f.target.entity_id)
		if not cast.ok:
			check(false, "Real learned staff spell cast can start")
			return
		f.attacker.set("orb_element", "")
		var events: Array = f.engine.process_realtime(f.world, 2.1)
		if has_event(events, "orb_effect_applied"):
			procced = true
			break
	check(procced, "Real staff spell hit retains enchanted orb captured at cast start")
	var area := make_fixture("hurricane")
	area.player.set_skill_level("magic", 100)
	area.attacker.magic_level = 100
	area.attacker.magic_accuracy = 0.99
	var area_procced := false
	for trial in range(150):
		area.player.current_mana = 10000
		area.attacker.set("orb_element", "hurricane")
		area.engine.cast_spell(area.world, area.attacker.entity_id,
			"fire_cinderfall", "", Vector2(12.0, 10.0))
		area.attacker.set("orb_element", "")
		var events: Array = area.engine.process_realtime(area.world, 2.9)
		if has_event(events, "orb_effect_applied"):
			area_procced = true
			break
	check(area_procced, "Damaging area staff spell rolls the captured orb for each direct target hit")
	var iced := make_fixture("ice")
	empower(iced)
	iced.attacker.set("active_orb_effects", effects(iced.target).duplicate(true))
	iced.player.set_skill_level("magic", 100)
	iced.player.current_mana = 10000
	var cast: Dictionary = iced.engine.cast_spell(iced.world, iced.attacker.entity_id, "fire_scorch", iced.target.entity_id)
	check(cast.ok and is_equal_approx(float(iced.engine.active_spell_casts[iced.attacker.entity_id].remaining), 2.0),
		"Ice slows a 1.8 second damaging cast to two seconds in normal staff play")

func check_lifecycle() -> void:
	var f := make_fixture("fire")
	empower(f)
	f.target.hp = 1
	var events: Array = f.engine.process_realtime(f.world, 0.6)
	check(has_event(events, "entity_died"), "Burn kill reports the standard death event for loot")
	check(not f.target.is_alive and effects(f.target).is_empty(), "Burn kill clears all effects")
	var count := 0
	for event: Dictionary in events:
		if event.type == "entity_hit":
			check(event.attacker_id == "orb_player", "Burn hit keeps original attacker attribution")
		if event.type == "entity_died":
			count += 1
	events = f.engine.process_realtime(f.world, 100.0)
	check(count == 1 and not has_event(events, "entity_died"), "Burn never reports death twice")
	var removed := make_fixture("fire")
	empower(removed)
	removed.world.remove_monster(removed.target.entity_id)
	check(effects(removed.target).is_empty(), "Despawn clears orb state even when an actor reference survives")
	check(not has_event(removed.engine.process_realtime(removed.world, 100.0), "entity_hit"), "Despawn leaves no ticking damage")
	var restored := make_fixture("hurricane")
	empower(restored)
	var roundtrip := CombatActor.new().configure(restored.target.to_dictionary())
	check(roundtrip.call("effective_defence_level") == 90, "Actor state roundtrip preserves active debuffs without mutating base level")
	roundtrip.active_orb_effects.clear()
	check(effects(restored.target).has("hurricane"), "Actor status snapshot owns a separate dictionary")
