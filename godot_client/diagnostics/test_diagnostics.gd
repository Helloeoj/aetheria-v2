extends Node
## Controlled script failures below are intentional. The test runner checks assertions AND native capture.
const Data = preload("res://diagnostics/diagnostic_data.gd")
const Bridge = preload("res://diagnostics/native_logger.gd")
var checks := 0
var failures: Array[String] = []
var core: Node

func _ready() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("ADC TEST FAIL: " + label)

func _duplicate_error() -> void:
	push_error("ADC synthetic duplicate InstanceID=1234 at 2026-10-19T12:00:00Z")

func _runtime_error() -> void:
	var absent: Variant = null
	absent.adc_intentional_missing_method()

func _freed_error() -> void:
	var object := Node.new()
	object.free()
	object.get_name()

func _worker_error() -> void:
	push_error("ADC synthetic worker-thread error")

func _run() -> void:
	core = get_tree().root.get_node("DiagnosticCore")
	check(core.enabled and core.bridge != null, "autoload registered native logger")
	var recorder = Bridge.new()
	recorder.event_limit = 8
	for index in 20:
		recorder.breadcrumb("Inventory", "ring event", {"item": index})
	recorder.mutex.lock()
	var recent: Array = recorder._recent()
	recorder.mutex.unlock()
	check(recent.size() == 8 and recent[0].data.item == 12 and recent[-1].data.item == 19, "circular buffer order and bound")
	var safe: Dictionary = Data.safe({"password": "NEVER_STORE", "nested": {"token": "NEVER_STORE"}, "object": core, "position": Vector2(2, 3)})
	check(safe.password == "[REDACTED]" and safe.nested.token == "[REDACTED]" and safe.object == "[object omitted]", "redaction and object omission")
	check(float(safe.position[0]) == 2.0 and float(safe.position[1]) == 3.0, "position is stable primitive data")
	var signature := {"kind": "test", "system": "Equipment", "message": "InstanceID=1234 0x123456 2026-10-19T12:00:00Z item 42", "source": {"file": "res://equipment.gd", "line": 12}}
	var second: Dictionary = signature.duplicate(true)
	second.message = "InstanceID=9876 0xabcdef 2026-10-20T13:00:00Z item 42"
	check(Data.fingerprint(signature) == Data.fingerprint(second), "volatile instance/pointer/time deduplication")
	second.message = "InstanceID=9876 0xabcdef 2026-10-20T13:00:00Z item 43"
	check(Data.fingerprint(signature) != Data.fingerprint(second), "different gameplay IDs remain distinct")
	second = signature.duplicate(true)
	second.source.line = 13
	check(Data.fingerprint(signature) != Data.fingerprint(second), "different source locations remain distinct")
	recorder.pending_limit = 8
	for index in 20:
		recorder.capture({"kind": "limit", "system": "Test", "message": "unique %d" % index, "source": {}})
	var limited: Dictionary = recorder.drain()
	check(limited.errors.size() == 8 and limited.dropped == 12, "bounded unique error queue reports overflow honestly")
	AetheriaDiagnostics.context({"scene": "adc_test", "player_position_tiles": [4, 5]})
	AetheriaDiagnostics.event("Equipment", "equip item", {"item": "Bronze Sword"})
	for index in 500:
		_duplicate_error()
	_runtime_error()
	_freed_error()
	var worker := Thread.new()
	worker.start(_worker_error)
	worker.wait_to_finish()
	var missing := load("res://diagnostics/ADC_INTENTIONALLY_MISSING.tscn")
	check(missing == null, "controlled missing-resource condition")
	core.flush()
	var duplicate: Dictionary = {}
	var saw_runtime := false
	var saw_freed := false
	var saw_worker := false
	var saw_resource := false
	for incident: Dictionary in core.incidents.values():
		if "ADC synthetic duplicate" in incident.message:
			duplicate = incident
		if "adc_intentional_missing_method" in incident.message:
			saw_runtime = true
		if "previously freed" in incident.message:
			saw_freed = true
		if "worker-thread" in incident.message:
			saw_worker = true
		if "ADC_INTENTIONALLY_MISSING" in incident.message:
			saw_resource = true
	check(not duplicate.is_empty() and duplicate.get("count", 0) == 500, "500 native errors become one counted incident")
	check(saw_runtime and saw_freed and saw_worker and saw_resource, "runtime/freed-object/worker/resource errors captured")
	if not duplicate.is_empty():
		check(duplicate.source.file == "res://diagnostics/test_diagnostics.gd" and duplicate.source.line > 0, "precise native GDScript source/backtrace")
		check(duplicate.recent_events[-1].data.item == "Bronze Sword", "error has causal-order breadcrumb snapshot")
		check(duplicate.context.scene == "adc_test", "context captured at error time")
		var detail: String = core.session_path.path_join("incidents").path_join(duplicate.id + ".json")
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(detail))
		check(saved is Dictionary and saved.count == 500 and saved.backtrace.size() > 0, "detailed JSON persisted and readable")
		var compact := FileAccess.get_file_as_string(detail.trim_suffix(".json") + ".txt")
		check(compact.length() < 3000 and "Hypothesis:" in compact and "Bronze Sword" in compact, "compact actionable report under 3000 characters")
		check(FileAccess.file_exists(core.storage.path_join("latest.txt")), "single-file agent entry point generated")
	check(not core.io_failed, "atomic reports successfully replace previous versions")
	var player := PlayerState.new("ADC test")
	player.add_item("Bronze Bow", 1)
	player.add_item("Bronze Kiteshield", 1)
	player.equip_item("Bronze Bow")
	player.equip_item("Bronze Kiteshield")
	check(not GameData.get_item_by_name("Bronze Kiteshield").is_empty() and player.equipment.shield.is_empty() and not player.equipment.weapon.is_empty() and int(player.backpack.get("Bronze Kiteshield", 0)) == 1, "two-handed weapon/shield rule preserved")
	player.unequip_slot("weapon")
	check(int(player.backpack.get("Bronze Bow", 0)) == 1, "unequip preserves backpack ownership")
	core.flush()
	var result := {"checks": checks, "failures": failures, "session_id": core.session_id, "session_path": core.session_path, "incidents": core.incidents.size(), "io_failed": core.io_failed}
	var file := FileAccess.open(core.storage.path_join("test-result.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
	print("ADC TEST RESULT: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
