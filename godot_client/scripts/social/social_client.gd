extends Node
## Persistent social state. Area scenes never own the socket or transcript.
signal updated

const PanelScript = preload("res://scripts/social/social_panel.gd")
var panel: Control
var history: Array[Dictionary] = []
var friends: Array = []
var blocks: Array = []
var identity := ""
var profile_name := ""
var endpoint := "ws://127.0.0.1:8765"
var status := "Chat offline"
var connected := false
var token := ""
var socket: WebSocketPeer
var preferences := ConfigFile.new()
var pending: Dictionary = {}
var sequence := 0
var retry_seconds := 0.0
var retry_delay := 1.0
var location_seconds := 0.0
var connection_seconds := 0.0
var was_open := false
var automatic := false
var automatic_allowed := false
var bound_character_id := ""
var fatal_error := false
var was_travelling := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	preferences.load("user://social_profiles.cfg")
	endpoint = str(preferences.get_value("settings", "endpoint", endpoint))
	_load_profile()
	var layer := CanvasLayer.new()
	layer.name = "SocialOverlay"
	layer.layer = 80
	add_child(layer)
	panel = PanelScript.new()
	panel.name = "ChatPanel"
	layer.add_child(panel)
	panel.configure(self)
	get_viewport().size_changed.connect(update_layout)
	update_layout()
	var network: Node = get_node_or_null("/root/Network")
	if network != null:
		network.joined.connect(_on_player_joined)
		network.status_changed.connect(_on_network_status_changed)
	automatic_allowed = DisplayServer.get_name() != "headless" and not OS.get_cmdline_user_args().has("--social-no-auto")
	automatic = automatic_allowed
	if automatic:
		if endpoint == "ws://127.0.0.1:8765":
			start_local_server()
		retry_seconds = 0.8

func _load_profile() -> void:
	var network: Node = get_node_or_null("/root/Network")
	bound_character_id = str(network.character_id) if network != null and network.authenticated else ""
	var legacy_section := endpoint.sha256_text()
	var section := _profile_section()
	token = str(preferences.get_value(section, "credential", ""))
	# Migrate the existing profile once, retaining its ID and social lists. Other
	# characters get separate credentials instead of inheriting another player's lists.
	if token.is_empty() and not bound_character_id.is_empty() and str(preferences.get_value(legacy_section, "migrated_to", "")).is_empty():
		token = str(preferences.get_value(legacy_section, "credential", ""))
		preferences.set_value(legacy_section, "migrated_to", bound_character_id)
		preferences.erase_section_key(legacy_section, "credential")
	if token.length() != 64:
		token = Crypto.new().generate_random_bytes(32).hex_encode()
	preferences.set_value(section, "credential", token)
	if network != null and network.authenticated:
		profile_name = str(network.username)
	else:
		profile_name = str(preferences.get_value(section, "name", "Player"))
		if RegEx.create_from_string("^Player_[0-9a-f]{6}$").search(profile_name) != null:
			profile_name = "Player"
	preferences.set_value(section, "name", profile_name)

func _profile_section() -> String:
	return endpoint.sha256_text() + (":" + bound_character_id if not bound_character_id.is_empty() else "")

func _on_player_joined() -> void:
	var network: Node = get_node_or_null("/root/Network")
	if network == null or not network.authenticated:
		return
	var reconnect := automatic_allowed or socket != null
	if socket != null:
		socket.close()
		socket = null
	connected = false
	if bound_character_id != str(network.character_id):
		_clear_account()
	_load_profile()
	status = "Chat ready as " + profile_name
	updated.emit()
	if reconnect:
		connect_chat()

func _on_network_status_changed() -> void:
	var network: Node = get_node_or_null("/root/Network")
	if not bound_character_id.is_empty() and network != null and not network.authenticated:
		disconnect_chat()
		_load_profile()
		status = "Log in to chat."
		updated.emit()

func _waiting_for_login() -> bool:
	var network: Node = get_node_or_null("/root/Network")
	if network == null or network.authenticated:
		return false
	var scene := get_tree().current_scene
	return network.online() or (scene != null and scene.scene_file_path.ends_with("/Login.tscn")) or (scene == null and str(ProjectSettings.get_setting("application/run/main_scene", "")).ends_with("/Login.tscn"))

