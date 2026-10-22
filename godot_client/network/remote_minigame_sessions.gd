extends RefCounted
## Read-only session views for the ORIGINAL minigame interfaces. No client rewards.

class Fish extends FishingSession:
	var transport: Node
	var station_id := ""
	var _last: Dictionary = {}
	var _steering_elapsed := 0.0
	var _last_status := ""
	func _init(owner: PlayerState, network: Node, station: String) -> void:
		super(owner)
		transport = network
		station_id = station
		_last_status = String(network.get("status")) if network.get("status") is String else ""
	func act() -> void:
		if state in [State.READY, State.CAUGHT, State.LOST]:
			reward_xp = 0
			transport.send_action({"type":"fish_start","station_id":station_id,"rod":rod,"bait":bait})
		else:
			transport.send_action({"type":"fish_input","action":"act"})
	func sync_remote() -> void:
		var status: Variant = transport.get("status")
		if status is String and status != _last_status:
			_last_status = status
			message = status
		var data: Dictionary = transport.latest_snapshot.get("activity", {})
		if data.get("kind") != "fish" or data.get("station_id") != station_id:
			return
		if data == _last:
			return
		_last = data.duplicate(true)
		state = int(data.state)
		message = String(data.get("message", ""))
		rod = String(data.get("rod", rod))
		bait = String(data.get("bait", bait))
		for field: String in ["elapsed","power","cast_power","distance","remaining","lateral","velocity","strain","fight_time","fish_pull"]:
			set(field, float(data.get(field, get(field))))
		reward_xp = int(data.get("reward_xp", 0))
		fish = GameData.get_item(int(data.get("fish_id", 0)))
	func advance(delta: float, input: float = 0.0) -> void:
		sync_remote()
		# Interpolate only the displayed power meter; the server chooses cast power.
		if state == State.POWER:
			elapsed += minf(maxf(delta, 0.0), 0.1)
			power = power_at_time(elapsed)
		_steering_elapsed += maxf(delta, 0.0)
		if state == State.FIGHT and _steering_elapsed >= 0.05:
			_steering_elapsed = 0.0
			transport.send_action({"type":"fish_input","steering":clampf(input,-1.0,1.0)})
	func close() -> void:
		transport.send_action({"type":"fish_stop"})
		state = State.CLOSED

class Cook extends CookingSession:
	var transport: Node
	var station_id := ""
	var _last_status := ""
	var _last: Dictionary = {}
	func _init(owner: PlayerState, heat: CookingCampfire, combat: CombatEngine, network: Node, station: String) -> void:
		super(owner, heat, combat)
		transport = network
		station_id = station
		_last_status = String(network.get("status")) if network.get("status") is String else ""
	func start(item_name: String, quantity: int = 1) -> String:
		transport.send_action({"type":"cook_start","station_id":station_id,"item_name":item_name,"quantity":quantity})
		return ""
	func sync_remote() -> void:
		var status: Variant = transport.get("status")
		if status is String and status != _last_status:
			_last_status = status
			message = status
		var data: Dictionary = transport.latest_snapshot.get("activity", {})
		if data.get("kind") != "cook" or data.get("station_id") != station_id:
			return
		if data == _last:
			return
		_last = data.duplicate(true)
		state = int(data.state)
		message = String(data.get("message", ""))
		raw_item = String(data.get("raw_item", ""))
		remaining = int(data.get("remaining", 0))
		for field: String in ["elapsed","flip_elapsed","feedback_elapsed"]:
			set(field, float(data.get(field, 0.0)))
		flip_window = INF if float(data.get("flip_window", 0.8)) < 0.0 else float(data.get("flip_window", 0.8))
		last_result = data.get("last_result", {}).duplicate(true)
		cooked_count = int(data.get("cooked_count", 0))
		burnt_count = int(data.get("burnt_count", 0))
		reward_xp = int(data.get("reward_xp", 0))
	func advance(delta: float) -> Array[Dictionary]:
		sync_remote()
		# Smooth the existing animation/timer between snapshots, without changing
		# phase, resolving a flip, consuming food or granting a reward.
		var step := minf(maxf(delta, 0.0), 0.1)
		if state == State.COOKING:
			elapsed += step
		elif state == State.FLIP_PENDING:
			flip_elapsed += step
		elif state == State.FEEDBACK:
			feedback_elapsed += step
		return []
	func flip() -> Array[Dictionary]:
		transport.send_action({"type":"cook_flip"})
		return []
	func close(_reason: String = "") -> void:
		transport.send_action({"type":"cook_cancel"})
		state = State.CANCELLED

static func raise_modal(panel: Control, game: Node) -> void:
	var canvas := game.get_node_or_null("UI") as CanvasLayer
	var social := game.get_node_or_null("/root/Social/SocialOverlay") as CanvasLayer
	if canvas != null and social != null and not panel.has_meta("original_ui_layer"):
		panel.set_meta("original_ui_layer", canvas.layer)
		canvas.layer = maxi(canvas.layer, social.layer + 1)
	for name: String in ["OnlineLogoutButton", "OnlineStatusLabel"]:
		var hud := game.ui_root.get_node_or_null(name) as Control
		if hud != null:
			hud.hide()

static func restore_modal(panel: Control, game: Node) -> void:
	var canvas := game.get_node_or_null("UI") as CanvasLayer
	if canvas != null and panel.has_meta("original_ui_layer"):
		canvas.layer = int(panel.get_meta("original_ui_layer"))
		panel.remove_meta("original_ui_layer")
	for name: String in ["OnlineLogoutButton", "OnlineStatusLabel"]:
		var hud := game.ui_root.get_node_or_null(name) as Control
		if hud != null:
			hud.show()
