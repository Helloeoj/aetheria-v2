extends SceneTree
## Exact floor coverage, including holes hidden between the body's corners.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Tile floor FAIL] ", label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var path := "res://scripts/dev_tools/tile_floor_support.gd"
	check(FileAccess.file_exists(path), "Authored floor support checker exists")
	if not FileAccess.file_exists(path):
		_finish()
		return
	var area := Node2D.new()
	root.add_child(area)
	var ground := TileMapLayer.new()
	ground.name = "Ground"
	var texture := GradientTexture2D.new()
	texture.width = 8
	texture.height = 8
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(8, 8)
	source.create_tile(Vector2i.ZERO)
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(8, 8)
	tiles.add_source(source, 0)
	ground.tile_set = tiles
	area.add_child(ground)
	for y in range(3):
		for x in range(3):
			ground.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
	var support = load(path).new()
	support.configure(area)
	check(support.supports_body(Vector2(12, 12)), "Full 24px body fits on native floor")
	ground.erase_cell(Vector2i.ONE)
	check(not support.supports_body(Vector2(12, 12)), "Interior void rejects even when every body corner has floor")
	ground.set_cell(Vector2i.ONE, 0, Vector2i.ZERO)
	ground.erase_cell(Vector2i(0, 1))
	check(not support.supports_body(Vector2(12, 12)), "Body edge crossing void rejects")
	var path_layer := TileMapLayer.new()
	path_layer.name = "PathsAndQuays"
	path_layer.tile_set = tiles
	area.add_child(path_layer)
	path_layer.set_cell(Vector2i(0, 1), 0, Vector2i.ZERO)
	support.configure(area)
	check(support.supports_body(Vector2(12, 12)), "Adjacent ground and path layers jointly support body")
	ground.erase_cell(Vector2i.ONE)
	path_layer.set_cell(Vector2i(2, 2), 0, Vector2i.ZERO)
	check(not support.supports_body(Vector2(12, 12)), "Overlapping floor elsewhere cannot compensate for a hole")
	ground.set_cell(Vector2i.ONE, 0, Vector2i.ZERO)
	area.position = Vector2(91, -30)
	area.scale = Vector2(3, 3)
	check(support.supports_body(area.to_global(Vector2(12, 12)), 36.0), "Authored parent scale and translation preserve floor coverage")
	check(not support.supports_body(area.to_global(Vector2(2, 2)), 36.0), "Scaled body cannot hang beyond floor boundary")
	ground.hide()
	check(not support.supports_body(area.to_global(Vector2(12, 12)), 36.0), "Hidden layers do not invent floor")
	area.free()
	var unknown := Node2D.new()
	root.add_child(unknown)
	support.configure(unknown)
	check(not support.supports_body(Vector2.ZERO), "No authored floor source fails closed")
	unknown.free()
	_finish()

func _finish() -> void:
	print("[Tile floor] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
