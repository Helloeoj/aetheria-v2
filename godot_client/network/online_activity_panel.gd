class_name OnlineActivityPanel
extends PanelContainer
## Presentation and input only. The region owns inventory, rewards, RNG and timers.
var game: Node
var _network: Node
var _station_id := ""
var _kind := ""
var _poll_elapsed := 0.0
var _left := false
var _right := false
var _inventory_signature := ""
var _network_message := ""
var _fish_lane: Control
var _heading: Label
var _status: Label
var _phase: Label
var _details: Label
var _meter: ProgressBar
var _line_meter: ProgressBar
var _rod: OptionButton
var _bait: OptionButton
var _raw: OptionButton
var _act_button: Button
var _cook_one: Button
var _cook_all: Button
var _fish_controls: VBoxContainer
var _cook_controls: VBoxContainer
var _pale_controls: HBoxContainer
var _pale_buttons: Array[Button] = []
var _modal_canvas: CanvasLayer
var _previous_canvas_layer := 0
class FishLane extends Control:
	var lateral := 0.0
	var boundary := 0.4
	var limit := 0.64
	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		draw_style_box(FantasyUI.box(FantasyUI.INK, FantasyUI.MUTED), rect)
		var scale := size.x * 0.5 / maxf(0.01,limit)
		var safe_width := minf(size.x,boundary * scale * 2)
		var safe := Rect2(Vector2((size.x-safe_width)*0.5,3),Vector2(safe_width,maxf(1,size.y-6)))
		draw_rect(safe,Color("315846"))
		draw_line(Vector2(size.x*0.5,3),Vector2(size.x*0.5,size.y-3),FantasyUI.GOLD,1)
		var marker := Vector2(clampf(size.x*0.5+lateral*scale,4,size.x-4),size.y*0.5)
		draw_circle(marker,5,FantasyUI.GOLD if absf(lateral) <= boundary else Color("ef7564"))

var is_open: bool:
	get:
		return visible

func configure(owner_game: Node) -> void:
	game = owner_game
	_network = get_node_or_null("/root/Network")
	if _network != null and _network.has_signal("status_changed"):
		_network.connect("status_changed",_on_network_status)
	theme = FantasyUI.make_theme()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", FantasyUI.frame_style())
	custom_minimum_size = Vector2(580, 440)
	var margin := MarginContainer.new()
	for side: String in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	_heading = _label("Activity", top, 25)
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button("Close [Esc]", close, top)
	_phase = _label("Choose your supplies.", box, 16)
	_phase.add_theme_color_override("font_color", FantasyUI.GOLD)
	_fish_controls = VBoxContainer.new()
	_fish_controls.add_theme_constant_override("separation",8)
	box.add_child(_fish_controls)
	var tackle := HBoxContainer.new()
	_fish_controls.add_child(tackle)
	_rod = OptionButton.new()
	_rod.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tackle.add_child(_rod)
	_bait = OptionButton.new()
	_bait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tackle.add_child(_bait)
	var steering := HBoxContainer.new()
	_fish_controls.add_child(steering)
	var left := _button("Hold left [A / ←]", Callable(), steering)
	left.button_down.connect(func() -> void: _left = true)
	left.button_up.connect(func() -> void: _left = false)
	var right := _button("Hold right [D / →]", Callable(), steering)
	right.button_down.connect(func() -> void: _right = true)
	right.button_up.connect(func() -> void: _right = false)
	_cook_controls = VBoxContainer.new()
	_cook_controls.add_theme_constant_override("separation",8)
	box.add_child(_cook_controls)
	_raw = OptionButton.new()
	_raw.custom_minimum_size.y = 34
	_cook_controls.add_child(_raw)
	var cook_row := HBoxContainer.new()
	_cook_controls.add_child(cook_row)
	_cook_one = _button("Cook 1", _cook.bind(false), cook_row)
	_cook_all = _button("Cook all", _cook.bind(true), cook_row)
	_details = _label("", box, 14)
	_details.custom_minimum_size.y = 38
	_meter = ProgressBar.new()
	_meter.custom_minimum_size.y = 22
	_meter.show_percentage = false
	box.add_child(_meter)
	_line_meter = ProgressBar.new()
	_line_meter.custom_minimum_size.y = 16
	_line_meter.show_percentage = false
	box.add_child(_line_meter)
	_fish_lane = FishLane.new()
	_fish_lane.custom_minimum_size.y = 34
	box.add_child(_fish_lane)
	_status = _label("", box, 15)
	_status.custom_minimum_size.y = 42
	_act_button = _button("Start [Space / Enter]", _act, box)
	_act_button.add_theme_font_size_override("font_size", 20)
	_pale_controls = HBoxContainer.new()
	_pale_controls.add_theme_constant_override("separation",4)
	box.add_child(_pale_controls)
	for slot in range(PlayerState.FISHING_PALE_SIZE):
		var button := _button("Empty", _move_pale.bind(slot), _pale_controls)
		button.add_theme_font_size_override("font_size",11)
		button.custom_minimum_size = Vector2(70,32)
		button.tooltip_text = "Move this fish from your pale into your backpack."
		_pale_buttons.append(button)
	hide()

