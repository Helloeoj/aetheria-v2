extends SceneTree
## Exercise real login-name selection and migration without touching user files.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("[Social name FAIL] ", label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var social: Node = root.get_node("Social")
	var network: Node = root.get_node("Network")
	social.automatic = false
	social.preferences = ConfigFile.new()
	social.endpoint = "ws://127.0.0.1:45287"
	var legacy_section: String = social.endpoint.sha256_text()
	var existing_credential := "e".repeat(64)
	social.preferences.set_value(legacy_section, "credential", existing_credential)
	social.preferences.set_value(legacy_section, "name", "Player_55eb2b")
	network.authenticated = true
	network.username = "Aria"
	network.character_id = "character-aria"
	social._load_profile()
	check(social.profile_name == "Aria", "Chat takes the authenticated player's name instead of its saved random nickname")
	check(social.token == existing_credential, "First login migrates the old credential so friends and blocks are retained")
	network.username = "Borin"
	network.character_id = "character-borin"
	social._load_profile()
	var borin_credential: String = social.token
	check(borin_credential != existing_credential, "A different player does not inherit the previous player's chat identity")
	network.username = "Aria"
	network.character_id = "character-aria"
	social._load_profile()
	check(social.token == existing_credential and social.profile_name == "Aria", "Returning to the first player restores their original profile")
	network.joined.emit()
	check(social.profile_name == "Aria", "World admission synchronizes the chat name")
	check(social.panel.display_name.text == "Aria" and not social.panel.display_name.editable, "Connection settings display the actual player name without a separate online alias")
	social.connect_chat(social.endpoint, "WrongAlias")
	check(social.profile_name == "Aria", "A stale settings alias cannot override the logged-in name")
	social.history.append({"id": "old-private", "channel": "private", "text": "Previous player's conversation"})
	network.authenticated = false
	network.status_changed.emit()
	check(not social.connected and social.socket == null and social.history.is_empty(), "Logout disconnects chat and removes the previous player's private history")
	social._load_profile()
	check(not social.profile_name.begins_with("Player_"), "Unauthenticated fallback never displays a generated credential fragment")
	check(social.token != existing_credential, "Offline testing after logout cannot reuse the migrated player's credential")
	print("[Social name] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
