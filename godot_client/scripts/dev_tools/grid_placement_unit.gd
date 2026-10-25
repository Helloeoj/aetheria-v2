extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Grid placement FAIL] ",label)

func _run() -> void:
	check(FileAccess.file_exists("res://scripts/grid_placement.gd"), "shared safe placement exists")
	if failures > 0:
		finish()
		return
	var placement = load("res://scripts/grid_placement.gd")
	var grid := HiddenGrid.new()
	grid.configure(Vector2.ZERO,Vector2(-10,-10),Vector2(10,10))
	check(placement.resolve(grid,Vector2(2.2,3.3)).is_equal_approx(Vector2(2.5,3.5)), "legacy coordinate migrates to a clear center")
	check(placement.resolve(grid,Vector2(2.5,3.5)).is_equal_approx(Vector2(2.5,3.5)), "migration is idempotent")
	check(not placement.resolve(grid,Vector2(INF,0)).is_finite(), "nonfinite save fails without fabricating a location")
	check(not placement.resolve(grid,Vector2(50,50)).is_finite(), "out-of-map save cannot silently jump to a spawn")
	grid.point_clear = func(p: Vector2) -> bool: return absf(p.x-0.25) > 0.05
	grid.sweep_clear = func(a: Vector2,b: Vector2) -> bool: return (a.x-0.25)*(b.x-0.25) > 0
	grid.clear_cache()
	check(placement.resolve(grid,Vector2(0.1,0.5)).is_equal_approx(Vector2(-0.5,0.5)), "nearest center across a thin wall is rejected for same-floor center")
	check(not placement.resolve(grid,Vector2(0.25,0.5)).is_finite(), "overlapping wall cannot infer a reachable floor")
	grid.point_clear = func(p: Vector2) -> bool: return p.distance_to(Vector2(0.1,0.1)) < 0.1
	grid.clear_cache()
	check(not placement.resolve(grid,Vector2(0.1,0.1)).is_finite(), "isolated clear patch cannot jump to disconnected floor")
	grid.point_clear = Callable()
	grid.sweep_clear = Callable()
	grid.clear_cache()
	var p = load("res://scripts/player_state.gd").new("Legacy")
	p.x = 2.2
	p.y = 3.3
	p.gold = 47
	p.add_item("Beginner Rod",1)
	p.set_skill_level("fishing",25)
	var codec = load("res://network/character_codec.gd")
	var state: Dictionary = codec.encode(p,"fixture")
	var region = load("res://network/authoritative_region.gd").new()
	region.configure("fixture",null)
	region.world.set_movement_bounds(Vector2(-10,-10),Vector2(10,10))
	region.world.set_grid(grid)
	var decoded: Dictionary = codec.decode(state,"Legacy","legacy")
	check(decoded.ok,"existing save version decodes")
	region.add_player("legacy",decoded.player)
	check(decoded.player.get_position().is_equal_approx(Vector2(2.5,3.5)), "server admission migrates the existing save to the checked center")
	check(decoded.player.gold == 47 and decoded.player.backpack.get("Beginner Rod",0) == 1 and decoded.player.levels.fishing == 25, "position migration retains gold, inventory and skills")
	state.version = 1
	state.skill_experience.erase("mining")
	check(codec.decode(state,"Legacy","legacy-v1").ok, "old version-one progression remains readable")
	var bad = codec.decode(codec.encode(p,"fixture"),"Legacy","unsafe").player
	bad.x = 50
	bad.y = 50
	region.add_player("unsafe",bad)
	check(not region.players.has("unsafe") and bad.x == 50 and bad.y == 50 and bad.gold == 47, "unsafe admission rejects without replacing saved location/progress")
	finish()

func finish() -> void:
	print("[Grid placement] %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