func open_station(station_id: String, kind: String, title: String = "") -> void:
	if visible:
		close()
	if kind not in ["fish", "cook"]:
		return
	_station_id = station_id
	_kind = kind
	_left = false
	_right = false
	_inventory_signature = ""
	_network_message = ""
	_heading.text = title if not title.is_empty() else ("Fishing" if kind == "fish" else "Cooking")
	_fish_controls.visible = kind == "fish"
	_cook_controls.visible = kind == "cook"
	_line_meter.visible = kind == "fish"
	_fish_lane.visible = kind == "fish"
	_pale_controls.visible = kind == "fish"
	_raise_modal_canvas()
	show()
	_layout()
	_refresh()

func close() -> void:
	if visible:
		_send({"type":"fish_stop" if _kind == "fish" else "cook_cancel"})
	_left = false
	_right = false
	_rod.get_popup().hide()
	_bait.get_popup().hide()
	_raw.get_popup().hide()
	hide()
	_restore_modal_canvas()

func _raise_modal_canvas() -> void:
	var canvas := game.get_node_or_null("UI") as CanvasLayer
	var social_canvas := get_node_or_null("/root/Social/SocialOverlay") as CanvasLayer
	if canvas == null or social_canvas == null:
		return
	_modal_canvas = canvas
	_previous_canvas_layer = canvas.layer
	canvas.layer = maxi(canvas.layer, social_canvas.layer + 1)

func _restore_modal_canvas() -> void:
	if is_instance_valid(_modal_canvas):
		_modal_canvas.layer = _previous_canvas_layer
	_modal_canvas = null

func _exit_tree() -> void:
	_restore_modal_canvas()

func handle_key(event: InputEventKey) -> void:
	if not visible or event.echo:
		return
	match event.keycode:
		KEY_A, KEY_LEFT:
			_left = event.pressed
		KEY_D, KEY_RIGHT:
			_right = event.pressed
		KEY_ESCAPE:
			if event.pressed:
				close()
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			if event.pressed and not _act_button.disabled:
				_act()

func _process(delta: float) -> void:
	if not visible:
		return
	_poll_elapsed += delta
	if _poll_elapsed < 0.1:
		return
	_poll_elapsed = 0.0
	_layout()
	_refresh()
	var activity := _activity()
	if _kind == "fish" and int(activity.get("state",-1)) == 5:
		_send({"type":"fish_input", "steering":float(int(_right) - int(_left))})

func _layout() -> void:
	# The map's UI root already scales logical coordinates to the viewport.
	# Using physical pixels here applies that scale twice on larger displays.
	var viewport_size := get_viewport_rect().size
	if get_parent() is Control:
		viewport_size = (get_parent() as Control).size
	# Wrapped labels can briefly request a tall panel before their first layout.
	# Containers grow automatically, so explicitly shrink back to the current
	# content minimum as well as updating the width on later layout passes.
	size = Vector2(minf(620, maxf(380, viewport_size.x - 32)), get_combined_minimum_size().y)
	position = Vector2((viewport_size.x - size.x) * 0.5, maxf(16, (viewport_size.y - size.y) * 0.5 - 75))

func _refresh() -> void:
	_refresh_inventory()
	var activity := _activity()
	var state := int(activity.get("state",-1))
	_status.text = String(activity.get("message", _network_message if not _network_message.is_empty() else "Choose owned supplies, then start."))
	_act_button.disabled = false
	if _kind == "fish":
		var names := ["Ready","Set cast power","Casting","Waiting for a bite","BITE — hook now!","Reel: pull against the fish","Catch landed","Line lost","Closed"]
		_phase.text = names[state] if state >= 0 and state < names.size() else "Choose your rod and bait"
		_act_button.text = "Set cast [Space / Enter]" if state == 1 else "HOOK! [Space / Enter]" if state == 4 else "Cast again [Space / Enter]" if state in [0,6,7] else "Start fishing [Space / Enter]"
		_act_button.disabled = state in [2,3,5] or _rod.item_count == 0 or _bait.item_count == 0
		_rod.disabled = state in [1,2,3,4,5]
		_bait.disabled = _rod.disabled
		_meter.value = clampf(float(activity.get("power",0)),0,1) * 100 if state == 1 else clampf(float(activity.get("strain",0)),0,1) * 100
		var limit := maxf(0.01,float(activity.get("lateral_limit",1)))
		_fish_lane.set("lateral",float(activity.get("lateral",0)))
		_fish_lane.set("boundary",float(activity.get("boundary",0.4)))
		_fish_lane.set("limit",limit)
		_fish_lane.queue_redraw()
		_line_meter.value = clampf((float(activity.get("lateral",0)) / limit + 1) * 50,0,100)
		_details.text = "Power: %d%%  •  Line: %.1f / %.1f  •  Strain: %d%%\nKeep the fish centered. Hold A / D or the steering buttons." % [roundi(float(activity.get("power",0))*100),float(activity.get("remaining",0)),float(activity.get("distance",0)),roundi(float(activity.get("strain",0))*100)]
	else:
		var names := ["Ready","Cooking","FLIP NOW!","Result","Batch complete","Stopped"]
		_phase.text = names[state] if state >= 0 and state < names.size() else "Choose raw fish to cook"
		_act_button.text = "FLIP! [Space / Enter]"
		_act_button.disabled = state != 2
		var busy := state in [1,2,3]
		_cook_one.disabled = busy or _raw.item_count == 0
		_cook_all.disabled = _cook_one.disabled
		_raw.disabled = busy
		var window := float(activity.get("flip_window",0.8))
		var elapsed := float(activity.get("flip_elapsed",0))
		if state == 2:
			_meter.value = 100 if window < 0 else maxf(0,1 - elapsed / maxf(window,0.01)) * 100
			_details.text = "Flip at your pace — mastered recipe." if window < 0 else "Flip window: %.1f seconds left" % maxf(0,window-elapsed)
		else:
			var recipe := GameData.get_item_by_name(String(activity.get("raw_item", "")))
			_meter.value = clampf(float(activity.get("elapsed",0)) / maxf(0.01,float(recipe.get("cooking_seconds",1))),0,1) * 100 if state == 1 else 0
			_details.text = "%d remaining  •  %d cooked  •  %d burnt  •  +%d XP" % [int(activity.get("remaining",0)),int(activity.get("cooked_count",0)),int(activity.get("burnt_count",0)),int(activity.get("reward_xp",0))]

