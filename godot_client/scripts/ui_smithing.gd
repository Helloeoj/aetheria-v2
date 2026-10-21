extends VBoxContainer
signal recipes_requested
## Embedded in the existing crafting panel; advances even while a hot batch is hidden.
const Session = preload("res://scripts/smithing_session.gd")
const Rules = preload("res://scripts/smithing_rules.gd")
var game: Node
var session: RefCounted
var workpiece: Control
var heat_gauge: Control
var progress_bar: ProgressBar
var notice: Label
var bellows: Button
var cancel_button: Button
var _bellows_held := false
var _reported_xp := 0

func configure(owner_game: Node) -> void:
	game = owner_game
	add_theme_constant_override("separation", 8)
	notice = Label.new()
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(notice)
	heat_gauge = Control.new()
	heat_gauge.custom_minimum_size = Vector2(660, 48)
	heat_gauge.draw.connect(_draw_heat)
	add_child(heat_gauge)
	workpiece = preload("res://scripts/smithing_workpiece.gd").new()
	add_child(workpiece)
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size.y = 24
	add_child(progress_bar)
	bellows = Button.new()
	bellows.text = "Hold bellows to raise heat"
	bellows.button_down.connect(func() -> void: _bellows_held = true)
	bellows.button_up.connect(func() -> void: _bellows_held = false)
	add_child(bellows)
	cancel_button = Button.new()
	cancel_button.text = "Cancel unfinished work / Back to recipes"
	cancel_button.pressed.connect(_cancel)
	add_child(cancel_button)
	if game.player.pending_smithing_session != null:
		session = game.player.pending_smithing_session
		workpiece.show_session(session)
	hide()

func begin(player: PlayerState, station: Node2D, recipe_id: String, quantity: int) -> String:
	if session != null and session.is_active():
		return "Finish the current Smithing work first."
	var next := Session.new(player, station, game.combat)
	var error := next.start(recipe_id, quantity)
	if not error.is_empty():
		return error
	session = next
	_reported_xp = 0
	workpiece.show_session(session)
	show()
	refresh()
	return ""

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if session == null:
		return
	session.advance(delta, _bellows_held and is_visible_in_tree() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	if session.reward_xp > _reported_xp:
		game.skill_training_session.record_event({"type": "skill_experience_gained", "skill": "smithing", "experience_gained": session.reward_xp - _reported_xp})
		_reported_xp = session.reward_xp
		game._refresh_character_ui()
	refresh()

func refresh() -> void:
	if session == null:
		return
	var smelting: bool = session.is_furnace_work()
	heat_gauge.visible = smelting
	bellows.visible = smelting
	workpiece.visible = not smelting
	progress_bar.value = 100.0 * (session.progress / maxf(0.01, session.duration) if smelting else float(session.hits) / float(maxi(1, session.total_hits())))
	notice.text = session.message
	if smelting and session.state == Session.State.SMELTING:
		var heat: Dictionary = session.heat_profile()
		var condition := "Too cold — progress paused" if session.temperature < heat.low else ("Too hot — progress paused" if session.temperature > heat.high else "Correct heat — smelting")
		notice.text = "%s × %d\n%s\nHeat: %d%% | Correct: %d–%d%% | %s" % [session.output_name, session.batch, condition, roundi(session.temperature * 100), roundi(heat.low * 100), roundi(heat.high * 100), "Burn immune (+30 mastery)" if heat.immune else "Overheat grace: %.1fs remaining" % maxf(0, heat.grace - session.overheated_seconds)]
	elif session.state == Session.State.FORGING:
		notice.text += "\n%s — stage %d/%d | hits %d/%d" % [session.output_name, session.shape_stage() + 1, int(session.config.shaping_stages), session.hits, session.total_hits()]
	cancel_button.disabled = session.state in [Session.State.QUENCHING, Session.State.CLAIM_PENDING]
	heat_gauge.queue_redraw()
	workpiece.refresh()

func _draw_heat() -> void:
	if session == null:
		return
	var area := Rect2(4, 4, heat_gauge.size.x - 8, 36)
	heat_gauge.draw_rect(area, Color("302d39"))
	var heat: Dictionary = session.heat_profile()
	heat_gauge.draw_rect(Rect2(area.position + Vector2(area.size.x * heat.low, 0), Vector2(area.size.x * (heat.high - heat.low), area.size.y)), Color("65562c"))
	heat_gauge.draw_rect(area, FantasyUI.GOLD, false, 2)
	var x: float = area.position.x + area.size.x * session.temperature
	heat_gauge.draw_line(Vector2(x, 0), Vector2(x, 44), Color("ff9f45"), 5)

func suspend() -> void:
	_bellows_held = false
	if session != null:
		session.cancel()

func _cancel() -> void:
	if session == null:
		return
	if session.state in [Session.State.SMELTING, Session.State.FORGING] and not session.cancel():
		refresh()
		return
	if session.state in [Session.State.QUENCHING, Session.State.CLAIM_PENDING]:
		return
	hide()
	recipes_requested.emit()

func _exit_tree() -> void:
	# Scene travel retains PlayerState. Settle the already completed object or
	# cool an abandoned hot batch using its actual rules before refunding.
	if session != null:
		if session.state == Session.State.QUENCHING:
			session.advance(session.quench_duration())
		elif not session.cancel() and session.state == Session.State.SMELTING:
			session.advance(30.0, false)
			session.cancel()
		# Unrepresentable output/refund stacks stay owned by persistent PlayerState.
		session.retain_for_later()
		if session.reward_xp > _reported_xp:
			game.skill_training_session.record_event({"type": "skill_experience_gained", "skill": "smithing", "experience_gained": session.reward_xp - _reported_xp})
			_reported_xp = session.reward_xp
