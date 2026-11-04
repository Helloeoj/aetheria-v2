extends SceneTree
## Authoring helper only: copies exact approved pixels into depth-sorted wall bands.
## The immutable complete backdrop stays installed underneath these overlays.
## No source resizing, color replacement, repainting or runtime script is used.
const SOURCE := "res://Assets/Maps/ValtherianMines/Approved/approved-map-v3.png"
const SOURCE_SHA := "8ddfeb0018110c36f3937592a09b378f61b9122d1d2f761eb4f6931dffedea90"
const ATLAS := "res://Assets/Maps/ValtherianMines/Approved/foreground.png"
const MANIFEST := "res://Assets/Maps/ValtherianMines/Approved/foreground-bands.json"
const SIZE := Vector2i(1703, 924)
const WALL_DEPTH := 32
const MIN_FLOOR_RUN := 8

static func build(layout: Dictionary) -> Node2D:
	var folder := Node2D.new()
	folder.name = "ApprovedForeground"
	folder.y_sort_enabled = true
	folder.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert(not data.is_empty(), "Missing approved foreground manifest; run authoring helper")
	var texture: Texture2D = load(ATLAS)
	assert(texture != null, "Missing approved foreground atlas")
	var world: Array = layout.get("world_size", [6144, 3328])
	var density := Vector2(float(world[0]) / SIZE.x, float(world[1]) / SIZE.y)
	for record in data["bands"]:
		var source_rect: Array = record["source_rect"]
		var atlas_rect: Array = record["atlas_rect"]
		var foot := float(record["foot_source_y"])
		var band := Node2D.new()
		band.name = record["name"]
		band.position = Vector2(0, foot * density.y)
		band.y_sort_enabled = false
		band.set_meta("approved_source_rect", source_rect)
		band.set_meta("approved_foot_source_y", foot)
		var sprite := Sprite2D.new()
		sprite.name = "ExactPixels"
		sprite.texture = texture
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.region_enabled = true
		sprite.region_filter_clip_enabled = true
		sprite.region_rect = Rect2(atlas_rect[0], atlas_rect[1], atlas_rect[2], atlas_rect[3])
		# Keep the global transform origin identical to the complete backdrop.
		# Native offset is applied before scale; translated world-space crops can
		# round to different sample columns at particular actual camera4x views.
		sprite.position = Vector2(0, -foot * density.y)
		sprite.offset = Vector2(source_rect[0], source_rect[1])
		sprite.scale = density
		band.add_child(sprite)
		folder.add_child(band)
	# Caller must set owner on all returned descendants to its PackedScene root.
	return folder

func _initialize() -> void:
	_generate.call_deferred()

