extends SceneTree
## Independent tile-VFX contract; no damage or boss authority.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("[Spike FAIL] ", label)

func _run() -> void:
	var path := "res://scenes/Effects/TitanPhysicalSpike.tscn"
	check(FileAccess.file_exists(path), "reusable single-tile effect exists")
	if failures.is_empty():
		var effect = load(path).instantiate()
		root.add_child(effect)
		check(not effect.visible, "new instance stays hidden until engine samples it")
		check(effect.sample_at_seconds(-0.1).phase == "inactive", "negative time is inactive")
		check(effect.sample_at_seconds(0.0).phase == "warning", "warning starts before impact")
		var tick := GameTickConfig.TICK_DURATION_SECONDS
		var warning := tick * 2.0
		check(effect.sample_at_seconds(warning-0.001).phase == "warning", "warning lasts two actual combat ticks")
		check(effect.sample_at_seconds(warning).phase == "eruption", "rise begins on warning's tick boundary")
		check(int(effect.sample_at_seconds(warning+tick-0.020).height_px) < 51, "rise takes a complete tick")
		var peak: Dictionary = effect.sample_at_seconds(warning+tick)
		var retract: Dictionary = effect.sample_at_seconds(warning+tick+0.020)
		check(int(peak.height_px) == 51 and int(retract.height_px) < 51, "one full peak then immediate retraction")
		check(int(effect.sample_at_seconds(warning+tick*2.0-0.100).height_px) > 0, "retraction remains visible over the next tick")
		check(int(effect.sample_at_seconds(warning+tick*2.0-0.001).height_px) > 0, "last visible pixel retracts at the tick boundary, not before it")
		check(int(effect.sample_at_seconds(warning+tick*2.0).height_px) == 0, "stone returns below floor exactly two ticks after rise starts")
		check(effect.sample_at_seconds(warning+tick*2.0+0.121).phase == "complete" and not effect.visible, "cleanup ends without a lingering hazard")
		var previous := 0
		var peak_count := 0
		var smooth := true
		var monotonic := true
		for step in 61:
			var sample: Dictionary = effect.sample_at_seconds(warning+float(step)*tick/30.0)
			var height := int(sample.height_px)
			smooth = smooth and absi(height-previous) <= 3
			monotonic = monotonic and (height >= previous if step <= 30 else height <= previous)
			if height == 51:
				peak_count += 1
			previous = height
		check(smooth and monotonic and peak_count == 1, "60 small eased motion steps replace the abrupt pop, without added peak dwell")
		check(effect.sample_at_seconds(0.5, 2.0).phase == "warning", "engine can choose warning duration")
		check(effect.sample_at_seconds(2.0, 2.0).phase == "eruption", "custom warning changes impact time")
		check(effect.sample_at_seconds(NAN).phase == "inactive", "invalid sample cannot flash a spike")
		var other = load(path).instantiate()
		root.add_child(other)
		other.sample_at_seconds(0.1)
		effect.sample_at_seconds(warning+tick)
		check(other.current_sample.phase == "warning", "each tile has independent playback state")
		check(other.get_node("Visual").texture == effect.get_node("Visual").texture, "all instances share one atlas")
		check(effect.get_node("Visual").offset == Vector2(-24,-52), "sprite uses declared ground anchor")
		check(effect.get_node("Visual").texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "native pixels use nearest filtering")
		var imported: Image = effect.get_node("Visual").texture.get_image()
		var source := Image.load_from_file(ProjectSettings.globalize_path("res://Assets/Effects/TitanPhysicalSpike/spike-atlas.png"))
		imported.convert(Image.FORMAT_RGBA8)
		source.convert(Image.FORMAT_RGBA8)
		var matches := imported.get_size() == source.get_size()
		if matches:
			for y in source.get_height():
				for x in source.get_width():
					var a := imported.get_pixel(x,y)
					var b := source.get_pixel(x,y)
					matches = matches and a.a == b.a and (b.a == 0.0 or a == b)
		check(matches, "actual imported atlas exactly matches current native alpha and visible RGB")
		check(not imported.has_mipmaps(), "loaded atlas has no mipmaps")
		check(effect.get_child_count() == 1 and not effect.has_method("apply_damage"), "VFX owns neither collision nor damage")
		other.queue_free()
		effect.queue_free()
	print("[Titan spike] ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
