extends Node
## Test process only; never used by the game main scene.

func _ready() -> void:
	var core := get_node("/root/DiagnosticCore")
	var mode := "once"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--probe="):
			mode = argument.trim_prefix("--probe=")
	if mode == "disabled":
		AetheriaDiagnostics.event("Test", "disabled no-op")
		AetheriaDiagnostics.report("Test", "disabled no-op")
		get_tree().quit(0 if not core.enabled else 1)
		return
	AetheriaDiagnostics.context({"scene": "ADC probe", "player_position_tiles": [7, 9]})
	AetheriaDiagnostics.event("Inventory", "probe operation", {"item": "Bronze Sword"})
	if mode == "hold":
		push_error("ADC probe evidence before abnormal test termination")
		core.flush()
		print("ADC PROBE READY")
		return
	if mode == "fault":
		for index in 5:
			AetheriaDiagnostics.report("Test", "ADC I/O fault resilience probe")
			core.flush()
		print("ADC FAULT PROBE: ", core.io_failed)
		get_tree().quit(0 if core.io_failed and core.incidents.size() <= 2 else 1)
		return
	if mode == "overflow":
		for index in 300:
			AetheriaDiagnostics.report("Test", "ADC unique error %d" % index)
		core.flush()
		get_tree().quit(0 if core.incidents.size() == core.max_incidents and core.dropped_occurrences == 300 - core.max_incidents else 1)
		return
	if mode == "scene_failure":
		var result: int = core.change_scene("res://diagnostics/ADC_MISSING_SCENE.tscn")
		core.flush()
		get_tree().quit(0 if result != OK and not core.incidents.is_empty() else 1)
		return
	push_error("ADC single synthetic probe error")
	core.flush()
	get_tree().quit(0 if not core.io_failed else 1)
