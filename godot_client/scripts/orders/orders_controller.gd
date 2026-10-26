extends Node
## Native journal adapter. Authenticated clients send intents only.
const Book := preload("res://scripts/orders/order_book.gd")
const Service := preload("res://scripts/orders/orders_service.gd")
const Definitions := preload("res://scripts/orders/orders_definitions.gd")
const Targets := preload("res://scripts/orders/orders_targets.gd")
const Protocol := preload("res://network/world_protocol.gd")
var game: Node
var service := Service.new()
var region_id := ""

func configure(owner_game: Node) -> void:
	game = owner_game
	region_id = Protocol.region_for_scene(game.get_parent().scene_file_path)
	var loaded: Dictionary = Definitions.new().load_data()
	if loaded.ok:
		service.configure(loaded.config)

func view() -> Dictionary:
	var result: Dictionary = game.player.orders_view.duplicate(true) if Network.online() else Book.public_book(game.player.dead_man_orders)
	result["enabled"] = service.enabled()
	if not service.enabled():
		result["message"] = "Dead Man's Orders are not available yet. Sealed orders remain safe in your backpack."
	return result

func open_sealed(item_name: String) -> void:
	var item := GameData.get_item_by_name(item_name)
	var tier := String(item.get("order_tier",""))
	if tier not in Book.TIERS:
		_notice("Choose an owned sealed order.")
		return
	var generation := int(view().get("generations",{}).get(tier,0))
	_dispatch({"type":"order_open","tier":tier,"generation":generation})

func search(order_id: String, directive_id: String, answer: String = "") -> void:
	var anchor_id := Targets.nearest(game,service.config,region_id,game.player,game.world)
	_dispatch({"type":"order_interact","order_id":order_id,"directive_id":directive_id,"anchor_id":anchor_id,"answer":answer})

func claim(order_id: String) -> void:
	var anchor_id := Targets.nearest(game,service.config,region_id,game.player,game.world)
	_dispatch({"type":"order_claim","order_id":order_id,"anchor_id":anchor_id})

func abandon(order_id: String, confirmed: bool = false) -> void:
	if confirmed:
		_dispatch({"type":"order_abandon","order_id":order_id})

func _dispatch(command: Dictionary) -> void:
	if Network.online():
		if Network.send_action(command):
			_notice("Waiting for the server.")
		return
	if game.player.current_hp <= 0 or game.player.in_combat:
		_notice("Finish combat before managing an order.")
		return
	var result := {"ok":false,"message":"That order action is unavailable."}
	match command.type:
		"order_open":
			result = service.open(game.player,command.tier,int(command.generation))
		"order_abandon":
			result = service.abandon(game.player,command.order_id)
		"order_interact":
			var context := Targets.context(game,service.config,region_id,command.anchor_id,game.player,game.world)
			result = service.interact(game.player,command.order_id,command.directive_id,command.anchor_id,context,command.answer)
		"order_claim":
			var context := Targets.context(game,service.config,region_id,command.anchor_id,game.player,game.world)
			result = service.claim(game.player,command.order_id,command.anchor_id,context)
	_notice(String(result.get("message","")))
	game.inventory_menu.refresh_view()

func _notice(message: String) -> void:
	if game.get("inventory_menu") != null:
		game.inventory_menu._set_status(message)