func _generate() -> void:
	var mask_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--floor-mask="):
			mask_path = arg.trim_prefix("--floor-mask=")
	if mask_path.is_empty():
		printerr("Pass --floor-mask=<reviewed source-size floor-positive PNG>; candidate masks are not accepted")
		quit(1)
		return
	var source := Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	var floor_image := Image.load_from_file(mask_path)
	if source == null or floor_image == null or source.get_size() != SIZE or floor_image.get_size() != SIZE:
		printerr("Approved source and reviewed floor mask must both be exactly ", SIZE)
		quit(1)
		return
	if FileAccess.get_sha256(SOURCE) != SOURCE_SHA:
		printerr("Approved source hash differs; refusing to derive overlays")
		quit(1)
		return
	source.convert(Image.FORMAT_RGBA8)
	floor_image.convert(Image.FORMAT_RGBA8)
	var source_bytes := source.get_data()
	for i in range(3, source_bytes.size(), 4):
		if source_bytes[i] != 255:
			printerr("Backdrop must be opaque for exact duplicate-pixel overlay proof")
			quit(1)
			return
	var mask_bytes := floor_image.get_data()
	var floor_bits := PackedByteArray()
	floor_bits.resize(SIZE.x * SIZE.y)
	for p in floor_bits.size():
		floor_bits[p] = int(mask_bytes[p * 4] >= 128 and mask_bytes[p * 4 + 3] >= 128)
	var groups: Array[Dictionary] = []
	for x in SIZE.x:
		var y := 0
		while y < SIZE.y:
			if floor_bits[y * SIZE.x + x] == 0:
				y += 1
				continue
			var start := y
			while y < SIZE.y and floor_bits[y * SIZE.x + x] != 0:
				y += 1
			if y >= SIZE.y or y - start < MIN_FLOOR_RUN:
				continue
			var bottom := mini(y + WALL_DEPTH, SIZE.y)
			for row in range(y + 1, bottom):
				if floor_bits[row * SIZE.x + x] != 0:
					bottom = row
					break
			var chosen := -1
			var delta := 9
			for index in groups.size():
				var g: Dictionary = groups[index]
				var candidate := absi(int(g["last_top"]) - y)
				if g["last_x"] == x - 1 and candidate < delta:
					chosen = index
					delta = candidate
			if chosen == -1:
				groups.append({"columns": [], "last_x": x, "last_top": y})
				chosen = groups.size() - 1
			groups[chosen]["columns"].append([x, y, bottom])
			groups[chosen]["last_x"] = x
			groups[chosen]["last_top"] = y
	var pieces: Array[Dictionary] = []
	var shelf_x := 0
	var shelf_y := 0
	var shelf_height := 0
	var copied := 0
	var mismatch := 0
	for group in groups:
		var columns: Array = group["columns"]
		if columns.size() < 4:
			continue
		var left := int(columns[0][0])
		var right := int(columns[-1][0]) + 1
		var top := SIZE.y
		var bottom := 0
		var foot := 0
		for column in columns:
			top = mini(top, column[1])
			bottom = maxi(bottom, column[2])
			# This dark-void observation sets only the sort anchor, never colors,
			# alpha, physical geometry, or which source wall pixels are copied.
			for row in range(column[1], column[2]):
				var pixel := source.get_pixel(column[0], row)
				if maxf(pixel.r, maxf(pixel.g, pixel.b)) > 0.10:
					foot = maxi(foot, row + 1)
		var width := right - left
		var height := bottom - top
		if foot == 0:
			continue
		if shelf_x + width > SIZE.x:
			shelf_x = 0
			shelf_y += shelf_height + 2
			shelf_height = 0
		var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		for column in columns:
			for row in range(column[1], column[2]):
				var color := source.get_pixel(column[0], row)
				image.set_pixel(column[0] - left, row - top, color)
				copied += 1
		var record := {"name": "FrontWall%03d" % pieces.size(), "source_rect": [left, top, width, height],
			"atlas_rect": [shelf_x, shelf_y, width, height], "foot_source_y": foot,
			"image": image}
		pieces.append(record)
		shelf_x += width + 2
		shelf_height = maxi(shelf_height, height)
	var atlas := Image.create(SIZE.x, shelf_y + shelf_height, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	var records: Array = []
	for piece in pieces:
		var rect: Array = piece["atlas_rect"]
		var image: Image = piece["image"]
		atlas.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(rect[0], rect[1]))
		var src: Array = piece["source_rect"]
		for y in image.get_height():
			for x in image.get_width():
				var pixel := image.get_pixel(x, y)
				if pixel.a > 0 and pixel != source.get_pixel(src[0] + x, src[1] + y):
					mismatch += 1
		piece.erase("image")
		records.append(piece)
	if mismatch != 0 or records.is_empty():
		printerr("Lossless band proof failed; mismatches=", mismatch, " bands=", records.size())
		quit(1)
		return
	var saved := atlas.save_png(ProjectSettings.globalize_path(ATLAS))
	var manifest := {"schema": 1, "source": SOURCE,
		"source_sha256": FileAccess.get_sha256(SOURCE), "source_size": [SIZE.x, SIZE.y],
		"floor_mask_sha256": FileAccess.get_sha256(mask_path), "atlas": ATLAS,
		"atlas_size": [atlas.get_width(), atlas.get_height()], "copied_exact_rgba_pixels": copied,
		"source_rgba_mismatches": mismatch, "source_was_opaque": true,
		"method": "Reviewed visible-floor south transitions locate continuous terrain bands. Exact RGBA copied; no resize, color replacement, alpha cleanup or hidden-floor repaint. Complete immutable source remains the backdrop. These are terrain overlays, not reusable mined-rock props.",
		"bands": records}
	var file := FileAccess.open(MANIFEST, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
	file.close()
	print("Approved exact-pixel foreground: ", records.size(), " bands, ", copied,
		" native pixels, ", mismatch, " RGBA differences; atlas ", atlas.get_size(), "; save=", saved)
	quit(0 if saved == OK else 1)
