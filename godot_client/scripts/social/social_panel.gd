extends PanelContainer
## Presentation only; routing and relationship authority stay on the service.
var social: Node
var tabs: TabBar
var transcript: RichTextLabel
var composer: LineEdit
var destination: OptionButton
var recipient: LineEdit
var status_label: Label
var counter: Label
var drawer: PanelContainer
var drawer_tabs: TabContainer
var friend_list: ItemList
var block_list: ItemList
var target: LineEdit
var server_url: LineEdit
var display_name: LineEdit
var retry_button: Button
var background_alpha := 0.25
var failed_draft := ""
var unread := {"local": 0, "global": 0, "private": 0}
var filter := "all"
var last_render := ""
var pointer_passthrough := false
var original_mouse_filters: Dictionary = {}
const CHANNELS := ["all", "local", "global", "private"]

func configure(client: Node) -> void:
	social = client
	theme = FantasyUI.make_theme()
	add_theme_font_size_override("font_size", 14)
	mouse_filter = Control.MOUSE_FILTER_STOP
	background_alpha = float(social.preferences.get_value("settings", "opacity", 0.25))
	_apply_background()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	tabs = TabBar.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 14)
	for channel: String in CHANNELS:
		tabs.add_tab(channel.capitalize())
	tabs.tab_changed.connect(_filter_changed)
	header.add_child(tabs)
	header.add_child(_button("Friends", func() -> void: _open_drawer(0)))
	header.add_child(_button("Connect", func() -> void: _open_drawer(2)))
	transcript = RichTextLabel.new()
	transcript.name = "ChatHistory"
	transcript.size_flags_vertical = Control.SIZE_EXPAND_FILL
	transcript.bbcode_enabled = false
	transcript.selection_enabled = true
	transcript.scroll_following = true
	transcript.add_theme_font_size_override("normal_font_size", 15)
	transcript.add_theme_color_override("default_color", Color("eee7d6"))
	transcript.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	transcript.add_theme_constant_override("shadow_offset_x", 1)
	transcript.add_theme_constant_override("shadow_offset_y", 1)
	column.add_child(transcript)
	transcript.get_v_scroll_bar().value_changed.connect(_scroll_changed)
	var compose_row := HBoxContainer.new()
	column.add_child(compose_row)
	destination = OptionButton.new()
	destination.focus_mode = Control.FOCUS_NONE
	destination.add_theme_font_size_override("font_size", 13)
	for channel: String in ["Local", "Global", "Private"]:
		destination.add_item(channel)
	destination.item_selected.connect(_destination_changed)
	compose_row.add_child(destination)
	recipient = LineEdit.new()
	recipient.placeholder_text = "To player"
	recipient.custom_minimum_size.x = 105
	recipient.max_length = 20
	recipient.add_theme_font_size_override("font_size", 13)
	recipient.hide()
	compose_row.add_child(recipient)
	composer = LineEdit.new()
	composer.name = "ChatInput"
	composer.placeholder_text = "Press Enter to chat…"
	composer.tooltip_text = "Developer maps: ::help lists tile coordinates and teleport commands."
	composer.max_length = 280
	composer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	composer.add_theme_font_size_override("font_size", 14)
	composer.text_submitted.connect(_submit)
	composer.text_changed.connect(func(value: String) -> void: counter.text = str(value.length()) + "/280")
	compose_row.add_child(composer)
	counter = Label.new()
	counter.text = "0/280"
	counter.add_theme_font_size_override("font_size", 11)
	compose_row.add_child(counter)
	var bottom := HBoxContainer.new()
	column.add_child(bottom)
	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.clip_text = true
	status_label.add_theme_font_size_override("font_size", 12)
	bottom.add_child(status_label)
	retry_button = _button("Restore draft", func() -> void:
		composer.text = failed_draft
		failed_draft = ""
		composer.grab_focus()
		refresh())
	bottom.add_child(retry_button)
	_build_drawer()
	social.updated.connect(refresh)
	refresh()

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(action)
	return button

func _apply_background() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.035, 0.05, clampf(background_alpha, 0.1, 0.8))
	style.border_color = Color(0.65, 0.56, 0.4, 0.55)
	style.set_border_width_all(1)
	style.set_content_margin_all(7)
	add_theme_stylebox_override("panel", style)

