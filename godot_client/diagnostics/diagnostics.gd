class_name AetheriaDiagnostics
extends RefCounted
## Safe no-op facade when diagnostics are disabled or no SceneTree exists.
static var _core: WeakRef

static func event(system: String, action: String, data: Dictionary = {}) -> void:
	var core: Variant = _core.get_ref() if _core != null else null
	if core != null and core.enabled:
		core.bridge.breadcrumb(system, action, data)

static func report(system: String, message: String, details: Dictionary = {}) -> void:
	var core: Variant = _core.get_ref() if _core != null else null
	if core != null and core.enabled:
		core.report(system, message, details, get_stack())

static func context(values: Dictionary) -> void:
	var core: Variant = _core.get_ref() if _core != null else null
	if core != null and core.enabled:
		core.bridge.set_context(values)
