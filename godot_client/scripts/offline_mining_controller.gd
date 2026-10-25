extends Node
## Offline uses the same extraction rules/catalog holds as the authoritative region.
var game: Node2D
var service := MiningService.new()
var nodes := {}

func configure(owner_game: Node2D) -> void:
	game = owner_game
	var definitions := MiningDefinitions.new()
	definitions.load_data()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	service.configure(definitions, _context, _reward, rng)
	var candidates := {}
	var duplicates := {}
	for node: Node in get_tree().get_nodes_in_group("mining_deposit"):
		if not game.get_parent().is_ancestor_of(node) or not node.enabled:
			continue
		if candidates.has(node.deposit_id):
			duplicates[node.deposit_id] = true
		candidates[node.deposit_id] = node
	for id: String in candidates:
		if not duplicates.has(id) and service.register_deposit(id, candidates[id].ore_item_id).ok:
			nodes[id] = candidates[id]
	_publish()

func start(node: Node2D) -> Dictionary:
	if nodes.get(node.deposit_id) != node:
		return {"ok": false, "message": "That deposit is unavailable."}
	var result := service.start(game.player.entity_id, node.deposit_id, int(node.state.get("generation", 0)))
	game.show_fishing_notice("Mining…" if result.ok else String(result.get("message", "Mining unavailable.")))
	return result

func stop(reason: String) -> void:
	service.stop(game.player.entity_id, reason)

func advance(delta: float) -> void:
	service.advance(delta)
	_publish()

func _publish() -> void:
	for state: Dictionary in service.deposit_snapshots():
		var node: Variant = nodes.get(state.deposit_id)
		if is_instance_valid(node):
			node.apply_state(state)

func _context(id: String, deposit_id: String) -> Dictionary:
	var node: Variant = nodes.get(deposit_id)
	if not is_instance_valid(node) or not node.is_inside_tree():
		return {}
	var actor: CombatActor = game.combat.actors.get(id)
	var approach: Dictionary = preload("res://scripts/interaction_approach.gd").describe(game, node, "mine")
	return {"player": game.player, "paused": false,
		"eligible": actor != null and actor.is_alive and actor.hp > 0 and not game.player.in_combat
			and not game.combat.active_spell_casts.has(id) and game.world.at_grid_rest(id)
			and not game.fishing_panel.visible and not game.cooking_controller.panel.visible,
		"in_range": preload("res://scripts/interaction_approach.gd").in_range(game.world, actor, approach)}

func _reward(_id: String, _event: Dictionary) -> void:
	game.inventory_menu.refresh_view()
	game.show_fishing_notice("Mined ore.")
