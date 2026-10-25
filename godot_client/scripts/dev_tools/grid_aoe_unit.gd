extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Grid AoE FAIL] ", label)

func _run() -> void:
	check(FileAccess.file_exists("res://scripts/spell_footprint.gd"), "shared tile footprint exists")
	if failures > 0:
		finish()
		return
	var footprint = load("res://scripts/spell_footprint.gd")
	var grid := HiddenGrid.new()
	grid.configure(Vector2.ZERO, Vector2(-20,-20), Vector2(20,20))
	for pair: Array in [[2.0,13],[2.5,21],[3.0,29],[3.5,37]]:
		var cells: Array = footprint.cells(grid, Vector2i.ZERO, {"area_radius":pair[0]})
		check(cells.size() == pair[1], "inclusive circle count for provisional radius " + str(pair[0]))
	check(footprint.cells(grid, Vector2i(-3,-4), {"area_radius":0.0}) == [Vector2i(-3,-4)], "zero radius retains exactly the captured negative cell")
	check(footprint.cells(grid, Vector2i.ZERO, {"area_radius":-1.0}).is_empty(), "negative radius fails closed")
	check(footprint.cells(grid, Vector2i.ZERO, {"area_radius":INF}).is_empty(), "nonfinite radius fails closed")
	check(footprint.cells(grid, Vector2i.ZERO, {"area_radius":1.0}).has(Vector2i(1,0)), "exact radius boundary included")
	check(not footprint.cells(grid, Vector2i.ZERO, {"area_radius":1.0}).has(Vector2i(1,1)), "diagonal outside circle excluded")
	check(footprint.cells(grid, Vector2i.ZERO, {"area_shape":"offsets", "area_offsets":[[0,0],[1,0],[1,0]]}) == [Vector2i.ZERO,Vector2i(1,0)], "per-spell explicit footprints are ordered and deduplicated")
	grid.configure(Vector2.ZERO, Vector2(0.5,0.5), Vector2(4.5,4.5))
	check(footprint.cells(grid, Vector2i.ZERO, {"area_radius":1.0}).size() == 3, "map edges clip cells without wrapping")
	var p = load("res://scripts/player_state.gd").new("AoE regression")
	p.entity_id = "caster"
	p.set_skill_level("magic", 100)
	p.current_mana = 10000
	p.x = 0.5
	p.y = 0.5
	var world = load("res://scripts/world_state.gd").new(p)
	world.set_movement_bounds(Vector2(-20,-20), Vector2(20,20))
	grid.configure(Vector2.ZERO, Vector2(-20,-20), Vector2(20,20))
	world.set_grid(grid)
	world.combat.player_auto_attack_enabled = false
	world.register_player_actor(CombatActor.new().configure({"entity_id":"caster", "x":0.5,"y":0.5,"hp":100,"max_hp":100,"magic_level":100}))
	for pair: Array in [["anchor",Vector2(5.5,5.5)],["leaving",Vector2(7.5,5.5)],["entering",Vector2(8.5,5.5)],["dead",Vector2(5.5,5.5)]]:
		world.combat.add_actor(CombatActor.new().configure({"entity_id":pair[0],"x":pair[1].x,"y":pair[1].y,"hp":10000,"max_hp":10000,"is_monster":true}))
	world.combat.actors.dead.is_alive = false
	world.grid_traveller("anchor")
	world.move_grid_direction("anchor", Vector2.RIGHT, 0.2, 4.0)
	check(world.combat.cast_spell(world,"caster","air_stormring","anchor").ok, "existing selected-target cast starts")
	var cast: Dictionary = world.combat.active_spell_casts.caster
	check(cast.get("target_cell") == Vector2i(5,5), "cast captures target's committed cell despite midstep travel")
	world.move_grid_direction("anchor", Vector2.RIGHT, 1.0, 4.0)
	world.move_grid_direction("leaving", Vector2.RIGHT, 0.2, 4.0)
	world.move_grid_direction("entering", Vector2.LEFT, 0.2, 4.0)
	world.terrain_collision_handler = func(_a: Vector2,_b: Vector2) -> Dictionary: return {"blocked":true}
	var events: Array = world.combat._process_spell_casts(world, 2.5)
	var resolved: Dictionary = {}
	for event: Dictionary in events:
		if event.type == "spell_area_resolved": resolved = event
	check(resolved.get("target_cell") == [5,5], "resolution never follows a target that moved after cast start")
	var ids: Array = resolved.get("targets", [])
	check(ids.has("leaving") and not ids.has("entering"), "unfinished edges retain source occupancy for hits")
	check(not ids.has("anchor") and not ids.has("dead") and not ids.has("caster"), "departed, dead and friendly actors excluded")
	check(resolved.get("cells", []).size() == 13, "resolution reports the same radius-two footprint as preview")
	check(ids.has("leaving"), "existing wall-ignoring area behavior retained")
	world.move_grid_direction("leaving", Vector2.ZERO, 0.1, 4.0)
	world.move_grid_direction("entering", Vector2.ZERO, 0.1, 4.0)
	p.current_mana = 10000
	world.combat.cast_spell(world,"caster","air_stormring","",Vector2(5.5,5.5))
	events = world.combat._process_spell_casts(world, 2.5)
	for event: Dictionary in events:
		if event.type == "spell_area_resolved": resolved = event
	ids = resolved.get("targets", [])
	check(not ids.has("leaving") and ids.has("entering"), "arrived occupancy changes who is affected")
	finish()

func finish() -> void:
	print("[Grid AoE] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
