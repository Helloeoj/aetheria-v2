extends "res://scripts/dev_tools/golem_titan_animation_review.gd"
## Actual-map review only. No production scene, encounter or combat edits.
const FIXTURE := "res://scenes/dev_tools/titan_spike_world_review.tscn"
const TICK_MS := int(GameTickConfig.TICK_DURATION_SECONDS * 1000.0)
const STEP_MS := int(TICK_MS / 30.0)
const SAMPLE_COUNT := 150
const WARNING_MS := TICK_MS * 2
const SLAM_OFFSET_MS := WARNING_MS - 1020
var spikes: Array[Node2D] = []
var target_cells: Array[Vector2i] = []
var escape_position := Vector2.ZERO
var route_checks: Array[Dictionary] = []

func _choose_floor() -> bool:
	if not super._choose_floor():
		return false
	player_position = (player_position / 32.0).floor() * 32.0 + Vector2(16,16)
	escape_position = player_position + Vector2(32,0)
	return _clear(player_position, Vector2(24,24)) and _clear(escape_position, Vector2(24,24))

func _capture_clip(clip: String, definition: Dictionary) -> void:
	if clip != "shockwave_slam":
		return
	# Render the exact authored scene named by the worldbuilding contract.
	content.get_parent().remove_child(content)
	content.queue_free()
	var fixture := (load(FIXTURE) as PackedScene).instantiate()
	titan.get_parent().add_child(fixture)
	content = fixture.get_node("Map")
	await physics_frame
	await physics_frame
	var start_cell := Vector2i((player_position / 32.0).floor())
	var offsets := [Vector2i(0,0), Vector2i(-3,-1), Vector2i(2,-1), Vector2i(-1,1), Vector2i(3,1),
		Vector2i(-2,2), Vector2i(2,2), Vector2i(-4,1), Vector2i(4,2), Vector2i(-3,3)]
	for delta: Vector2i in offsets:
		var cell := start_cell + delta
		var point := Vector2(cell) * 32.0 + Vector2(16,16)
		if not _clear(point, Vector2(32,32)):
			_fail("Declared spike cell is not wholly on clear actual floor: " + str(cell))
			return
		target_cells.append(cell)
		var effect := fixture.get_node("SpikeCells/Spike%02d" % spikes.size()) as Node2D
		if effect.global_position != point:
			_fail("Authored fixture placement differs from captured cell contract")
			return
		spikes.append(effect)
	# Real 24px body sweep for the marked-cell escape; not a point-only route.
	var shape := RectangleShape2D.new()
	shape.size = Vector2(24,24)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0, player_position)
	query.motion = escape_position - player_position
	query.collision_mask = 1
	var fraction := viewport.world_2d.direct_space_state.cast_motion(query)
	var clear := fraction[0] >= 1.0 and not target_cells.has(start_cell + Vector2i(1,0))
	route_checks.append({"from":[player_position.x,player_position.y],"to":[escape_position.x,escape_position.y],"body_size":[24,24],"sweep_fraction":fraction[0],"destination_unmarked":true,"passed":clear})
	if not clear:
		_fail("Actual escape sweep is blocked or marked")
		return
	var frame_set := SpriteFrames.new()
	frame_set.add_animation(clip)
	frame_set.set_animation_loop(clip,false)
	var durations: Array = definition.durations_ms
	for index in durations.size():
		var path := asset_dir.path_join("shockwave_slam/frames/%02d.png" % index)
		frame_set.add_frame(clip,ImageTexture.create_from_image(Image.load_from_file(path)),float(durations[index])/1000.0)
	visual.sprite_frames = frame_set
	visual.animation = clip
	visual.pause()
	# Smooth render sampling between600ms tick events. Delay the unchanged slam
	#180ms so its1020ms contact lands at the two-tick warning boundary.
	for index in SAMPLE_COUNT:
		var time_ms := index * STEP_MS
		_sample_slam(time_ms,durations)
		for effect: Node2D in spikes:
			effect.sample_at_seconds(float(time_ms)/1000.0)
		player.position = player_position.lerp(escape_position,clampf((float(time_ms)-300.0)/250.0,0.0,1.0))
		await _spike_capture("ten-tiles",index,2.0, titan_position + Vector2(0,-10),time_ms)
		# Close review isolates ONE instance, with unchanged player alongside it.
		for i in spikes.size():
			if i > 0:
				spikes[i].hide()
		await _spike_capture("single-tile",index,4.0,player_position+Vector2(16,-16),time_ms)
		for effect: Node2D in spikes:
			effect.sample_at_seconds(float(time_ms)/1000.0)
	# Ground-cell debug is separate from artwork and uses actual sampled peak.
	_sample_slam(TICK_MS*3,durations)
	for effect: Node2D in spikes:
		effect.sample_at_seconds(GameTickConfig.TICK_DURATION_SECONDS*3.0)
	await _spike_capture("normal-zoom",0,1.0,titan_position+Vector2(0,-10),TICK_MS*3)
	var guide := SpikeGuide.new()
	guide.cells = target_cells
	titan.get_parent().add_child(guide)
	await _spike_capture("tile-guides",0,4.0,player_position+Vector2(0,16),TICK_MS*3)
	guide.queue_free()