func _save_profile() -> void:
	preferences.set_value("settings", "endpoint", endpoint)
	preferences.set_value(_profile_section(), "credential", token)
	preferences.set_value(_profile_section(), "name", profile_name)
	preferences.save("user://social_profiles.cfg")

func update_layout() -> void:
	if panel == null:
		return
	var pixels := get_viewport().get_visible_rect().size
	var factor := maxf(0.5, minf(pixels.x / 1280.0, pixels.y / 720.0))
	panel.scale = Vector2.ONE * factor
	panel.size = Vector2(minf(640.0, pixels.x / factor - 24.0), 208.0)
	panel.position = Vector2(12.0 * factor, pixels.y - (panel.size.y + 12.0) * factor)
	panel.layout_drawer()

func start_local_server() -> void:
	var script := ProjectSettings.globalize_path("res://../tools/social.ps1")
	if OS.get_name() == "Windows" and FileAccess.file_exists(script):
		OS.create_process("powershell.exe", PackedStringArray(["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", script, "start"]), false)
		status = "Starting local chat server…"
		updated.emit()

func connect_chat(url: String = "", display_name: String = "") -> void:
	if _waiting_for_login():
		automatic = false
		status = "Log in to chat."
		updated.emit()
		return
	var next_url := endpoint if url.is_empty() else url.strip_edges()
	var local_pattern := RegEx.create_from_string("^ws://(127\\.0\\.0\\.1|localhost|\\[::1\\])(:[0-9]+)?/?$")
	if next_url.length() > 256 or next_url.contains("@") or next_url.contains("?") or (not next_url.begins_with("wss://") and local_pattern.search(next_url) == null):
		status = "Use wss:// for remote chat, or ws://127.0.0.1:8765 locally."
		updated.emit()
		return
	if socket != null:
		socket.close()
	if next_url != endpoint:
		_clear_account()
		endpoint = next_url
		_load_profile()
	var network: Node = get_node_or_null("/root/Network")
	if network != null and network.authenticated:
		if bound_character_id != str(network.character_id):
			_clear_account()
			_load_profile()
		profile_name = str(network.username)
	elif not display_name.strip_edges().is_empty():
		profile_name = display_name.strip_edges()
	connected = false
	fatal_error = false
	automatic = true
	was_open = false
	connection_seconds = 0.0
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 262144
	socket.outbound_buffer_size = 16384
	socket.max_queued_packets = 128
	socket.heartbeat_interval = 15.0
	status = "Connecting…"
	if socket.connect_to_url(endpoint) != OK:
		_lost_connection()
	updated.emit()

func disconnect_chat() -> void:
	automatic = false
	if socket != null:
		socket.close()
	socket = null
	connected = false
	status = "Chat offline — use Connect to join."
	_clear_account()
	updated.emit()

func _clear_account() -> void:
	history.clear()
	friends.clear()
	blocks.clear()
	pending.clear()
	identity = ""
	if panel != null:
		panel.clear_private_context()

func request(operation: String, data: Dictionary = {}) -> String:
	if not connected or socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		status = "Chat is offline. Connect before sending."
		updated.emit()
		return ""
	sequence += 1
	var request_id := str(sequence)
	var packet := data.duplicate()
	packet.merge({"v": 1, "op": operation, "request": request_id}, true)
	if socket.send_text(JSON.stringify(packet)) != OK:
		_lost_connection()
		return ""
	return request_id

func send_chat(channel: String, text: String, target: String = "") -> bool:
	var message := text.strip_edges()
	if message.is_empty() or message.length() > 280:
		return false
	var request_id := request("send", {"channel": channel, "text": message, "target": target.strip_edges()})
	if request_id.is_empty():
		return false
	pending[request_id] = {"text": message, "at": Time.get_ticks_msec()}
	status = "Sending…"
	updated.emit()
	return true

func is_blocked(sender_id: String) -> bool:
	for entry: Dictionary in blocks:
		if str(entry.get("id", "")) == sender_id:
			return true
	return false

