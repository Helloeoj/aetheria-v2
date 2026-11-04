extends SceneTree
## Scoped native-floor scale and actual4x macro-seam regression.
const HELPER := "res://scripts/dev_tools/valtherian_native_floor.gd"
const SOURCE := "res://Assets/Maps/ValtherianMines/Proofs/material-section-v1.png"
var output_dir := ""
var checks := 0
var failures := 0

func _initialize() -> void:
	output_dir = OS.get_user_data_dir().path_join("valtherian-floor-seams")
	var arguments := OS.get_cmdline_user_args()
	if not arguments.is_empty():
		output_dir = arguments[0]
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Valtherian floor FAIL] ", label)

func _run() -> void:
	check(FileAccess.file_exists(HELPER), "native floor helper exists")
	if failures > 0:
		quit(1)
		return
	var helper: Script = load(HELPER)
	var cells: Array = []
	for y in range(-1, 11):
		for x in range(-1, 25):
			cells.append([x, y])
	var floor_layer: TileMapLayer = helper.build(cells)
	check(floor_layer.get_used_cells().size() == cells.size(), "every requested floor cell exists")
	check(floor_layer.tile_set.tile_size == Vector2i(128, 128), "native artwork cell size128")
	check(floor_layer.scale == Vector2(0.25, 0.25), "declared source-to-world density0.25")
	check(floor_layer.position == Vector2.ZERO, "fixed shared grid origin")
	check(floor_layer.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "nearest filtering")
	check(floor_layer.z_index == -100, "floor remains beneath props")
	var center0 := floor_layer.to_global(floor_layer.map_to_local(Vector2i.ZERO))
	var center1 := floor_layer.to_global(floor_layer.map_to_local(Vector2i(1, 0)))
	check(center0.is_equal_approx(Vector2(16, 16)), "world cell center16,16")
	check(center1 - center0 == Vector2(32, 0), "native atlas gives32px physical cells")
	for cell: Vector2i in floor_layer.get_used_cells():
		var atlas := floor_layer.get_cell_atlas_coords(cell)
		check(atlas.x >= 0 and atlas.x < 12 and atlas.y >= 3 and atlas.y <= 7,
			"clean floor source region at " + str(cell))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1536, 1024)
	viewport.disable_3d = true
	viewport.world_2d = World2D.new()
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.position = Vector2i(-10000, -10000)
	root.size = Vector2i(320, 240)
	root.add_child(viewport)
	viewport.add_child(floor_layer)
	var camera := Camera2D.new()
	camera.position = Vector2(384, 160)
	camera.zoom = Vector2(4, 4)
	viewport.add_child(camera)
	camera.make_current()
	camera.force_update_scroll()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var rendered := viewport.get_texture().get_image()
	var x_mismatches := 0
	var y_mismatches := 0
	for y in range(rendered.get_height()):
		if rendered.get_pixel(767, y) != rendered.get_pixel(768, y):
			x_mismatches += 1
	for x in range(rendered.get_width()):
		if rendered.get_pixel(x, 511) != rendered.get_pixel(x, 512):
			y_mismatches += 1
	check(x_mismatches == 0, "actual4x vertical macro seam has no pixel jump")
	check(y_mismatches == 0, "actual4x horizontal macro seam has no pixel jump")
	var source_texture: Texture2D = load(SOURCE)
	var source := source_texture.get_image()
	for point: Vector2i in [Vector2i(20, 30), Vector2i(770, 35), Vector2i(45, 515), Vector2i(810, 545)]:
		var world := Vector2(192, 32) + Vector2(point) / 4.0
		var cell := Vector2i(floori(world.x / 32.0), floori(world.y / 32.0))
		var offset := point % Vector2i(128, 128)
		var alternative := floor_layer.get_cell_alternative_tile(cell)
		if alternative & TileSetAtlasSource.TRANSFORM_FLIP_H:
			offset.x = 127 - offset.x
		if alternative & TileSetAtlasSource.TRANSFORM_FLIP_V:
			offset.y = 127 - offset.y
		var texel := floor_layer.get_cell_atlas_coords(cell) * 128 + offset
		check(rendered.get_pixelv(point) == source.get_pixelv(texel), "actual4x preserves native source texel " + str(point))
	DirAccess.make_dir_recursive_absolute(output_dir)
	check(rendered.save_png(output_dir.path_join("valtherian-floor-seams-4x.png")) == OK, "save floor-only4x evidence")
	var actor := ActorSprite.new().configure(Vector2(32, 32), Color.BLUE, "native_floor_quality_check_only")
	viewport.add_child(actor)
	actor.position = Vector2(400, 208)
	actor.set_process(false)
	actor.set_skin("peasant")
	actor.animated_sprite.pause()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(output_dir.path_join("valtherian-floor-seams-4x-player.png")) == OK, "save actual4x with unchanged player")
	camera.zoom = Vector2.ONE
	viewport.size = Vector2i(768, 320)
	camera.force_update_scroll()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(output_dir.path_join("valtherian-floor-seams-1x-player.png")) == OK, "save actual1x with unchanged player")
	var report := {"checks": checks, "failures": failures, "floor_cells": cells.size(),
		"physical_cell_pixels": 32, "native_cell_pixels": 128, "density": 0.25,
		"source_rows": [3, 7], "vertical_macro_seam_pixel_mismatches": x_mismatches,
		"horizontal_macro_seam_pixel_mismatches": y_mismatches,
		"scope": "native floor helper and actual floor-only macro boundaries; no full dungeon or prop placement certificate"}
	var file := FileAccess.open(output_dir.path_join("valtherian-floor-seam-check.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	print(JSON.stringify(report))
	viewport.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
