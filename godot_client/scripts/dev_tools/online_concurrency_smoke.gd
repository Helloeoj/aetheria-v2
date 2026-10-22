extends Node
## Driven only by tools/test_online_concurrency.py; credentials live outside Git.
var config: Dictionary
var net: Node
var checks := 0
var failures := 0
var ever_joined := false
var saw_other := false
var finished := false
var snapshots := 0
var started := 0
var first_revision := -1
var logout_requested := false
var ready_written := false
var last_action := ""

func bait_count() -> int:
	var item_id := int(GameData.get_item_by_name("Low Grade Fish Food").get("id", -1))
	for item: Dictionary in net.saved_state.get("inventory", []):
		if int(item.get("item_id", -2)) == item_id:
			return int(item.get("count", 0))
	return 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("[Online concurrency client FAIL] ", label)

func write_json(name: String, data: Dictionary) -> void:
	var file := FileAccess.open(String(config.directory).path_join(name), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))

func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--test-input="):
			config = JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("--test-input=")))
	if config.is_empty():
		get_tree().quit(1)
		return
	started = Time.get_ticks_msec()
	net = get_node("/root/Network")
	net.auto_scene = false
	net.username = config.username
	net.account_token = config.token
	net.joined.connect(func() -> void:
		ever_joined = true
		first_revision = net.revision
		check(net.character_id == config.character_id, "Stable backend character identity")
		check(net.revision > int(config.get("minimum_revision", -1)), "Admission confirms a durable revision")
		if config.has("expected_bait"):
			check(bait_count() == int(config.expected_bait), "Saved inventory mutation survives reconnection")
	)
	net.snapshot_received.connect(_snapshot)
	check(net.join_world(config.ticket) == OK, "ENet transport starts")
	get_tree().create_timer(75).timeout.connect(func() -> void:
		check(false, "Client timed out")
		finish())

func _snapshot(snapshot: Dictionary) -> void:
	snapshots += 1
	var ids: Array[String] = []
	for actor: Dictionary in snapshot.get("actors", []):
		if not actor.get("is_monster", true):
			ids.append(String(actor.entity_id))
	if ids.has(String(config.get("other_id", ""))):
		saw_other = true
	write_json("observation.json", {"authenticated": net.authenticated, "ids": ids,
		"revision": net.revision, "snapshots": snapshots, "region_id": net.region_id,
		"bait_count": bait_count(), "drops": snapshot.get("drops", [])})
	if saw_other and ids.has(config.character_id) and not ready_written:
		check(ids.count(config.character_id) == 1, "Own stable character appears once in shared snapshots")
		write_json("ready.json", {"character_id": net.character_id, "revision": net.revision,
			"region_id": net.region_id, "shared": true})
		ready_written = true

func _process(_delta: float) -> void:
	if config.is_empty() or finished:
		return
	var directory: String = config.directory
	var action_path := directory.path_join("action.json")
	if FileAccess.file_exists(action_path):
		var action: Variant = JSON.parse_string(FileAccess.get_file_as_string(action_path))
		if action is Dictionary and String(action.get("id", "")) != last_action and net.authenticated:
			last_action = String(action.get("id", ""))
			check(net.send_action(action.command), "A real client submits the requested inventory action")
	if config.get("expect_rejection", false):
		if not ever_joined and not net.authenticated and String(net.status).contains("already"):
			check(true, "A duplicate login cannot steal the active gameplay lease")
			finish()
		return
	if FileAccess.file_exists(directory.path_join("expire.request")) and ever_joined and not net.authenticated:
		check(true, "Expired ownership retires the old live client")
		check(saw_other, "Retired client previously shared the region")
		finish()
	elif FileAccess.file_exists(directory.path_join("stop.request")):
		if net.authenticated and not logout_requested:
			logout_requested = true
			net.request_logout()
		elif not net.authenticated:
			check(saw_other, "Two distinct clients observed each other in a shared region")
			finish()

func finish() -> void:
	if finished:
		return
	finished = true
	# Network revokes its account session asynchronously after a logout control.
	# Let real HTTP requests finish before freeing the scene and its coroutines.
	var deadline := Time.get_ticks_msec() + 10000
	while net.get_children().any(func(child: Node) -> bool: return child is AccountHTTP):
		if Time.get_ticks_msec() > deadline:
			check(false, "Account logout request completed before process shutdown")
			break
		await get_tree().process_frame
	await get_tree().process_frame
	write_json("result.json", {"checks": checks, "failures": failures,
		"character_id": config.character_id, "joined": ever_joined,
		"revision": net.revision, "first_revision": first_revision, "shared": saw_other,
		"bait_count": bait_count()})
	print("[Online concurrency client] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
