extends Node

var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("[Mining definitions FAIL] ", label)

func _ready() -> void:
	if not ResourceLoader.exists("res://scripts/mining_definitions.gd"):
		check(false, "Mining definitions implementation exists")
	else:
		_run()
	print("[Mining definitions] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _run() -> void:
	var defs = load("res://scripts/mining_definitions.gd").new()
	check(defs.load_data().ok, "Production metadata validates without invented tools")
	check(defs.best_pickaxe(PlayerState.new()).is_empty(), "Missing catalog pickaxes fail closed")
	var bronze: Dictionary = defs.ore(235)
	check(not bronze.is_empty(), "Bronze uses existing catalog ID")
	check(is_equal_approx(defs.success_probability(1, bronze), 0.28), "Unlock chance matches simulator")
	check(is_equal_approx(defs.success_probability(27, bronze), 0.78), "Mastered chance matches simulator")
	check(defs.success_probability(10, bronze) > defs.success_probability(1, bronze), "Levels improve chance")
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mining.json"))
	var valid := source.duplicate(true)
	var coal := bronze.duplicate(true)
	coal.item_id = 329
	coal.required_level = 100
	valid.ores.append(coal)
	check(defs.load_records(valid).ok, "Second ore requires data only")
	check(defs.success_probability(99, defs.ore(329)) == 0.0 and is_equal_approx(defs.success_probability(100, defs.ore(329)), 0.28), "Independent level 100 unlock is safe")
	for invalid_id in [242, 256, 999999]:
		var invalid := source.duplicate(true)
		invalid.ores[0].item_id = invalid_id
		check(not defs.load_records(invalid).ok and defs.ore(235).is_empty(), "Restricted/unknown ore fails closed: %d" % invalid_id)
	for field in ["required_level", "xp_reward", "respawn_seconds", "node_scene"]:
		var invalid := source.duplicate(true)
		invalid.ores[0][field] = -1
		check(not defs.load_records(invalid).ok, "Invalid ore " + field)
	for field in ["p_at_unlock", "p_at_mastery", "mastery_levels", "curve_exponent"]:
		var invalid := source.duplicate(true)
		invalid.ores[0].success[field] = NAN
		check(not defs.load_records(invalid).ok, "Nonfinite success " + field)
	var duplicate := source.duplicate(true)
	duplicate.ores.append(duplicate.ores[0].duplicate(true))
	check(not defs.load_records(duplicate).ok, "Duplicate IDs rejected")
	var invalid_tool := source.duplicate(true)
	invalid_tool.pickaxes = [{"item_id":999999, "required_level":1, "attempt_interval_seconds":3.0}]
	check(not defs.load_records(invalid_tool).ok, "Unknown tool rejected")
	var missing_art := source.duplicate(true)
	missing_art.ores[0].visual.available = "res://missing.png"
	check(not defs.load_records(missing_art).ok, "Nonempty missing art reference rejected")
