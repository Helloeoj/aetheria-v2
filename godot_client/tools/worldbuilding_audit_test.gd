extends SceneTree
## Real shape regression fixtures; no installed map or character save is modified.
const AUDIT_PATH := "res://tools/worldbuilding_audit.gd"
const ORE := "res://scenes/MapProps/OreNodes/CopperOreFull.tscn"
var checks := 0
var failures := 0
var fixture: Node2D

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Worldbuilding FAIL] ", label)

func spec() -> Dictionary:
	return {"schema_version":1, "scene":ORE, "bounds":[0, 0, 512, 320],
		"grid_origin":[0, 0], "props":[{"node":"CopperA", "blocking":true}, {"node":"CopperB", "blocking":true}],
		"anchors":[{"id":"entry", "point":[48, 240]}, {"id":"far", "point":[464, 240]}],
		"routes":[{"id":"main lane", "points":[[48, 240], [464, 240]], "width":48}],
		"floor_polygon":[[0, 0], [512, 0], [512, 320], [0, 320]]}

func make_fixture() -> void:
	fixture = Node2D.new()
	fixture.name = "WorldbuildingFixture"
	root.add_child(fixture)
	for item: Array in [["CopperA", Vector2(128, 96)], ["CopperB", Vector2(320, 96)]]:
		var ore: Node2D = load(ORE).instantiate()
		ore.name = item[0]
		ore.position = item[1]
		fixture.add_child(ore)
	await settle()

func settle() -> void:
	await physics_frame
	await physics_frame

