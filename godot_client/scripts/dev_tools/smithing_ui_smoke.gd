extends Node
## Real world stations, actual GUI clicks, quench timeline and optional captures.
var checks := 0
var failures := 0
var capture_dir := ""

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Smithing UI FAIL] " + label)

func _ready() -> void:
	# The headless display otherwise defaults to a 64px window, clipping GUI
	# input even though controls report their full minimum layout dimensions.
	get_tree().root.size = Vector2i(1280, 720)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_dir = argument.trim_prefix("--capture=")
	get_tree().create_timer(60.0).timeout.connect(func() -> void: get_tree().quit(1))
	_run.call_deferred()

func frames(count: int = 2) -> void:
	for index in range(count):
		await get_tree().process_frame

func capture(label: String) -> void:
	if capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(capture_dir.path_join(label + ".png"))

func click_at(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_tree().root.push_input(motion)
	await frames()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.position = point
		event.global_position = point
		event.pressed = pressed
		get_tree().root.push_input(event)
		await frames()

func _run() -> void:
	var world: Node = load("res://scenes/EastOutskirtsLayered.tscn").instantiate()
	get_tree().root.add_child(world)
	await frames(4)
	var game: Node = world.get_node("Combat")
	game.set_physics_process(false)
	var panel: Control = game.crafting_panel
	check("smithing" in panel, "Existing station panel owns Smithing UI")
	if failures > 0:
		_finish()
		return
	var anvil: Node2D
	var furnace: Node2D
	for station: Node in get_tree().get_nodes_in_group("crafting_station"):
		if station.station_id == "anvil": anvil = station
		if station.station_id == "furnace": furnace = station
	game.player.x = anvil.simulation_position.x
	game.player.y = anvil.simulation_position.y
	game.player.add_item("Bronze Ingot", 3)
	game.request_crafting(anvil)
	var button: Button
	for candidate: Node in panel.find_children("*", "Button", true, false):
		if candidate.get_meta("recipe_id", "") == "bronze_longsword": button = candidate
	check(button != null and not button.disabled, "Approved longsword remains accessible at real anvil")
	await frames()
	await click_at(button.get_global_rect().get_center())
	var minigame: Control = panel.smithing
	check(minigame.visible and minigame.session != null, "Recipe button opens guided forging")
	if minigame.session == null:
		_finish()
		return
	minigame.set_process(false)
	var session: RefCounted = minigame.session
	check(not game.player.backpack.has("Bronze Longsword") and game.player.backpack.get("Bronze Ingot", 0) == 0, "UI reserves bars and defers item award")
	await capture("forge-billet")
	var view: Control = minigame.workpiece
	var guard := 0
	while session.state == SmithingSession.State.FORGING and guard < 30:
		await click_at(view.get_global_rect().position + session.target_position() * view.size)
		guard += 1
		if guard == 6: await capture("forge-shaped")
	check(session.state == SmithingSession.State.QUENCHING, "Actual target clicks finish shaping")
	if session.state != SmithingSession.State.QUENCHING:
		printerr("[Smithing UI context] hits=", session.hits, " workpiece=", view.get_global_rect(), " target=", session.target_position())
	session.advance(0.4)
	minigame.refresh()
	await frames()
	await capture("quench-lowering")
	panel.close()
	check(session.state == SmithingSession.State.QUENCHING and not game.player.backpack.has("Bronze Longsword"), "Closing during quench cannot skip or duplicate rewards")
	game.request_crafting(anvil)
	check(minigame.session == session, "Reopening resumes the same quench")
	session.advance(0.7)
	minigame.refresh()
	await frames()
	check(view.hiss.playing, "Immersion plays reusable hiss audio")
	await capture("quench-steam")
	session.advance(1.8)
	minigame.refresh()
	await frames()
	check(view.finished_texture == ItemVisualLibrary.texture("Bronze Longsword"), "Quench uses actual inventory artwork")
	await capture("quench-rising")
	session.advance(2.0)
	minigame.refresh()
	check(game.player.backpack.get("Bronze Longsword", 0) == 1, "Animation completion grants exactly one item")
	await capture("quench-finished")
	panel.close()
	game.player.x = furnace.simulation_position.x
	game.player.y = furnace.simulation_position.y
	game.player.add_item("Bronze Ore", 10)
	game.request_crafting(furnace)
	check(panel.amount.max_value == 10, "Furnace batch picker is capped at ten")
	panel.amount.value = 10
	panel._craft("smelt_bronze")
	check(minigame.session != session and minigame.session.batch == 10, "Real furnace starts chosen ten-bar batch")
	await frames()
	var bellows_point: Vector2 = minigame.bellows.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = bellows_point
	Input.parse_input_event(motion)
	var press := InputEventMouseButton.new()
	press.position = bellows_point
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	Input.parse_input_event(press)
	await frames()
	minigame.advance(0.5)
	var raised: float = minigame.session.temperature
	press = press.duplicate()
	press.pressed = false
	Input.parse_input_event(press)
	await frames()
	minigame.advance(0.25)
	check(raised > 0.0 and minigame.session.temperature < raised, "Actual bellows press heats and release cools the furnace")
	await capture("smelting")
	minigame.session.temperature = 1.0
	panel.close()
	check(minigame.session.state == SmithingSession.State.SMELTING, "Closing a hot furnace leaves the same timer active")
	minigame.set_process(true)
	minigame.advance(10.0)
	check(minigame.session.state == SmithingSession.State.FAILED and not game.player.backpack.has("Bronze Ore"), "Hidden hot batch still burns its reserved ore")
	# Exercise actual scene teardown/recreation rather than holding a test-only
	# strong session reference across the transition.
	var retained_player: PlayerState = game.player
	game.request_crafting(furnace)
	retained_player.add_item("Bronze Ore")
	panel.amount.value = 1
	panel._craft("smelt_bronze")
	minigame.set_process(false)
	minigame.session.config.cooling_per_second = 0.0
	minigame.session.temperature = 0.6
	retained_player.backpack["Bronze Ingot"] = 9223372036854775807
	minigame.session.advance(10.0)
	check(minigame.session.state == SmithingSession.State.CLAIM_PENDING, "Overflow holds a completed batch before travel")
	var output_ref: WeakRef = weakref(minigame.session)
	world.queue_free()
	await frames()
	check(output_ref.get_ref() != null and retained_player.pending_smithing_session == output_ref.get_ref(), "Actual scene teardown retains pending reward")
	retained_player.backpack.erase("Bronze Ingot")
	world = load("res://scenes/EastOutskirtsLayered.tscn").instantiate()
	get_tree().root.add_child(world)
	await frames(4)
	game = world.get_node("Combat")
	game.set_physics_process(false)
	check(game.player == retained_player and retained_player.backpack.get("Bronze Ingot", 0) == 1 and retained_player.pending_smithing_session == null, "New area UI restores and settles pending output once")
	minigame = game.crafting_panel.smithing
	var refund_station: Node2D
	for candidate: Node in get_tree().get_nodes_in_group("crafting_station"):
		if candidate.station_id == "anvil": refund_station = candidate
	retained_player.x = refund_station.simulation_position.x
	retained_player.y = refund_station.simulation_position.y
	game.request_crafting(refund_station)
	game.crafting_panel._craft("bronze_dagger")
	minigame.set_process(false)
	retained_player.backpack["Bronze Ingot"] = 9223372036854775807
	var refund_ref: WeakRef = weakref(minigame.session)
	world.queue_free()
	await frames()
	check(refund_ref.get_ref() != null and retained_player.pending_smithing_session != null, "Actual teardown retains a blocked material refund")
	retained_player.backpack.erase("Bronze Ingot")
	world = load("res://scenes/EastOutskirtsLayered.tscn").instantiate()
	get_tree().root.add_child(world)
	await frames(4)
	check(retained_player.backpack.get("Bronze Ingot", 0) == 1 and retained_player.pending_smithing_session == null, "New area UI restores blocked refund without losing bars")
	world.queue_free()
	await frames()
	_finish()

func _finish() -> void:
	print("[Smithing UI] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
