extends Node
class FakeNetwork extends Node:
	var latest_snapshot: Dictionary = {}
	var commands: Array[Dictionary] = []
	func send_action(command: Dictionary) -> void:
		commands.append(command)
class Game extends Node:
	var player := PlayerState.new("Panel test")
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
func _ready() -> void:
	check(ResourceLoader.exists("res://network/online_activity_panel.gd"),"Remote activity panel must exist")
	if not failures.is_empty():
		get_tree().quit(1)
		return
	var game := Game.new()
	add_child(game)
	game.player.add_item("Beginner Rod",1)
	game.player.add_item("Low Grade Fish Food",2)
	game.player.add_item("Raw Reedkip",3)
	var network := FakeNetwork.new()
	add_child(network)
	var panel = load("res://network/online_activity_panel.gd").new()
	add_child(panel)
	panel.configure(game)
	panel._network = network
	panel.open_station("shore", "fish", "Harbor")
	panel._on_network_status("Move closer to the fishing spot.")
	panel._refresh()
	check(panel._status.text == "Move closer to the fishing spot.", "Command rejections remain visible without an activity")
	panel._act()
	check(network.commands.size() == 1 and network.commands[0].type == "fish_start", "Start sends intent to server")
	check(game.player.backpack.get("Low Grade Fish Food") == 2, "UI never consumes inventory locally")
	network.latest_snapshot = {"activity":{"kind":"fish","state":1,"message":"Charge","power":0.8}}
	panel._refresh()
	panel._act()
	check(network.commands[-1] == {"type":"fish_input","action":"act"}, "Cast commits action without elapsed or outcome")
	panel.close()
	check(network.commands[-1].type == "fish_stop", "Close cancels authoritative fishing")
	panel.open_station("stove","cook","Tavern stove")
	panel._cook(true)
	check(network.commands[-1].type == "cook_start" and network.commands[-1].quantity == 3, "Cook all sends owned quantity")
	network.latest_snapshot = {"activity":{"kind":"cook","state":2,"message":"Flip!","flip_elapsed":0.1,"flip_window":0.8}}
	panel._refresh()
	panel._act()
	check(network.commands[-1] == {"type":"cook_flip"}, "Flip sends no timing or success data")
	check(game.player.backpack.get("Raw Reedkip") == 3, "Remote cooking leaves local inventory untouched")
	panel.close()
	check(network.commands[-1].type == "cook_cancel", "Close cancels authoritative cooking")
	print("Online activity panel smoke: %d failures" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