func _build_drawer() -> void:
	drawer = PanelContainer.new()
	drawer.name = "SocialDrawer"
	drawer.theme = FantasyUI.make_theme()
	drawer.add_theme_stylebox_override("panel", FantasyUI.box(Color("15202c")))
	get_parent().add_child(drawer)
	drawer.hide()
	var box := VBoxContainer.new()
	drawer.add_child(box)
	var heading := HBoxContainer.new()
	box.add_child(heading)
	var title := Label.new()
	title.text = "Players & chat"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	heading.add_child(_button("Close", drawer.hide))
	drawer_tabs = TabContainer.new()
	drawer_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(drawer_tabs)
	for kind: String in ["Friends", "Blocked"]:
		var content := VBoxContainer.new()
		content.name = kind
		drawer_tabs.add_child(content)
		var list := ItemList.new()
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list.custom_minimum_size.y = 100
		list.add_theme_font_size_override("font_size", 15)
		content.add_child(list)
		var actions := HBoxContainer.new()
		content.add_child(actions)
		if kind == "Friends":
			friend_list = list
			list.item_activated.connect(func(index: int) -> void: _message_friend(index))
			actions.add_child(_button("Message", func() -> void:
				if not friend_list.get_selected_items().is_empty():
					_message_friend(friend_list.get_selected_items()[0])))
			actions.add_child(_button("Remove", func() -> void: _selected_action(friend_list, "friend_remove")))
			actions.add_child(_button("Block", func() -> void: _selected_action(friend_list, "block_add")))
		else:
			block_list = list
			actions.add_child(_button("Unblock", func() -> void: _selected_action(block_list, "block_remove")))
	var connection := VBoxContainer.new()
	connection.name = "Connection"
	drawer_tabs.add_child(connection)
	server_url = LineEdit.new()
	server_url.text = social.endpoint
	server_url.placeholder_text = "Chat server URL"
	server_url.max_length = 256
	connection.add_child(server_url)
	display_name = LineEdit.new()
	display_name.text = social.profile_name
	display_name.placeholder_text = "Player name (3-20 letters, numbers, underscores)"
	display_name.max_length = 20
	connection.add_child(display_name)
	var connection_actions := HBoxContainer.new()
	connection.add_child(connection_actions)
	connection_actions.add_child(_button("Connect", func() -> void:
		social.connect_chat(server_url.text, display_name.text)
		drawer.hide()))
	connection_actions.add_child(_button("Disconnect", social.disconnect_chat))
	connection_actions.add_child(_button("Start local server", func() -> void:
		social.start_local_server()
		social.connect_chat("ws://127.0.0.1:8765", display_name.text)
		drawer.hide()))
	var opacity_label := Label.new()
	opacity_label.text = "Chat background opacity"
	opacity_label.add_theme_font_size_override("font_size", 14)
	connection.add_child(opacity_label)
	var opacity := HSlider.new()
	opacity.min_value = 0.1
	opacity.max_value = 0.8
	opacity.step = 0.05
	opacity.value = background_alpha
	opacity.value_changed.connect(func(value: float) -> void:
		background_alpha = value
		_apply_background()
		social.preferences.set_value("settings", "opacity", value)
		social.preferences.save("user://social_profiles.cfg"))
	connection.add_child(opacity)
	var add_row := HBoxContainer.new()
	box.add_child(add_row)
	target = LineEdit.new()
	target.placeholder_text = "Player name"
	target.max_length = 20
	target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(target)
	add_row.add_child(_button("Add friend", func() -> void: social.request("friend_add", {"target": target.text.strip_edges()})))
	add_row.add_child(_button("Block", func() -> void: social.request("block_add", {"target": target.text.strip_edges()})))

func layout_drawer() -> void:
	if drawer == null:
		return
	drawer.scale = scale
	drawer.size = Vector2(size.x, 292)
	drawer.position = Vector2(position.x, maxf(8, position.y - 300 * scale.y))

func _open_drawer(tab: int) -> void:
	var should_open := not drawer.visible or drawer_tabs.current_tab != tab
	drawer_tabs.current_tab = tab
	drawer.visible = should_open
	layout_drawer()

func owns_control(control: Control) -> bool:
	return control != null and (control == self or is_ancestor_of(control) or control == drawer or drawer.is_ancestor_of(control))

func prepare_pointer(point: Vector2, game: Node) -> void:
	# Existing modal buttons can overlap this permanent HUD. Give those controls
	# their click unless the player is explicitly editing chat or using its drawer.
	var passthrough := false
	var focus := get_viewport().gui_get_focus_owner()
	var editing_chat := owns_control(focus) and (focus is LineEdit or focus is TextEdit)
	if not drawer.visible and not editing_chat and get_global_rect().has_point(point):
		var ui: Control = game.get("ui_root")
		if ui != null:
			for node: Node in ui.find_children("*", "Control", true, false):
				var control := node as Control
				if not control.is_visible_in_tree() or control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
					continue
				if (control is BaseButton or control is LineEdit or control is ItemList or control is TabBar or control is ScrollBar or control is Slider) and control.get_global_rect().has_point(point):
					passthrough = true
					break
	if pointer_passthrough == passthrough:
		return
	pointer_passthrough = passthrough
	if passthrough:
		var controls: Array[Node] = find_children("*", "Control", true, false)
		controls.append(self)
		for node: Node in controls:
			var control := node as Control
			original_mouse_filters[control] = control.mouse_filter
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		for control: Control in original_mouse_filters:
			control.mouse_filter = int(original_mouse_filters[control])
		original_mouse_filters.clear()