func _sample_slam(time_ms: int,durations: Array) -> void:
	var slam_time_ms := maxi(0,time_ms-SLAM_OFFSET_MS)
	var cursor := 0
	for frame in durations.size():
		cursor += int(durations[frame])
		if slam_time_ms < cursor or frame == durations.size()-1:
			visual.frame = frame
			return

class SpikeGuide extends Node2D:
	var cells: Array[Vector2i] = []
	func _draw() -> void:
		for cell: Vector2i in cells:
			draw_rect(Rect2(Vector2(cell)*32.0,Vector2(32,32)),Color(1,0.1,0.1),false,0.5)

func _spike_capture(kind: String,index: int,zoom: float,center: Vector2,time_ms: int) -> void:
	camera.position = center
	camera.zoom = Vector2.ONE * zoom
	camera.force_update_scroll()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := output_dir.path_join(kind)
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("frame-%03d.png" % index)
	var rendered := viewport.get_texture().get_image()
	if rendered.save_png(path) != OK:
		_fail("Cannot save actual GPU image: " + path)
	captures.append({"path":path,"kind":kind,"time_ms":time_ms,"titan_frame":visual.frame,"duration_ms":STEP_MS,"zoom":zoom,"camera_world_xy":[center.x,center.y],"viewport":[viewport.size.x,viewport.size.y]})

func _review_metadata() -> Dictionary:
	var cells: Array = []
	for cell: Vector2i in target_cells:
		cells.append([cell.x,cell.y])
	return {"effect_scene":"res://scenes/Effects/TitanPhysicalSpike.tscn","effect_native_canvas":[48,64],"effect_anchor":[24,52],
		"actual_fixture_scene":FIXTURE,"fixture_sha256":FileAccess.get_sha256(FIXTURE),
		"affected_cell_size":[32,32],"captured_player_cell": [floori(player_position.x/32.0),floori(player_position.y/32.0)],
		"effect_cells":cells,"route_checks":route_checks,"pattern_scope":"Fixed development fixture only; production engine chooses cells.",
		"tick_ms":TICK_MS,"warning_ms":WARNING_MS,"slam_start_offset_ms":SLAM_OFFSET_MS,"slam_contact_ms":WARNING_MS,
		"spike_peak_ms":TICK_MS*3,"first_lower_frame_ms":TICK_MS*3+STEP_MS,"spike_gone_ms":TICK_MS*4,"cleanup_done_ms":TICK_MS*4+STEP_MS*6,
		"sample_interval_ms":STEP_MS,"sample_count":SAMPLE_COUNT,"preview_duration_ms":STEP_MS*SAMPLE_COUNT,
		"passive_worldbuilding_status":"Animated scripted effects outside current validator scope; no world placement changed."}