func _receive(event: Dictionary) -> void:
	match str(event.get("type", "")):
		"ready":
			var incoming_id := str(event.get("id", ""))
			if not identity.is_empty() and identity != incoming_id:
				_clear_account()
			identity = incoming_id
			profile_name = str(event.get("name", profile_name))
			connected = true
			retry_delay = 1.0
			location_seconds = 0.0
			status = "Connected as " + profile_name
			if automatic and DisplayServer.get_name() != "headless":
				_save_profile()
		"social":
			friends = event.get("friends", [])
			blocks = event.get("blocks", [])
			if panel != null:
				panel.check_private_target()
		"message":
			if is_blocked(str(event.get("sender_id", ""))):
				return
			for previous: Dictionary in history:
				if previous.get("id") == event.get("id"):
					return
			history.append(event.duplicate(true))
			if history.size() > 500:
				history.pop_front()
			if panel != null:
				panel.message_arrived(event)
		"result":
			var request_id := str(event.get("request", ""))
			if not bool(event.get("ok", false)):
				status = str(event.get("error", "Message failed."))
				if pending.has(request_id) and panel != null:
					panel.failed_draft = str(pending[request_id].text)
			elif pending.has(request_id):
				status = "Sent · " + profile_name
			pending.erase(request_id)
			if bool(event.get("ok", false)) and not event.has("message_id"):
				return
		"error":
			fatal_error = true
			status = str(event.get("error", "Unable to join chat."))
	updated.emit()

func _lost_connection() -> void:
	connected = false
	socket = null
	was_open = false
	if not pending.is_empty():
		status = "Connection lost; pending messages may not have arrived. Retry them manually."
		pending.clear()
	elif not fatal_error:
		status = "Chat offline · reconnecting…"
	retry_seconds = retry_delay
	retry_delay = minf(15.0, retry_delay * 2.0)
	updated.emit()

func _send_location() -> void:
	var scene := get_tree().current_scene
	var travel: Node = get_node_or_null("/root/SceneTravel")
	var travelling: bool = travel != null and travel.is_transitioning()
	var context: Variant = null
	if not travelling and scene != null:
		var game: Node = scene.get_node_or_null("Combat")
		if game != null and game.get("player") != null:
			var actor: RefCounted = game.get("player")
			context = {"world": "development", "area": scene.scene_file_path, "instance": str(scene.get_meta("social_instance", "main")), "x": actor.get("x"), "y": actor.get("y")}
	request("location", {"location": context})
	was_travelling = travelling

func _process(delta: float) -> void:
	if socket == null:
		if automatic and not fatal_error:
			retry_seconds -= delta
			if retry_seconds <= 0.0:
				connect_chat()
		return
	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not was_open:
			was_open = true
			socket.send_text(JSON.stringify({"v": 1, "op": "hello", "name": profile_name, "token": token}))
		var count := 0
		while socket != null and socket.get_available_packet_count() > 0 and count < 64:
			var decoded: Variant = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			if decoded is Dictionary:
				_receive(decoded)
			count += 1
		if connected:
			location_seconds -= delta
			var travel: Node = get_node_or_null("/root/SceneTravel")
			var travelling: bool = travel != null and travel.is_transitioning()
			if location_seconds <= 0.0 or travelling != was_travelling:
				location_seconds = 0.5
				_send_location()
	elif state == WebSocketPeer.STATE_CLOSED:
		_lost_connection()
	else:
		connection_seconds += delta
		if connection_seconds > 10.0:
			socket.close()
			_lost_connection()

func handle_game_key(event: InputEvent, game: Node) -> bool:
	if event is InputEventMouse:
		panel.prepare_pointer(event.position, game)
		return false
	if not event is InputEventKey:
		return false
	var focus := get_viewport().gui_get_focus_owner()
	if panel.owns_control(focus) and (focus is LineEdit or focus is TextEdit):
		if event.pressed and event.keycode == KEY_ESCAPE:
			focus.release_focus()
			get_viewport().set_input_as_handled()
		game._reset_held_movement()
		return true
	if event.pressed and not event.echo and event.keycode == KEY_ENTER and not (focus is LineEdit or focus is TextEdit):
		var modal := false
		for field: String in ["inventory_menu", "spawn_menu", "item_menu", "fishing_panel", "crafting_panel", "skill_debug_panel", "sprite_preview"]:
			var widget: Variant = game.get(field)
			modal = modal or (widget is Control and widget.visible)
		var cooking: Node = game.get("cooking_controller")
		modal = modal or (cooking != null and cooking.panel.visible)
		if not modal:
			panel.composer.grab_focus()
			game._reset_held_movement()
			get_viewport().set_input_as_handled()
			return true
	return false
