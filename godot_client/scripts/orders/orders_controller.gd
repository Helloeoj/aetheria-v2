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
var activation_errors: Dictionary = {}
var _pending_activations: Dictionary = {}

func _ready() -> void:
	Network.action_result.connect(_action_result)

func configure(owner_game: Node) -> void:
	game = owner_game
	region_id = Protocol.region_for_scene(game.get_parent().scene_file_path)
	var loaded: Dictionary = Definitions.new().load_data()
	if loaded.ok:
		service.configure(loaded.config)

func view() -> Dictionary:
	var result: Dictionary = game.player.orders_view.duplicate(true) if Network.online() else Book.public_book(game.player.dead_man_orders)
	result["enabled"] = service.enabled()
	result["activation_errors"] = activation_errors.duplicate(true)
	if not service.enabled():
		result["message"] = "Dead Man's Orders are not available yet. Sealed orders remain safe in your backpack."
	return result

func open_sealed(item_name: String) -> void:
	var item := GameData.get_item_by_name(item_name)
	var tier := String(item.get("order_tier",""))
	if tier not in Book.TIERS or item.get("order_opened",false) == true:
		_notice("Choose an owned sealed order.")
		return
	var generation := int(view().get("generations",{}).get(tier,0))
	activation_errors.erase(tier)
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
			if command.type == "order_open":
				_pending_activations[Network.sequence] = command.duplicate(true)
			_notice("Waiting for the server.")
		else:
			_activation_failed(command,"The server connection is unavailable. Your sealed Order is unchanged.")
		return
	if game.player.current_hp <= 0 or game.player.in_combat:
		_activation_failed(command,"Finish combat before managing an order.")
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
	if result.get("ok",false) == false:
		_activation_failed(command,String(result.get("message","")))
	else:
		_notice(String(result.get("message","")))
	game.inventory_menu.refresh_view()

func _activation_failed(command: Dictionary, message: String) -> void:
	if command.get("type") == "order_open":
		activation_errors[String(command.tier)] = {"generation":int(command.generation)+1,"message":message}
	_notice(message)

func _action_result(sequence: int, result: Dictionary) -> void:
	if not _pending_activations.has(sequence):
		return
	var command: Dictionary = _pending_activations[sequence]
	_pending_activations.erase(sequence)
	if result.get("ok",false) == false:
		_activation_failed(command,String(result.get("message","This Order could not be opened.")))
		if is_instance_valid(game) and game.get("inventory_menu") != null:
			game.inventory_menu.refresh_view()

func _notice(message: String) -> void:
	if game.get("inventory_menu") != null:
		game.inventory_menu._set_status(message)