func _selected_action(list: ItemList, operation: String) -> void:
	if not list.get_selected_items().is_empty():
		var entry: Dictionary = list.get_item_metadata(list.get_selected_items()[0])
		social.request(operation, {"target": entry.name})

func _message_friend(index: int) -> void:
	var entry: Dictionary = friend_list.get_item_metadata(index)
	destination.select(2)
	_destination_changed(2)
	recipient.text = str(entry.name)
	drawer.hide()
	composer.grab_focus()

func _destination_changed(index: int) -> void:
	recipient.visible = index == 2

func clear_private_context() -> void:
	if recipient != null:
		recipient.clear()
		composer.clear()
		failed_draft = ""
		unread = {"local": 0, "global": 0, "private": 0}
		last_render = ""

func check_private_target() -> void:
	for entry: Dictionary in social.blocks:
		if str(entry.name).to_lower() == recipient.text.to_lower():
			recipient.clear()

func _submit(value: String) -> void:
	if value.strip_edges().is_empty():
		composer.release_focus()
		return
	if social.send_chat(["local", "global", "private"][destination.selected], value, recipient.text):
		composer.clear()
		counter.text = "0/280"
		composer.release_focus()

func _filter_changed(index: int) -> void:
	filter = CHANNELS[index]
	last_render = ""
	transcript.scroll_following = true
	_mark_read()
	refresh()

func _at_bottom() -> bool:
	var scroll := transcript.get_v_scroll_bar()
	return scroll.value + scroll.page >= scroll.max_value - 3.0

func _scroll_changed(_value: float) -> void:
	transcript.scroll_following = _at_bottom()
	if transcript.scroll_following:
		_mark_read()

func message_arrived(event: Dictionary) -> void:
	var channel := str(event.get("channel", "local"))
	if unread.has(channel) and ((filter != "all" and filter != channel) or not _at_bottom()):
		unread[channel] = int(unread[channel]) + 1
	_update_tab_titles()

func _mark_read() -> void:
	if filter == "all":
		for channel: String in unread:
			unread[channel] = 0
	elif unread.has(filter):
		unread[filter] = 0
	_update_tab_titles()

func _update_tab_titles() -> void:
	for index in range(4):
		var channel: String = CHANNELS[index]
		var count := 0
		if channel == "all":
			for value: int in unread.values():
				count += value
		else:
			count = int(unread[channel])
		tabs.set_tab_title(index, channel.capitalize() + (" (" + str(count) + ")" if count > 0 else ""))

func refresh() -> void:
	if social == null or transcript == null:
		return
	var network: Node = social.get_node_or_null("/root/Network")
	var online_name: bool = network != null and network.authenticated
	display_name.editable = not online_name
	display_name.tooltip_text = "Uses your logged-in player's name." if online_name else "Player name for offline testing."
	if online_name or not display_name.has_focus():
		display_name.text = social.profile_name
	status_label.text = social.status
	status_label.tooltip_text = social.status
	retry_button.visible = not failed_draft.is_empty()
	var stamp := str(social.history.size()) + ":" + str(social.history.back().get("id", "")) if not social.history.is_empty() else "empty"
	stamp += filter + str(social.blocks)
	if stamp != last_render:
		var follow := transcript.scroll_following
		var old_scroll := transcript.get_v_scroll_bar().value
		transcript.clear()
		for event: Dictionary in social.history:
			var channel := str(event.get("channel", "local"))
			if social.is_blocked(str(event.get("sender_id", ""))) or (channel != "system" and filter != "all" and filter != channel):
				continue
			var color := Color("eee7d6")
			if channel == "global":
				color = Color("eac778")
			elif channel == "private":
				color = Color("a9cdfa")
			var speaker := str(event.get("sender", "Player"))
			if channel == "private":
				speaker = ("To " + str(event.get("target", ""))) if str(event.get("sender_id", "")) == social.identity else "From " + speaker
			transcript.push_color(color)
			transcript.add_text("[" + channel.capitalize() + "] " + speaker + ": " + str(event.get("text", "")) + "\n")
			transcript.pop()
		transcript.scroll_following = follow
		if not follow:
			transcript.get_v_scroll_bar().set_deferred("value", old_scroll)
		last_render = stamp
	_rebuild_list(friend_list, social.friends, true)
	_rebuild_list(block_list, social.blocks, false)
	_update_tab_titles()

func _rebuild_list(list: ItemList, entries: Array, show_online: bool) -> void:
	var selected_id := ""
	if not list.get_selected_items().is_empty():
		selected_id = str(list.get_item_metadata(list.get_selected_items()[0]).get("id", ""))
	list.clear()
	for entry: Dictionary in entries:
		var label := str(entry.name)
		if show_online:
			label += "  ·  " + ("Online" if bool(entry.get("online", false)) else "Offline")
		var index := list.add_item(label)
		list.set_item_metadata(index, entry)
		if str(entry.id) == selected_id:
			list.select(index)
