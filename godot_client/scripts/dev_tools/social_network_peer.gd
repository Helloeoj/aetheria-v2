extends SceneTree
## External runner supplies disposable configuration; no test secrets enter logs.
var social: Node
var config: Dictionary
var sequence := -1
var elapsed := 0.0
var report_time := 0.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	config = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("AETHERIA_SOCIAL_TEST_CONFIG")))
	social = root.get_node("Social")
	social.automatic = false
	social.endpoint = str(config.url)
	# Begin with the old generated nickname and a real Network admission event;
	# the production client must choose the player's name for the actual handshake.
	social.preferences = ConfigFile.new()
	social.preferences.set_value(social.endpoint.sha256_text(), "credential", str(config.token))
	social.preferences.set_value(social.endpoint.sha256_text(), "name", "Player_55eb2b")
	var network: Node = root.get_node("Network")
	network.username = str(config.name)
	network.character_id = "social-fixture-" + str(config.name).to_lower()
	network.authenticated = true
	network.joined.emit()
	var scene: Node = load("res://scenes/EastOutskirtsLayered.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var game: Node = scene.get_node("Combat")
	game.player.x = float(config.x)
	game.player.y = float(config.y)
	game.world.player.x = float(config.x)
	game.world.player.y = float(config.y)
	var actor: CombatActor = game.combat.actors[game.player.entity_id]
	actor.x = float(config.x)
	actor.y = float(config.y)
	social.connect_chat(social.endpoint, "StaleAlias")

func _process(delta: float) -> bool:
	if social == null:
		return false
	elapsed += delta
	report_time -= delta
	if elapsed > 90:
		printerr("[Social peer] Timed out")
		quit(1)
		return false
	if report_time <= 0.0:
		report_time = 0.1
		if FileAccess.file_exists(str(config.command)):
			var command: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(config.command)))
			if command is Dictionary and int(command.get("sequence", -1)) > sequence:
				sequence = int(command.sequence)
				if str(command.get("op", "")) == "quit":
					quit(0)
				else:
					social.request(str(command.op), command.get("data", {}))
		var report := {"connected": social.connected, "status": social.status, "name": social.profile_name, "transcript": social.panel.transcript.get_parsed_text(), "history": social.history, "friends": social.friends, "blocks": social.blocks, "sequence": sequence}
		var file := FileAccess.open(str(config.report) + ".tmp", FileAccess.WRITE)
		file.store_string(JSON.stringify(report))
		file.close()
		DirAccess.rename_absolute(str(config.report) + ".tmp", str(config.report))
	return false
