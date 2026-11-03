extends Node
const Fixture := preload("res://scripts/dev_tools/titan_combat_smoke.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Damage/aggro FAIL] ", label)
func _ready() -> void:
	var helper := Fixture.new()
	for critical: bool in [false, true]:
		for kind: String in ["haymaker", "bolt", "slam", "eruption"]:
			var f: Dictionary = helper.fixture(1.5, 719)
			f.boss.min_damage = 7
			f.boss.max_damage = 7
			f.boss.crit_chance = 1.0 if critical else 0.0
			f.boss.crit_multiplier = 1.5
			f.target.damage_reductions = {"blunt":0.25, "magic":0.25}
			var original: int = f.target.hp
			var events: Array[Dictionary] = f.engine.titan_encounters._resolve(f.engine, f.world, f.boss, {"kind":kind,"target_id":"p","attack_id":"damage_case","cells":[f.world.occupied_cell("p")]})
			if kind == "bolt": events = f.engine._process_projectiles(f.world, 1.0)
			var multiplier := 2 if kind in ["slam", "eruption"] else 1
			var expected := (7 if critical else 5)*multiplier
			check(original-f.target.hp == expected, kind+" damage="+str(original-f.target.hp)+" expected="+str(expected)+" crit="+str(critical))
	for titan: bool in [false,true]:
		var f: Dictionary = helper.fixture(1.5,719)
		if not titan:
			f.boss.boss_profile = ""
			f.boss.stationary = false
		f.player.current_target = ""
		f.target.current_target_id = ""
		var events: Array[Dictionary] = []
		for i in 8: events.append_array(helper.step(f))
		check(f.boss.current_target_id == "p", "engaged monster retains target after player stops attacking; titan="+str(titan))
		check(events.any(func(e: Dictionary) -> bool: return e.get("type", "") in ["entity_hit", "titan_attack_started"]), "engaged monster keeps attacking; titan="+str(titan))
		f.world.move_actor_continuous("p", Vector2(60,0))
		for i in 2: helper.step(f)
		check(f.boss.current_target_id.is_empty() and f.boss.aggro_attacker_ids.is_empty(), "leaving existing boundary ends aggression; titan="+str(titan))
		f.world.move_actor_continuous("p", Vector2(22,20.5)-Vector2(f.target.x,f.target.y))
		helper.step(f)
		check(f.boss.current_target_id.is_empty(), "returning alone does not re-engage after leash reset; titan="+str(titan))
		f.boss.aggro_attacker_ids.append("p")
		f.target.is_alive = false
		check(f.engine._refresh_monster_target(f.world,f.boss) == null, "dead player is dropped; titan="+str(titan))
	helper.free()
	print("[Damage/aggro] ", checks," checks; ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)
