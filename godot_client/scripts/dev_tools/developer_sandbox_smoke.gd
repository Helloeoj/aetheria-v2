extends SceneTree
## Explicit sandbox entry must never rebind an authenticated online character.
var failures: Array[String] = []
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("[Developer sandbox FAIL] ", label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var network: Node = root.get_node("Network")
	check(network.has_method("open_developer_sandbox"), "Networking exposes explicit developer sandbox entry")
	if not network.has_method("open_developer_sandbox"):
		quit(1)
		return
	network.mode = network.Mode.CLIENT
	network.authenticated = true
	network.character_id = "online-character"
	network.saved_state = {"online": true}
	check(not network.open_developer_sandbox(), "An authenticated character must save and log out before sandbox entry")
	check(network.online() and network.authenticated and network.character_id == "online-character" and network.saved_state.has("online"), "Rejected sandbox entry preserves the active online session")
	network.authenticated = false
	network.username = "Online account"
	network.latest_snapshot = {"actors": [{"entity_id": "online-character"}]}
	network.revision = 5
	network._ticket = "pending-ticket"
	network._scene_loading = true
	root.get_node("Social").panel.hide()
	check(network.open_developer_sandbox(), "Logged-out player can enter the developer sandbox")
	check(not network.online() and not network.authenticated, "Sandbox explicitly uses local authority")
	check(network.saved_state.is_empty() and network.latest_snapshot.is_empty() and network.character_id.is_empty() and network.username.is_empty(), "Sandbox clears online identity and character projection")
	check(network._ticket.is_empty() and not network._scene_loading and network.game == null, "Sandbox clears admission and scene-loading state")
	await scene_changed
	for _index in range(8):
		await process_frame
	check(current_scene.scene_file_path == "res://scenes/EastOutskirtsLayered.tscn", "Sandbox enters the actual development map")
	var game: Node = current_scene.get_node("Combat")
	check(game.online_view == null and network.game == null, "Development map has no online authority binding")
	check(game.player.entity_id != "online-character", "Development map creates a separate local character")
	check(game.fishing_test_button.visible and game.skill_test_button.visible, "Fishing and skill development controls are visible")
	check(root.get_node("Social").panel.visible, "Persistent chat remains available in the sandbox")
	print("[Developer sandbox] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
