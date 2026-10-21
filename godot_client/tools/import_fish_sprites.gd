extends SceneTree
## Usage: Godot --headless --path godot_client --script res://tools/import_fish_sprites.gd
##        -- --source=<absolute batch directory> [--layout=<source_layout.json>] [--validate-only]
## Original pair_01.png ... pair_05.png files are never modified.

const SPECIES := ["Reedkip", "Marlo", "Bracken", "Kessa", "Veilfin", "Lumara", "Vesper", "Moonfin", "Velora", "Sunfish"]
const CELL_SIZE := 64
const VISIBLE_SIZE := 40
const OUTPUT_DIR := "res://Assets/Items/fish_001/inventory"
var _errors: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _fail(message: String) -> void:
	_errors.append(message)
	# Validation failures are expected tool results, not engine exceptions.
	print("[Fish importer] ERROR: ", message)


func _bounds_array(bounds: Rect2i) -> Array[int]:
	return [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]


func _pixel_stats(image: Image) -> Dictionary:
	var palette: Dictionary = {}
	var visible_pixels := 0
	var semitransparent_pixels := 0
	var bytes := image.get_data()
	for offset in range(0, bytes.size(), 4):
		var alpha := int(bytes[offset + 3])
		if alpha == 0:
			continue
		visible_pixels += 1
		if alpha < 255:
			semitransparent_pixels += 1
		var rgba := (int(bytes[offset]) << 24) | (int(bytes[offset + 1]) << 16) | (int(bytes[offset + 2]) << 8) | alpha
		palette[rgba] = true
	return {"visible_pixels": visible_pixels, "palette_colors": palette.size(), "semitransparent_pixels": semitransparent_pixels}


func _prepare_cell(cell: Image, species: String, source_name: String, cell_index: int, index: int, component_bounds: Rect2i = Rect2i()) -> Dictionary:
	var source_bounds := cell.get_used_rect()
	if not source_bounds.has_area():
		_fail("%s cell %d (%s) has no visible pixels." % [source_name, cell_index, species])
		return {}
	var is_component := component_bounds.has_area()
	var checked_bounds := component_bounds if is_component else source_bounds
	var checked_size := Vector2i(CELL_SIZE * 2, CELL_SIZE) if is_component else Vector2i(CELL_SIZE, CELL_SIZE)
	if checked_bounds.position.x <= 0 or checked_bounds.position.y <= 0 or checked_bounds.end.x >= checked_size.x or checked_bounds.end.y >= checked_size.y:
		_fail("%s selection %d (%s) touches a source edge at %s; check for clipped artwork before importing." % [source_name, cell_index, species, str(checked_bounds)])
		return {}
	var visible := cell.get_region(source_bounds)
	var resize_passes := 0
	# Recrop after nearest downsampling, which can remove a one-pixel extremum.
	# If that shrinks the visible bounds, a second nearest pass restores 40 px.
	for _attempt in range(2):
		var factor := float(VISIBLE_SIZE) / float(maxi(visible.get_width(), visible.get_height()))
		var width := maxi(1, roundi(float(visible.get_width()) * factor))
		var height := maxi(1, roundi(float(visible.get_height()) * factor))
		visible.resize(width, height, Image.INTERPOLATE_NEAREST)
		resize_passes += 1
		var resized_bounds := visible.get_used_rect()
		if not resized_bounds.has_area():
			_fail("%s disappeared during nearest normalization." % species)
			return {}
		visible = visible.get_region(resized_bounds)
		if maxi(visible.get_width(), visible.get_height()) == VISIBLE_SIZE:
			break
	if maxi(visible.get_width(), visible.get_height()) != VISIBLE_SIZE:
		_fail("%s could not be normalized to a visible longest side of %d px." % [species, VISIBLE_SIZE])
		return {}
	var normalized := Image.create(CELL_SIZE, CELL_SIZE, false, Image.FORMAT_RGBA8)
	normalized.fill(Color.TRANSPARENT)
	var offset := Vector2i(floori(float(CELL_SIZE - visible.get_width()) / 2.0), floori(float(CELL_SIZE - visible.get_height()) / 2.0))
	normalized.blit_rect(visible, Rect2i(Vector2i.ZERO, visible.get_size()), offset)
	var output_bounds := normalized.get_used_rect()
	if not output_bounds.has_area() or output_bounds.position.x <= 0 or output_bounds.position.y <= 0 or output_bounds.end.x >= CELL_SIZE or output_bounds.end.y >= CELL_SIZE:
		_fail("%s has invalid or edge-touching normalized bounds." % species)
		return {}
	var png := normalized.save_png_to_buffer()
	if png.is_empty():
		_fail("%s could not be encoded as PNG." % species)
		return {}
	var manifest := {
		"species": species,
		"source": source_name,
		"source_selection": "component" if is_component else "cell",
		"source_index": cell_index,
		"source_cell_bbox": _bounds_array(source_bounds),
		"source_pair_bbox": _bounds_array(component_bounds) if is_component else [source_bounds.position.x + cell_index * CELL_SIZE, source_bounds.position.y, source_bounds.size.x, source_bounds.size.y],
		"source_stats": _pixel_stats(cell),
		"output": OUTPUT_DIR.path_join(species.to_lower() + ".png"),
		"output_bbox": _bounds_array(output_bounds),
		"output_stats": _pixel_stats(normalized),
		"resize_passes": resize_passes,
		"contact_sheet_cell": [index % 5, floori(float(index) / 5.0)]
	}
	return {"image": normalized, "png": png, "manifest": manifest}


