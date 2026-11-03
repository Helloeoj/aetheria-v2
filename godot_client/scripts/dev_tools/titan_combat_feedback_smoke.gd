extends Node
const Fixture := preload("res://scripts/dev_tools/titan_combat_smoke.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	print("[Titan feedback] ", "PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func _ready() -> void:
	var helper := Fixture.new()
	var f: Dictionary = helper.fixture(9,719)
	var events: Array[Dictionary] = helper.starts(f,40)
	var previous := -1
	var largest_gap := 0
	var punches := 0
	for event: Dictionary in events:
		if event.kind == "haymaker": punches += 1
		else:
			if previous >= 0: largest_gap = maxi(largest_gap,int(event.tick)-previous)
			previous = int(event.tick)
	check(punches == 0, "no haymakers when target stays nine tiles away")
	check(largest_gap <= 4, "out-of-range punch gaps fall through to main attacks; gap="+str(largest_gap))
	for kind: String in ["slam","eruption"]:
		f = helper.fixture(6,719)
		var cast: Dictionary = {}
		for i in 50:
			for event: Dictionary in helper.step(f):
				if event.type == "titan_attack_started" and event.kind == kind: cast = event
			if not cast.is_empty(): break
		check(not cast.is_empty() and cast.cells.is_empty(), kind+" does not reveal locked cells through the entire body windup")
		var warnings: Array[Dictionary] = []
		var damage: Array[Dictionary] = []
		f.world.move_actor_continuous("p", Vector2(0, 1))
		for i in 3:
			for event: Dictionary in helper.step(f):
				if event.get("attack_id", "") == cast.get("attack_id", "") and event.type == "titan_area_warned": warnings.append(event)
				if event.get("titan_attack_id", "") == cast.get("attack_id", "") and event.type == "entity_hit": damage.append(event)
		check(warnings.size() == 1 and warnings[0].cells.size() == 10, kind+" publishes ten cells at the actual warning")
		check(not damage.is_empty(), kind+" still damages a stationary target")
		if warnings.size() == 1:
			check(warnings[0].cells.has(f.world.occupied_cell("p")), kind+" warns the new tile after movement during windup")
			check(int(warnings[0].tick) == int(cast.tick)+2, kind+" captures the player's tile when the floor cue appears")
			check(int(cast.hit_tick)-int(warnings[0].tick) == 1, kind+" gives exactly one game tick of floor warning")
	helper.free()
	get_tree().quit(0 if failures == 0 else 1)
