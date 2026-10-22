extends Control
const HTTP = preload("res://network/account_http.gd")
var api: Node
var username: LineEdit
var password: LineEdit
var confirmation: LineEdit
var message: Label
var submit_button: Button
var register_mode := false
var busy := false

func _ready() -> void:
	api = HTTP.new()
	add_child(api)
	api.endpoint = Network.account_url
	theme = FantasyUI.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("101a27")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(490, 530)
	frame.add_theme_stylebox_override("panel", FantasyUI.box(Color("192737"), FantasyUI.GOLD))
	center.add_child(frame)
	var margins := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 28)
	frame.add_child(margins)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 15)
	margins.add_child(column)
	var title := Label.new()
	title.text = "AETHERIA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", FantasyUI.GOLD)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Your character. Your progress. Every session."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)
	username = _entry(column, "Username", false)
	password = _entry(column, "Password — at least 15 characters", true)
	confirmation = _entry(column, "Confirm password", true)
	confirmation.hide()
	var preferences := ConfigFile.new()
	preferences.load("user://online_ui.cfg")
	username.text = String(preferences.get_value("login", "username", ""))
	submit_button = Button.new()
	submit_button.text = "Log in and play"
	submit_button.custom_minimum_size.y = 46
	submit_button.pressed.connect(_submit)
	column.add_child(submit_button)
	var toggle := Button.new()
	toggle.text = "Create a new account"
	toggle.pressed.connect(func() -> void:
		if busy:
			return
		register_mode = not register_mode
		confirmation.visible = register_mode
		submit_button.text = "Create account and play" if register_mode else "Log in and play"
		toggle.text = "I already have an account" if register_mode else "Create a new account"
		message.text = "Email is optional. Use 3–20 letters, numbers or underscores for your username." if register_mode else "Enter your username and password.")
	column.add_child(toggle)
	var sandbox := Button.new()
	sandbox.name = "DeveloperSandboxButton"
	sandbox.text = "Developer sandbox — unsaved testing"
	sandbox.custom_minimum_size.y = 40
	sandbox.tooltip_text = "Use F5/F6/F7, K and P to test without changing an online character."
	sandbox.pressed.connect(func() -> void: Network.open_developer_sandbox())
	column.add_child(sandbox)
	message = Label.new()
	message.text = Network.status if Network.status != "Not connected" else "Enter your username and password."
	message.custom_minimum_size = Vector2(425, 75)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(message)
	var recovery := Label.new()
	recovery.text = "Email linking and password recovery are planned."
	recovery.add_theme_font_size_override("font_size", 13)
	recovery.modulate = Color("abb7c5")
	column.add_child(recovery)
	password.text_submitted.connect(func(_value: String) -> void: _submit())
	confirmation.text_submitted.connect(func(_value: String) -> void: _submit())
	Network.status_changed.connect(_network_status)
	var social := get_node_or_null("/root/Social")
	if social != null and social.panel != null:
		social.panel.hide()
	if DisplayServer.get_name() != "headless":
		_start_local()
	username.grab_focus()

func _entry(parent: Node, hint: String, secret: bool) -> LineEdit:
	var input := LineEdit.new()
	input.placeholder_text = hint
	input.secret = secret
	input.max_length = 128 if secret else 20
	input.custom_minimum_size.y = 43
	parent.add_child(input)
	return input

func _start_local() -> void:
	var script := ProjectSettings.globalize_path("res://../tools/online.ps1")
	if OS.get_name() == "Windows" and FileAccess.file_exists(script):
		OS.create_process("powershell.exe", PackedStringArray(["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", script, "start"]), false)
		message.text = "Starting your local world. Log in when it is ready."

func _submit() -> void:
	if busy:
		return
	busy = true
	submit_button.disabled = true
	var name_value := username.text.strip_edges()
	var password_value := password.text
	var confirmation_value := confirmation.text
	password.clear()
	confirmation.clear()
	message.text = "Creating account…" if register_mode else "Signing in…"
	if register_mode:
		var registration: Dictionary = await api.request_json("/api/register", {"username": name_value, "password": password_value, "password_confirmation": confirmation_value})
		if not registration.get("ok", false):
			_finish_error(String(registration.get("message", "Account creation failed.")))
			return
	var login: Dictionary = await api.request_json("/api/login", {"username": name_value, "password": password_value})
	password_value = ""
	confirmation_value = ""
	if not login.get("ok", false):
		_finish_error(String(login.get("message", "Login failed.")))
		return
	Network.account_token = String(login.token)
	Network.username = String(login.username)
	var admission: Dictionary = await api.request_json("/api/admit", {"world_id": Network.world_id}, Network.account_token)
	if not admission.get("ok", false):
		_finish_error(String(admission.get("message", "World admission failed.")))
		return
	var preferences := ConfigFile.new()
	preferences.set_value("login", "username", name_value)
	preferences.save("user://online_ui.cfg")
	if Network.join_world(String(admission.ticket)) != OK:
		_finish_error(Network.status)

func _finish_error(text: String) -> void:
	busy = false
	submit_button.disabled = false
	message.text = text

func _network_status() -> void:
	message.text = Network.status
	if not Network.authenticated:
		busy = false
		submit_button.disabled = false
