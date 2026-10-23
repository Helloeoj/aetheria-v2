extends Node

var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("[Region freeze FAIL] ", label)

func _ready() -> void:
	var region := AuthoritativeRegion.new()
	region.configure("test", null)
	preload("res://scripts/dev_tools/region_combat_fixture.gd").add_monsters(region)
	var player := PlayerState.new("Frozen caster")
	player.set_skill_level("magic", 100)
	player.x = 14.0
	player.y = 15.0
	region.add_player("caster", player)
	var engine: CombatEngine = region.world.combat
	var actor: CombatActor = engine.actors.caster
	var target: MonsterState = region.world.monsters[0]
	var monster: CombatActor = engine.actors[target.entity_id]
	var outcome := region.submit("caster", {"type": "cast", "spell_id": "fire_scorch", "target_id": target.entity_id})
	check(outcome.ok and engine.active_spell_casts.has("caster"), "Casting fixture starts a delayed spell")
	if failures > 0:
		get_tree().quit(1)
		return
	var cast_remaining: float = engine.active_spell_casts.caster.remaining
	var mana := player.current_mana
	player.food_cooldown_seconds = 0.5
	actor.active_orb_effects.ice = preload("res://scripts/orb_effects.gd").create("ice", target.entity_id, 1)
	var orb_remaining: float = actor.active_orb_effects.ice.remaining
	monster.active_orb_effects.fire = preload("res://scripts/orb_effects.gd").create("fire", "caster", 10)
	var dot_remaining: float = monster.active_orb_effects.fire.remaining
	var outgoing := CombatProjectile.new().configure({"projectile_id": "outgoing", "attacker_id": "caster", "target_id": target.entity_id, "x": 10.0, "y": 10.0, "dx": 1.0, "dy": 0.0, "speed": 1.0})
	var incoming := CombatProjectile.new().configure({"projectile_id": "incoming", "attacker_id": target.entity_id, "target_id": "caster", "x": 5.0, "y": 5.0, "dx": 1.0, "dy": 0.0, "speed": 1.0})
	engine.projectiles.outgoing = outgoing
	engine.projectiles.incoming = incoming
	region.frozen["caster"] = true
	region.advance(1.0 / 30.0)
	check(engine.active_spell_casts.has("caster"), "Persistence pause preserves the already-paid cast")
	check(is_equal_approx(float(engine.active_spell_casts.get("caster", {}).get("remaining", -1)), cast_remaining), "Frozen casts do not advance their timer")
	check(player.current_mana == mana, "Pause never charges mana again")
	check(is_equal_approx(player.food_cooldown_seconds, 0.5), "Frozen player's food timer stays paused")
	check(is_equal_approx(actor.active_orb_effects.ice.remaining, orb_remaining), "Effects on the frozen actor retain their timers")
	check(is_equal_approx(monster.active_orb_effects.fire.remaining, dot_remaining), "Frozen source's damage-over-time waits for progression ownership")
	check(is_equal_approx(outgoing.x, 10.0) and is_equal_approx(outgoing.travelled, 0.0), "Frozen attacker projectiles do not travel or resolve without XP ownership")
	check(is_equal_approx(incoming.x, 5.0) and is_equal_approx(incoming.travelled, 0.0), "Projectiles aimed at the frozen player do not pass through or expire")
	region.frozen.erase("caster")
	region.advance(1.0 / 30.0)
	check(float(engine.active_spell_casts.get("caster", {}).get("remaining", cast_remaining)) < cast_remaining, "Cast resumes after confirmed persistence recovery")
	check(outgoing.x > 10.0 and incoming.x > 5.0, "Suspended projectiles resume after recovery")
	check(player.food_cooldown_seconds < 0.5 and monster.active_orb_effects.fire.remaining < dot_remaining, "Player and source effect timers resume after recovery")
	region.remove_player("caster")
	check(not engine.projectiles.has("outgoing") and not engine.projectiles.has("incoming"), "Terminal removal discards incoming and outgoing old-generation projectiles")
	check(not monster.active_orb_effects.has("fire"), "Terminal removal discards source-owned effects on other actors")
	var replacement := PlayerState.new("Replacement generation")
	region.add_player("caster", replacement)
	region.advance(1.0 / 30.0)
	check(engine.projectiles.is_empty() and not monster.active_orb_effects.has("fire"), "Rejoining cannot reactivate a previous lease's attacks or damage effects")
	print("[Region freeze] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
