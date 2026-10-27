extends SceneTree
## --headless --path godot_client --script res://tools/check_worldbuilding.gd
## -- --manifest <absolute JSON> --report <absolute JSON outside project>
const Audit = preload("res://tools/worldbuilding_audit.gd")
var _report_path := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var values := {}
	if args.size() != 4:
		_finish(_failure("invalid_arguments", "Expected --manifest <absolute JSON> --report <absolute JSON outside project>."))
		return
	for index in [0, 2]:
		if args[index] not in ["--manifest", "--report"] or values.has(args[index]):
			_finish(_failure("invalid_arguments", "Unknown or duplicate command argument."))
			return
		values[args[index]] = args[index + 1]
	var manifest_path := str(values.get("--manifest", ""))
	_report_path = str(values.get("--report", ""))
	if not manifest_path.is_absolute_path() or not _safe_output(_report_path) or _normalized(manifest_path) == _normalized(_report_path):
		_report_path = ""
		_finish(_failure("invalid_arguments", "Input/output must be absolute, distinct paths; report must be outside the Godot project."))
		return
	if not FileAccess.file_exists(manifest_path):
		_finish(_failure("invalid_contract", "Manifest file does not exist."))
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(manifest_path)) != OK or not parser.data is Dictionary:
		_finish(_failure("invalid_contract", "Manifest must contain a JSON object: " + parser.get_error_message()))
		return
	var spec: Dictionary = parser.data
	if not Audit._valid_contract(spec):
		_finish(_failure("invalid_contract", "Manifest does not satisfy worldbuilding contract v1; props, distinct anchors and protected lanes are mandatory."))
		return
	# Loading a PackedScene can instantiate scripted Resource dependencies before
	# instantiate() or any node-script inspection. Check source dependencies first.
	var dependency_failure := _passive_dependencies(spec.scene, {})
	if not dependency_failure.is_empty():
		_finish(_failure("unsafe_resource_dependency", dependency_failure))
		return
	var resource: Resource = load(spec.scene)
	if not resource is PackedScene:
		_finish(_failure("invalid_scene", "Manifest scene is not a PackedScene."))
		return
	if not _editable_state(resource.get_state(), {}):
		_finish(_failure("scene_not_editable_content", "Audit passive editable content only. Scene or an instance has a script; select its un-scripted content scene instead of a gameplay wrapper."))
		return
	var map: Node = resource.instantiate()
	if not map is Node2D:
		map.free()
		_finish(_failure("invalid_scene", "Content scene root must be Node2D."))
		return
	root.add_child(map)
	await physics_frame
	await physics_frame
	var result: Dictionary = Audit.new().audit(map, spec)
	result.scene = spec.scene
	map.free()
	_finish(result)

func _passive_dependencies(path: String, visited: Dictionary) -> String:
	path = path.simplify_path()
	if visited.has(path):
		return ""
	visited[path] = true
	if not path.begins_with("res://") or not FileAccess.file_exists(path):
		return "Dependency cannot be inspected as local project source: " + path
	var extension := path.get_extension().to_lower()
	if extension in ["gd", "gdc", "cs"]:
		return "Executable script dependency is forbidden in passive content: " + path
	if extension not in ["tscn", "tres"]:
		# Only known raw media/shader leaves are exempt from scene/resource text
		# inspection. Binary .scn/.res and unknown serialized formats fail closed.
		if extension in ["png", "jpg", "jpeg", "webp", "bmp", "svg", "ttf", "otf", "woff", "woff2", "wav", "mp3", "ogg", "gdshader", "gdshaderinc"]:
			return ""
		return "Binary or unknown resource dependency cannot be inspected safely: " + path
	var source := FileAccess.get_file_as_string(path).trim_prefix("\ufeff").strip_edges()
	if not source.begins_with("[gd_scene ") and not source.begins_with("[gd_resource "):
		return "Scene/resource is not inspectable Godot text: " + path
	var executable := RegEx.new()
	executable.compile('(?m)^\\s*(?:script(?:/source)?\\s*=|\\[(?:sub_resource|ext_resource)\\s+[^\\r\\n\\]]*type\\s*=\\s*"(?:GDScript|CSharpScript|Script)")')
	if executable.search(source) != null:
		return "Embedded or attached script is forbidden in passive content: " + path
	for dependency: String in ResourceLoader.get_dependencies(path):
		var resolved := ""
		for part: String in dependency.split("::"):
			if part.begins_with("res://"):
				resolved = part
		if resolved.is_empty() and dependency.begins_with("uid://"):
			var id := ResourceUID.text_to_id(dependency.split("::")[0])
			if ResourceUID.has_id(id):
				resolved = ResourceUID.get_id_path(id)
		if resolved.is_empty():
			return "Resource dependency has no inspectable source path: " + dependency
		var failure := _passive_dependencies(resolved, visited)
		if not failure.is_empty():
			return failure
	return ""

func _editable_state(state: SceneState, visited: Dictionary) -> bool:
	if state == null or visited.has(state):
		return true
	visited[state] = true
	if not _editable_state(state.get_base_scene_state(), visited):
		return false
	for index in range(state.get_node_count()):
		for property in range(state.get_node_property_count(index)):
			if state.get_node_property_name(index, property) == &"script" and state.get_node_property_value(index, property) != null:
				return false
		var instance: PackedScene = state.get_node_instance(index)
		if instance != null and not _editable_state(instance.get_state(), visited):
			return false
	return true

func _safe_output(path: String) -> bool:
	if not path.is_absolute_path():
		return false
	var output := _normalized(path)
	var project := _normalized(ProjectSettings.globalize_path("res://")).trim_suffix("/")
	return output != project and not output.begins_with(project + "/")

func _normalized(path: String) -> String:
	return path.replace("\\", "/").simplify_path().to_lower()

func _failure(code: String, detail: String) -> Dictionary:
	return {"passed":false, "checks":0, "issues":[{"code":code, "node":"", "detail":detail}], "prop_textures":[], "rendering_verified":false}

func _finish(result: Dictionary) -> void:
	if not _report_path.is_empty():
		var directory_error := DirAccess.make_dir_recursive_absolute(_report_path.get_base_dir())
		var output: FileAccess = FileAccess.open(_report_path, FileAccess.WRITE) if directory_error == OK else null
		if output == null:
			result.passed = false
			result.issues.append({"code":"report_write_failed", "node":"", "detail":"Cannot write report to requested output path."})
		else:
			output.store_string(JSON.stringify(result, "\t") + "\n")
			output.close()
	print(JSON.stringify(result))
	quit(0 if result.passed else 1)