func _source_components(pair: Image) -> Array[Dictionary]:
	# Connected masks preserve overlapping bounding boxes without taking pixels
	# from a neighboring fish. Selection is explicit in the reviewed source layout.
	var width := pair.get_width()
	var height := pair.get_height()
	var bytes := pair.get_data()
	var visited := PackedByteArray()
	visited.resize(width * height)
	visited.fill(0)
	var components: Array[Dictionary] = []
	for start in range(width * height):
		if visited[start] != 0 or bytes[start * 4 + 3] == 0:
			continue
		var queue: Array[int] = [start]
		var pixels: Array[int] = []
		visited[start] = 1
		var cursor := 0
		var low := Vector2i(width, height)
		var high := Vector2i.ZERO
		while cursor < queue.size():
			var pixel := queue[cursor]
			cursor += 1
			pixels.append(pixel)
			var x := pixel % width
			var y := floori(float(pixel) / float(width))
			low = Vector2i(mini(low.x, x), mini(low.y, y))
			high = Vector2i(maxi(high.x, x), maxi(high.y, y))
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= width or ny >= height:
						continue
					var next := ny * width + nx
					if visited[next] == 0 and bytes[next * 4 + 3] > 0:
						visited[next] = 1
						queue.append(next)
		if pixels.size() <= 10:
			continue
		var bounds := Rect2i(low, high - low + Vector2i.ONE)
		var mask := Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
		mask.fill(Color.TRANSPARENT)
		for pixel in pixels:
			var point := Vector2i(pixel % width, floori(float(pixel) / float(width)))
			mask.set_pixelv(point - low, pair.get_pixelv(point))
		components.append({"image": mask, "bounds": bounds})
	components.sort_custom(_component_left_to_right)
	return components


func _component_left_to_right(a: Dictionary, b: Dictionary) -> bool:
	var first: Rect2i = a.bounds
	var second: Rect2i = b.bounds
	return first.position.x < second.position.x if first.position.x != second.position.x else first.position.y < second.position.y


func _read_layout(path: String) -> Dictionary:
	var result := {}
	if not FileAccess.file_exists(path):
		_fail("Source layout does not exist.")
		return result
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or int(data.get("schema_version", 0)) != 1:
		_fail("Source layout must be a version-1 JSON object.")
		return result
	var rows: Variant = data.get("pairs")
	if not rows is Array or rows.size() != 5:
		_fail("Source layout must describe exactly five pairs.")
		return result
	for index in range(5):
		var row: Variant = rows[index]
		var expected_file := "pair_%02d.png" % (index + 1)
		if not row is Dictionary or String(row.get("file", "")) != expected_file:
			_fail("Source layout pair order must match pair_01.png through pair_05.png.")
			continue
		var names: Variant = row.get("species")
		var picks: Variant = row.get("components")
		if not names is Array or names.size() != 2 or not picks is Array or picks.size() != 2:
			_fail(expected_file + " must name two species and two component indices.")
			continue
		for slot in range(2):
			if String(names[slot]) != SPECIES[index * 2 + slot]:
				_fail(expected_file + " species do not match the approved roster order.")
			if typeof(picks[slot]) not in [TYPE_INT, TYPE_FLOAT] or float(picks[slot]) != float(int(picks[slot])) or int(picks[slot]) < 0:
				_fail(expected_file + " component indices must be nonnegative integers.")
		if picks[0] == picks[1]:
			_fail(expected_file + " cannot select the same component for two species.")
		result[expected_file] = row
	return result