func wall(label: String, at: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = label
	body.position = at
	body.collision_layer = 1
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	fixture.add_child(body)
	return body

func run_audit(contract: Dictionary) -> Dictionary:
	return load(AUDIT_PATH).new().audit(fixture, contract)

func rejects(contract: Dictionary, code: String, label: String) -> void:
	var result := run_audit(contract)
	var found := false
	for issue: Dictionary in result.issues:
		found = found or issue.code == code
	check(not result.passed and found, label + " rejects with " + code + ": " + JSON.stringify(result.issues))

func _run() -> void:
	check(FileAccess.file_exists(AUDIT_PATH), "live shape worldbuilding validator exists")
	check(FileAccess.file_exists("res://tools/check_worldbuilding.gd"), "standalone editable-content CLI exists")
	if failures > 0:
		finish()
		return
	await make_fixture()
	var good := run_audit(spec())
	check(good.passed and good.checks > 0 and good.issues.is_empty(), "clear native canonical props and protected route pass: " + JSON.stringify(good))
	check(good.rendering_verified == false, "geometry success never claims visual approval")
	check(good.get("prop_textures", []).size() == 2, "actual canonical sprite textures are reported for source contract binding")
	if good.get("prop_textures", []).size() == 2:
		check(good.prop_textures[0].node == "CopperA/Footprint/Visual" and good.prop_textures[0].texture == "res://Assets/MapTiles/OreNodes/copper-ore-full-south.png" and good.prop_textures[0].world_scale == [1.0, 1.0] and good.prop_textures[0].anchor == [48.0, 72.0], "texture provenance, source anchor and native world scale come from installed sprites")
		check(good.prop_textures[0].get("native_size", []) == [96, 96], "actual imported texture dimensions bind the current source-size contract")
	_test_image_comparison()
	# A plain grouping folder must not hide overlap between distinct props.
	var folder := Node2D.new()
	folder.name = "Props"
	fixture.add_child(folder)
	var copper_a: Node2D = fixture.get_node("CopperA")
	var copper_b: Node2D = fixture.get_node("CopperB")
	copper_a.reparent(folder)
	copper_b.reparent(folder)
	copper_b.position = copper_a.position
	await settle()
	var folder_scope := spec()
	folder_scope.props = [{"node":"Props", "blocking":true}]
	rejects(folder_scope, "invalid_prop_scope", "grouping folder cannot merge separate overlapping prop instances into one self-exclusion scope")
	copper_a.reparent(fixture)
	copper_b.reparent(fixture)
	copper_b.position = Vector2(320, 96)
	folder.free()
	await settle()
	var visual: Sprite2D = fixture.get_node("CopperA/Footprint/Visual")
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rejects(spec(), "visual_filter", "linear filtering would blur native prop pixels")
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
	fixture.get_node("CopperA").texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rejects(spec(), "visual_filter", "inherited linear filtering is also rejected")
	fixture.get_node("CopperA").texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var original: Texture2D = visual.texture
	# Substitute only this process's in-memory texture cache, then restore it.
	# Source PNG and disk import cache stay untouched.
	var original_path := original.resource_path
	var stale_pixels := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	stale_pixels.fill(Color.WHITE)
	var stale_texture := ImageTexture.create_from_image(stale_pixels)
	stale_texture.take_over_path(original_path)
	visual.texture = stale_texture
	rejects(spec(), "imported_texture_mismatch", "loaded stale art cannot pass using the current clean PNG source contract")
	visual.texture = original
	original.take_over_path(original_path)
	var atlas := AtlasTexture.new()
	atlas.atlas = original
	atlas.region = Rect2(0, 0, 96, 96)
	visual.texture = atlas
	rejects(spec(), "unsupported_visual_texture", "atlas region cannot masquerade as a checked standalone PNG")
	visual.texture = original
	var round_base := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	round_base.shape = circle
	fixture.get_node("CopperA/Footprint").add_child(round_base)
	await settle()
	check(run_audit(spec()).passed, "existing circle bases use actual overlap with conservative rectangle containment")
	round_base.free()
	var second_body := StaticBody2D.new()
	second_body.position = Vector2(0, 32)
	var second_collision := CollisionShape2D.new()
	var second_shape := RectangleShape2D.new()
	second_shape.size = Vector2(8, 8)
	second_collision.shape = second_shape
	second_body.add_child(second_collision)
	fixture.get_node("CopperA").add_child(second_body)
	await settle()
	check(run_audit(spec()).passed, "legitimate reusable prop instance may own multiple physical bodies")
	second_body.free()
	var bypass := spec()
	bypass.props[0].blocking = false
	bypass.props[0].reason = "Declared decorative only"
	rejects(bypass, "nonblocking_has_footprint", "nonblocking declaration cannot bypass actual enabled world solids")
	var obstacle := wall("WallOverlap", Vector2(118, 81), Vector2(12, 12))
	await settle()
	rejects(spec(), "footprint_overlap", "rock base inside solid wall")
	obstacle.free()
	fixture.get_node("CopperB").position = Vector2(132, 96)
	await settle()
	rejects(spec(), "footprint_overlap", "rock base inside another prop")
	fixture.get_node("CopperB").position = Vector2(320, 96)
	fixture.get_node("CopperA").position = Vector2(16, 96)
	await settle()
	rejects(spec(), "footprint_out_of_bounds", "anchor is inside but physical rock extends outside bounds")
	fixture.get_node("CopperA").position = Vector2(128, 96)
	var floor_spec := spec()
	floor_spec.floor_polygon = [[0, 0], [512, 0], [512, 320], [0, 320], [0, 90], [160, 90], [160, 60], [0, 60]]
	await settle()
	rejects(floor_spec, "footprint_outside_floor", "base crosses concave floor cutout")
	obstacle = wall("NarrowLane", Vector2(256, 209), Vector2(24, 24))
	await settle()
	rejects(spec(), "reserved_lane_blocked", "24px actor fits but 48px reserved lane does not")
	obstacle.free()
	# World x=477 is blocked by the 24px body reaching x=489, while its
	# nearest grid center x=464 remains clear. A goal-radius-only test misses it.
	obstacle = wall("ExactGoal", Vector2(488, 240), Vector2(2, 2))
	await settle()
	var exact := spec()
	exact.anchors[1].point = [477, 240]
	rejects(exact, "anchor_blocked", "exact anchor is blocked even when nearby grid center can be clear")
	obstacle.free()
	obstacle = wall("DividingWall", Vector2(256, 160), Vector2(16, 320))
	await settle()
	rejects(spec(), "route_unreachable", "disconnected rooms")
	obstacle.free()
	fixture.get_node("CopperA/Footprint/MainBase").disabled = true
	fixture.get_node("CopperA/Footprint/CompanionBase").disabled = true
	await settle()
	rejects(spec(), "missing_footprint", "blocking prop with all colliders disabled")
	fixture.get_node("CopperA/Footprint/MainBase").disabled = false
	fixture.get_node("CopperA/Footprint/CompanionBase").disabled = false
	# The fixture's parent transform changes every canonical child's physical base.
	fixture.position = Vector2(64, 32)
	fixture.scale = Vector2(2, 2)
	await settle()
	var transformed := spec()
	transformed.bounds = [64, 32, 1024, 640]
	transformed.grid_origin = [64, 32]
	transformed.floor_polygon = [[64, 32], [1088, 32], [1088, 672], [64, 672]]
	transformed.anchors = [{"id":"entry", "point":[160, 512]}, {"id":"far", "point":[992, 512]}]
	transformed.routes = [{"id":"lane", "points":[[160, 512], [992, 512]], "width":48}]
	check(run_audit(transformed).passed, "scaled/translated parent uses actual world transforms")
	var transformed_report := run_audit(transformed)
	check(transformed_report.prop_textures[0].world_scale == [2.0, 2.0] and transformed_report.prop_textures[0].anchor == [48.0, 72.0], "native source anchor survives parent scaling while physical pixel density is reported")
	obstacle = wall("ScaledOverlap", Vector2(118, 81), Vector2(12, 12))
	await settle()
	rejects(transformed, "footprint_overlap", "scaled parent overlap remains detectable")
	obstacle.free()
	fixture.position = Vector2.ZERO
	fixture.scale = Vector2.ONE
	await settle()
	for malformed: Dictionary in [{}, {"schema_version":2}, {"bounds":[0, 0, -1, 320]}, {"grid_origin":[INF, 0]}, {"props":[]}, {"anchors":[]}, {"routes":[]}, {"routes":[{"id":"bad", "points":[[48, 240], [464, 240]], "width":12}]}, {"props":[{"node":"CopperA", "blocking":false}]}, {"props":[{"node":".", "blocking":true}]}, {"scene":"res://not-a-scene.gd"}]:
		var invalid := spec()
		if malformed.is_empty():
			invalid = {}
		else:
			invalid.merge(malformed, true)
		rejects(invalid, "invalid_contract", "malformed/vacuous manifest " + str(malformed))
	var missing := spec()
	missing.props[0].node = "MissingProp"
	rejects(missing, "prop_missing", "missing installed prop")
	var nested := spec()
	nested.props = [{"node":"CopperA", "blocking":true}, {"node":"CopperA/Footprint", "blocking":true}]
	rejects(nested, "invalid_prop_scope", "nested root cannot hide audited peer overlaps")
	var root_alias := spec()
	root_alias.props = [{"node":"./", "blocking":true}]
	rejects(root_alias, "invalid_prop_scope", "root path alias cannot exclude all scene walls as own bodies")
	fixture.free()
	_test_resource_preflight()
	finish()

func _test_image_comparison() -> void:
	var auditor: RefCounted = load(AUDIT_PATH).new()
	check(auditor.has_method("images_match"), "imported/source comparison is available for stale-art regression")
	if not auditor.has_method("images_match"):
		return
	var source := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	source.fill(Color(0.25, 0.5, 0.75, 1))
	source.set_pixel(0, 0, Color(1, 0, 0, 0))
	var imported := source.duplicate() as Image
	check(auditor.images_match(imported, source), "matching imported visible pixels and source pass")
	imported.set_pixel(0, 0, Color(0, 1, 0, 0))
	check(auditor.images_match(imported, source), "Godot alpha-border RGB under full transparency is ignored")
	imported.set_pixel(1, 1, Color(0.9, 0.5, 0.75, 1))
	check(not auditor.images_match(imported, source), "stale visible RGB is rejected")
	imported = source.duplicate() as Image
	imported.set_pixel(0, 0, Color(1, 0, 0, 0.25))
	check(not auditor.images_match(imported, source), "stale alpha at any pixel is rejected")
	check(not auditor.images_match(Image.create(3, 2, false, Image.FORMAT_RGBA8), source), "stale imported dimensions are rejected")

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _test_resource_preflight() -> void:
	# Run in an isolated temporary project. The negative fixture's _init writes
	# only its own temporary marker; no actual map, import cache or save is edited.
	var directory := OS.get_cache_dir().path_join("aetheria-worldbuilding-preflight-" + str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(directory.path_join("tools"))
	DirAccess.make_dir_recursive_absolute(directory.path_join("scripts"))
	_write(directory.path_join("project.godot"), "config_version=5\n[application]\nconfig/name=\"Worldbuilding preflight fixture\"\n[rendering]\nrenderer/rendering_method=\"gl_compatibility\"\n")
	for path: String in ["tools/worldbuilding_audit.gd", "tools/check_worldbuilding.gd", "scripts/hidden_grid.gd"]:
		_write(directory.path_join(path), FileAccess.get_file_as_string("res://" + path))
	var output: Array = []
	var import_exit := OS.execute(OS.get_executable_path(), ["--headless", "--path", directory, "--editor", "--import", "--quit"], output, true)
	check(import_exit == 0, "isolated preflight test project imports safely before adding probe resource")
	var marker := directory + "-marker.txt"
	_write(directory.path_join("resource_probe.gd"), "extends Resource\nfunc _init() -> void:\n\tvar file := FileAccess.open(" + JSON.stringify(marker.replace("\\", "/")) + ", FileAccess.WRITE)\n\tfile.store_string(\"RESOURCE_INIT_EXECUTED\")\n\tfile.close()\n")
	_write(directory.path_join("resource_probe.tres"), "[gd_resource type=\"Resource\" load_steps=2 format=3]\n[ext_resource type=\"Script\" path=\"res://resource_probe.gd\" id=\"1\"]\n[resource]\nscript = ExtResource(\"1\")\n")
	_write(directory.path_join("passive.tscn"), "[gd_scene load_steps=2 format=3]\n[ext_resource type=\"Resource\" path=\"res://resource_probe.tres\" id=\"1\"]\n[node name=\"Passive\" type=\"Node2D\"]\nmetadata/probe = ExtResource(\"1\")\n[node name=\"DummyProp\" type=\"Node2D\" parent=\".\"]\n")
	var contract := spec()
	contract.scene = "res://passive.tscn"
	contract.props = [{"node":"DummyProp", "blocking":true}]
	var manifest_path := directory + "-manifest.json"
	var report_path := directory + "-report.json"
	_write(manifest_path, JSON.stringify(contract))
	output.clear()
	var exit_code := OS.execute(OS.get_executable_path(), ["--headless", "--path", directory, "--script", "res://tools/check_worldbuilding.gd", "--", "--manifest", manifest_path, "--report", report_path], output, true)
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(report_path)) if FileAccess.file_exists(report_path) else null
	var rejected := false
	if report is Dictionary:
		for issue: Dictionary in report.get("issues", []):
			rejected = rejected or issue.code == "unsafe_resource_dependency"
	check(exit_code == 1 and rejected, "scripted Resource dependency is rejected before loading content: " + str(output))
	check(not FileAccess.file_exists(marker), "scripted Resource _init never runs during passive preflight")

func finish() -> void:
	print("[Worldbuilding] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
