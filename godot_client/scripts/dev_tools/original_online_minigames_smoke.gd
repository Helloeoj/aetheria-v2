extends Node
class Transport extends Node:
	var commands: Array[Dictionary] = []
	var latest_snapshot: Dictionary = {}
	func send_action(command: Dictionary) -> bool:
		commands.append(command.duplicate(true))
		return true
var failures := 0
var checks := 0
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Original online minigames FAIL] ", text)
func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(40).timeout.connect(func() -> void: get_tree().quit(1))
func _run() -> void:
	var map := (load("res://scenes/EastOutskirtsLayered.tscn") as PackedScene).instantiate()
	add_child(map)
	await get_tree().process_frame
	var game: Node = map.get_node("Combat")
	Network.mode = Network.Mode.CLIENT
	Network.authenticated = true
	Network.set_process(false)
	game.online_view = load("res://network/online_world_view.gd").new()
	game.add_child(game.online_view)
	game.online_view.configure(game)
	var spots: Array[FishingSpot] = game.fishing_spots()
	check(game.online_view.activity_panel == game.fishing_panel, "Online fishing uses the original lake-art FishingPanel")
	if game.online_view.activity_panel != game.fishing_panel:
		_finish()
		return
	var fish_panel: FishingPanel = game.fishing_panel
	var sprite: Node2D = game.actor_sprites[game.player.entity_id]
	sprite.global_position = spots[0].shore_position()
	game.request_fishing(spots[0])
	check(fish_panel.visible and fish_panel._lake_texture != null, "Original lake artwork and fishing interface are present online")
	check(fish_panel.session.has_method("sync_remote"), "Original UI uses a server-state presentation adapter")
	if not fish_panel.session.has_method("sync_remote"):
		_finish()
		return
	var transport := Transport.new()
	add_child(transport)
	fish_panel.session.transport = transport
	var before: Dictionary = game.player.backpack.duplicate(true)
	fish_panel._act()
	check(transport.commands[-1].type == "fish_start", "Original cast control sends a server intent")
	check(game.player.backpack == before, "Client cast never consumes bait")
	transport.latest_snapshot = {"activity":{"kind":"fish", "start_token":fish_panel.session._start_token,"encounter_id":1,"sample_id":1,"action_ack":1,"station_id":fish_panel.session.station_id,"state":1,"elapsed":0.6,"power":0.7,"rod":"Beginner Rod","bait":"Low Grade Fish Food","message":"Set cast"}}
	fish_panel.session.advance(0.01)
	check(fish_panel.session.state == FishingSession.State.POWER, "Original power meter follows server state")
	fish_panel._act()
	check(transport.commands[-1].get("action") == "act" and transport.commands[-1].has("phase_elapsed") and not transport.commands[-1].has("power"), "Original power control sends bounded phase intent without client outcome")
	transport.latest_snapshot.activity.sample_id = 2
	transport.latest_snapshot.activity.action_ack = 2
	transport.latest_snapshot.activity.state = 5
	transport.latest_snapshot.activity.remaining = 30.0
	transport.latest_snapshot.activity.distance = 40.0
	transport.latest_snapshot.activity.lateral = 0.15
	transport.latest_snapshot.activity.fish_id = GameData.get_item_by_name("Raw Reedkip").id
	fish_panel.session.advance(0.1, -1.0)
	check(transport.commands[-1].type == "fish_input" and transport.commands[-1].steering == -1.0, "Original mouse/keyboard steering goes to the server")
	fish_panel.session.advance(90.0, 1.0)
	check(fish_panel.session.state == FishingSession.State.FIGHT and game.player.backpack == before, "Client time cannot finish a catch or grant a reward")
	game.player.store_fishing_catch("Raw Reedkip")
	var slot: int = game.player.fishing_pale.find("Raw Reedkip")
	fish_panel.move_pale_catch(slot,"Raw Reedkip")
	check(transport.commands[-1] == {"type":"pale_move","slot":slot} and game.player.fishing_pale[slot] == "Raw Reedkip", "Original pale menu requests transfer without changing inventory locally")
	fish_panel.close()
	check(transport.commands[-1].type == "fish_stop", "Leaving the original fishing UI closes the server session")
	var stove := CookingStation.new()
	stove.name = "FixtureStove"
	game.add_child(stove)
	game.cooking_controller.panel.open(stove)
	var cooking: CookingPanel = game.cooking_controller.panel
	check(cooking.session.has_method("sync_remote") and cooking.pan != null, "Online cooking retains the original pan/flip interface")
	if cooking.session.has_method("sync_remote"):
		cooking.session.transport = transport
		transport.latest_snapshot = {}
		game.player.add_item("Raw Reedkip",2)
		before = game.player.backpack.duplicate(true)
		cooking.session.start("Raw Reedkip",2)
		check(transport.commands[-1].type == "cook_start" and game.player.backpack == before, "Original cook controls request authoritative cooking")
		cooking.refresh()
		check(cooking.cook_one.disabled and cooking.timer_label.text.contains("Starting"), "Original cooking controls display pending start immediately")
		transport.latest_snapshot = {"activity":{"start_token":cooking.session._start_token,"encounter_id":1,"phase_id":2,"prompt_id":1,"sample_id":1,"sample_time":0.1,"action_ack":1,"kind":"cook","station_id":cooking.session.station_id,"state":2,"raw_item":"Raw Reedkip","remaining":2,"flip_window":0.8,"flip_elapsed":0.1,"message":"Flip"}}
		cooking.session.advance(0.1)
		cooking.session.flip()
		cooking.refresh()
		check(transport.commands[-1].type == "cook_flip" and transport.commands[-1].prompt_id == 1 and not transport.commands[-1].has("elapsed") and not transport.commands[-1].has("success"), "Original flip input identifies its server prompt without client success or timing")
		check(cooking.flip_action.disabled and cooking.timer_label.text.contains("Flip sent") and not cooking.timer_label.text.contains("Perfect"), "Original cooking button acknowledges pending flip without claiming success")
		cooking.session.advance(90.0)
		check(game.player.backpack == before and cooking.session.state == CookingSession.State.FLIP_PENDING, "Client cooking time cannot resolve rewards or burns")
		cooking.close()
		check(transport.commands[-1].type == "cook_cancel", "Original cooking close sends authoritative cancellation")
	_finish()
func _finish() -> void:
	Network.authenticated = false
	Network.mode = Network.Mode.OFFLINE
	print("[Original online minigames] %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