func _write_png(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("Cannot open output %s (error %d)." % [path, FileAccess.get_open_error()])
		return false
	file.store_buffer(bytes)
	var error := file.get_error()
	file.close()
	if error != OK:
		_fail("Cannot finish writing %s (error %d)." % [path, error])
		return false
	return true


func _run() -> void:
	var source_dir := ""
	var layout_path := ""
	var validate_only := false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--source="):
			source_dir = argument.trim_prefix("--source=")
		elif argument.begins_with("--layout="):
			layout_path = argument.trim_prefix("--layout=")
		elif argument == "--validate-only":
			validate_only = true
		else:
			_fail("Unknown argument: " + argument)
	if source_dir.is_empty() or not source_dir.is_absolute_path() or not DirAccess.dir_exists_absolute(source_dir):
		_fail("Supply --source=<absolute existing batch directory> containing pair_01.png ... pair_05.png.")
	var layout := _read_layout(layout_path) if not layout_path.is_empty() else {}
	if not _errors.is_empty():
		quit(2)
		return
	var prepared: Array[Dictionary] = []
	for pair_index in range(5):
		var source_name := "pair_%02d.png" % (pair_index + 1)
		var source_path := source_dir.path_join(source_name)
		if not FileAccess.file_exists(source_path):
			_fail("Missing source image: " + source_name)
			continue
		var pair := Image.load_from_file(source_path)
		if pair == null or pair.is_empty():
			_fail("Cannot read source image: " + source_name)
			continue
		if pair.get_size() != Vector2i(CELL_SIZE * 2, CELL_SIZE):
			_fail("%s must be 128 x 64, received %s." % [source_name, str(pair.get_size())])
			continue
		pair.convert(Image.FORMAT_RGBA8)
		var components := _source_components(pair) if not layout_path.is_empty() else []
		for cell_index in range(2):
			var index := pair_index * 2 + cell_index
			var entry: Dictionary
			if not layout_path.is_empty():
				var selected := int(layout[source_name].components[cell_index])
				if selected >= components.size():
					_fail("%s component %d is missing." % [source_name, selected])
					continue
				var component: Dictionary = components[selected]
				entry = _prepare_cell(component.image, SPECIES[index], source_name, selected, index, component.bounds)
			else:
				var cell := pair.get_region(Rect2i(cell_index * CELL_SIZE, 0, CELL_SIZE, CELL_SIZE))
				entry = _prepare_cell(cell, SPECIES[index], source_name, cell_index, index)
			if not entry.is_empty():
				prepared.append(entry)
	if not _errors.is_empty() or prepared.size() != SPECIES.size():
		print("[Fish importer] Validation failed; no final files were written.")
		quit(1)
		return
	if validate_only:
		print("[Fish importer] Validated all 10 fish; --validate-only wrote no files.")
		quit(0)
		return
	var output_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	if output_error != OK:
		_fail("Cannot create inventory output directory (error %d)." % output_error)
		quit(1)
		return
	var contact_sheet := Image.create(CELL_SIZE * 5, CELL_SIZE * 2, false, Image.FORMAT_RGBA8)
	contact_sheet.fill(Color.TRANSPARENT)
	var manifest_entries: Array[Dictionary] = []
	for index in range(prepared.size()):
		var entry := prepared[index]
		var manifest: Dictionary = entry.manifest
		if not _write_png(String(manifest.output), entry.png):
			quit(1)
			return
		contact_sheet.blit_rect(entry.image, Rect2i(0, 0, CELL_SIZE, CELL_SIZE), Vector2i((index % 5) * CELL_SIZE, floori(float(index) / 5.0) * CELL_SIZE))
		manifest_entries.append(manifest)
	if not _write_png(source_dir.path_join("contact_sheet.png"), contact_sheet.save_png_to_buffer()):
		quit(1)
		return
	contact_sheet.resize(CELL_SIZE * 15, CELL_SIZE * 6, Image.INTERPOLATE_NEAREST)
	if not _write_png(source_dir.path_join("contact_sheet_3x.png"), contact_sheet.save_png_to_buffer()):
		quit(1)
		return
	var manifest_file := FileAccess.open(source_dir.path_join("normalization.json"), FileAccess.WRITE)
	if manifest_file == null:
		_fail("Cannot write normalization.json (error %d)." % FileAccess.get_open_error())
		quit(1)
		return
	manifest_file.store_string(JSON.stringify({"schema_version": 1, "cell_size": CELL_SIZE, "visible_longest_side": VISIBLE_SIZE, "interpolation": "nearest", "species": manifest_entries}, "\t") + "\n")
	var manifest_error := manifest_file.get_error()
	manifest_file.close()
	if manifest_error != OK:
		_fail("Cannot finish normalization.json (error %d)." % manifest_error)
		quit(1)
		return
	print("[Fish importer] Imported 10 fish to %s; contact sheets and normalization.json saved beside untouched sources." % OUTPUT_DIR)
	quit(0)
