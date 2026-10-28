extends RefCounted
## Native terrain only. The approved source stays untouched; every atlas
## region is from its clean lower floor, never its painted wall band.
## 128 artwork pixels at0.25density make one32-world-pixel gameplay cell.
## Alternate12x5 macro blocks reflect the FLOOR ONLY, preserving neighboring
## source pixels internally and duplicating the outer edge at each join.
## This removes color jumps without painting, filtering or blending pixels.
const SOURCE_TEXTURE := "res://Assets/Maps/ValtherianMines/Proofs/material-section-v1.png"
const ART_CELL := 128
const DENSITY := 0.25
const COLUMNS := 12
const FLOOR_ROWS := 5
const FIRST_FLOOR_ROW := 3

static func build(cells: Array) -> TileMapLayer:
	var texture: Texture2D = load(SOURCE_TEXTURE)
	assert(texture != null, "Approved Valtherian material source is missing")
	assert(texture.get_size() == Vector2(1536, 1024), "Preserve the approved native source dimensions")
	var atlas := TileSetAtlasSource.new()
	atlas.texture = texture
	atlas.texture_region_size = Vector2i(ART_CELL, ART_CELL)
	for y in range(FIRST_FLOOR_ROW, FIRST_FLOOR_ROW + FLOOR_ROWS):
		for x in range(COLUMNS):
			atlas.create_tile(Vector2i(x, y))
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(ART_CELL, ART_CELL)
	tiles.add_source(atlas, 0)
	var layer := TileMapLayer.new()
	layer.name = "NativeFloor"
	layer.tile_set = tiles
	layer.scale = Vector2(DENSITY, DENSITY)
	layer.position = Vector2.ZERO
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.z_index = -100
	layer.set_meta("gameplay_cell_pixels", 32)
	layer.set_meta("world_pixels_per_source_pixel", DENSITY)
	layer.set_meta("source_floor_rows", Vector2i(FIRST_FLOOR_ROW, FIRST_FLOOR_ROW + FLOOR_ROWS - 1))
	layer.set_meta("floor_repeat", "Mirrored12x5macro; only continuous floor pixels are reflected")
	for pair: Array in cells:
		assert(pair.size() == 2, "Floor cells must be integer[x,y] gameplay indices")
		var cell := Vector2i(int(pair[0]), int(pair[1]))
		var source_x := posmod(cell.x, COLUMNS * 2)
		var source_y := posmod(cell.y, FLOOR_ROWS * 2)
		var flags := 0
		if source_x >= COLUMNS:
			source_x = COLUMNS * 2 - 1 - source_x
			flags |= TileSetAtlasSource.TRANSFORM_FLIP_H
		if source_y >= FLOOR_ROWS:
			source_y = FLOOR_ROWS * 2 - 1 - source_y
			flags |= TileSetAtlasSource.TRANSFORM_FLIP_V
		layer.set_cell(cell, 0, Vector2i(source_x, FIRST_FLOOR_ROW + source_y), flags)
	return layer