func _refresh_inventory() -> void:
	var player: PlayerState = game.get("player")
	if player == null:
		return
	var signature := var_to_str([player.backpack,player.fishing_pale,player.get_skill_level("fishing"),player.get_skill_level("cooking")])
	if signature == _inventory_signature:
		return
	_inventory_signature = signature
	_fill_picker(_rod,FishingSession.RODS,player,"fishing")
	_fill_picker(_bait,FishingSession.BAITS,player,"fishing")
	var raw_names: Array[String] = []
	for name: String in player.backpack:
		var item := GameData.get_item_by_name(name)
		if String(item.get("fish_state","")) == "raw" and int(item.get("cooking_level",101)) <= player.get_skill_level("cooking"):
			raw_names.append(name)
	raw_names.sort()
	_fill_picker(_raw,raw_names,player,"cooking")
	for slot in range(_pale_buttons.size()):
		var name := player.fishing_pale[slot] if slot < player.fishing_pale.size() else ""
		_pale_buttons[slot].text = name.trim_prefix("Raw ") if not name.is_empty() else "Empty"
		_pale_buttons[slot].disabled = name.is_empty()

func _fill_picker(picker: OptionButton, names: Array, player: PlayerState, skill: String) -> void:
	var selected := _selected(picker)
	picker.clear()
	for name: String in names:
		var count := int(player.backpack.get(name,0))
		var required := int(GameData.get_item_by_name(name).get(skill + "_level",1))
		if count <= 0 or player.get_skill_level(skill) < required:
			continue
		picker.add_item("%s ×%d" % [name,count])
		picker.set_item_metadata(picker.item_count-1,name)
		if name == selected:
			picker.select(picker.item_count-1)

func _selected(picker: OptionButton) -> String:
	return String(picker.get_item_metadata(picker.selected)) if picker.selected >= 0 else ""

func _act() -> void:
	var activity := _activity()
	if _kind == "fish":
		if activity.is_empty():
			_send({"type":"fish_start","station_id":_station_id,"rod":_selected(_rod),"bait":_selected(_bait)})
		else:
			_send({"type":"fish_input","action":"act"})
	elif int(activity.get("state",-1)) == 2:
		_send({"type":"cook_flip"})

func _cook(all_fish: bool) -> void:
	var name := _selected(_raw)
	if name.is_empty():
		return
	var player: PlayerState = game.get("player")
	_send({"type":"cook_start","station_id":_station_id,"item_name":name,"quantity":int(player.backpack.get(name,0)) if all_fish else 1})

func _move_pale(slot: int) -> void:
	_send({"type":"pale_move","slot":slot})

func _activity() -> Dictionary:
	if _network == null:
		return {}
	var snapshot: Variant = _network.get("latest_snapshot")
	if not snapshot is Dictionary:
		return {}
	var activity: Variant = snapshot.get("activity",{})
	if not activity is Dictionary or String(activity.get("kind","")) != _kind:
		return {}
	if activity.has("station_id") and String(activity.station_id) != _station_id:
		return {}
	return activity

func _send(command: Dictionary) -> void:
	if is_instance_valid(_network) and _network.has_method("send_action"):
		_network.send_action(command)

func _label(text: String, parent: Node, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",font_size)
	parent.add_child(label)
	return label

func _button(text: String, action: Callable, parent: Node) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 36
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	if action.is_valid():
		button.pressed.connect(action)
	parent.add_child(button)
	return button

func _on_network_status(message: String = "") -> void:
	_network_message = Network.status if message.is_empty() else message
	if visible and _activity().is_empty():
		_status.text = _network_message
