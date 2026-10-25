extends SceneTree
## Focused intent regression: real WorldInteraction with deterministic movement.
class TestMenu extends Control:
	var actions: Array[Dictionary] = []
	func show_options(_title: String, entries: Array[Dictionary], _at: Vector2) -> void:
		actions = entries
		show()

class TestWorld extends RefCounted:
	var grid: HiddenGrid
	func cancel_grid_route(_id: String) -> void:
		pass # Legacy intent fixture has no grid route; geometry is covered separately.
	func at_grid_rest(_id: String) -> bool:
		return true
	var monsters: Array[MonsterState] = []
	var actors: Dictionary = {}
	var blocked := false
	func move_actor_continuous(id: String, movement: Vector2) -> void:
		if not blocked:
			actors[id].x += movement.x
			actors[id].y += movement.y

class TestGame extends Node2D:
	const TILE_SIZE := 32.0
	const PLAYER_MOVE_SPEED_TILES_PER_SECOND := 5.0
	var player := {"entity_id": "player", "current_hp": 10}
	var combat := {"actors": {}}
	var actor_sprites: Dictionary = {}
	var ground_drops: Array = []
	var world := TestWorld.new()
	var spawn_menu := Control.new()
	var item_menu := Control.new()
	var inventory_menu := Control.new()
	var context_menu := TestMenu.new()
	var map_scene_mode := false
	var grid_adapter: Node
	var offline_mining: Node
	var reset_count := 0
	var target := ""
	func _ready() -> void:
		for menu: Control in [spawn_menu, item_menu, inventory_menu, context_menu]:
			add_child(menu)
			menu.hide()
		var actor := CombatActor.new()
		actor.entity_id = "player"
		combat.actors.player = actor
		world.actors = combat.actors
		var sprite := Node2D.new()
		add_child(sprite)
		actor_sprites.player = sprite
	func fishing_spots() -> Array:
		return []
	func _ui_is_editing() -> bool:
		return false
	func _clear_target() -> void:
		target = ""
	func _reset_held_movement() -> void:
		reset_count += 1
	func _update_sprite_position(id: String) -> void:
		actor_sprites[id].position = Vector2(combat.actors[id].x, combat.actors[id].y) * TILE_SIZE

class TestPortal extends CavePortal:
	var entries := 0
	func try_enter(game: Node) -> bool:
		if game.actor_sprites.player.global_position.distance_to(approach_position()) > interaction_radius:
			return false
		entries += 1
		return true

var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("[Portal FAIL] ", label)

func _initialize() -> void:
	_run.call_deferred()

func _click(controller: Node, point: Vector2, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	controller.handle_click(event, point)

func _walk_to_end(controller: Node) -> void:
	for frame in range(360):
		controller.update_walk(1.0 / 60.0)
		if not controller.walking:
			break

func _run() -> void:
	var map := Node2D.new()
	root.add_child(map)
	var game := TestGame.new()
	map.add_child(game)
	# Load after autoload creation, as the fishing dependencies use GameData.
	var controller: Node = load("res://scripts/world_interaction.gd").new()
	game.add_child(controller)
	controller.configure(game)
	var nested := Node2D.new()
	map.add_child(nested)
	var portal := TestPortal.new()
	portal.position = Vector2(320, 0)
	portal.approach_offset = Vector2.ZERO
	portal.interaction_radius = 16
	portal.click_rect = Rect2(-24, -60, 48, 72)
	nested.add_child(portal)
	var other_map := Node2D.new()
	root.add_child(other_map)
	var foreign := CavePortal.new()
	foreign.position = portal.global_position
	other_map.add_child(foreign)
	check(controller.portals_at(portal.global_position) == [portal], "Nested portals are discovered and other map portals are excluded")
	check(portal.contains_global_point(portal.global_position) and not portal.contains_global_point(portal.global_position + Vector2(60, 0)), "Doorway rectangle only accepts its own area")
	portal.hit_polygon = PackedVector2Array([Vector2(-10, -10), Vector2(10, -10), Vector2(0, 10)])
	check(portal.contains_global_point(portal.global_position) and not portal.contains_global_point(portal.global_position + Vector2(20, 0)), "Authored polygon takes precedence over rectangle")
	portal.hit_polygon = PackedVector2Array()
	_click(controller, portal.global_position, MOUSE_BUTTON_LEFT)
	check(controller.walking and controller.pending_portal == portal and portal.entries == 0, "Distant left-click queues Enter without teleporting")
	_walk_to_end(controller)
	check(portal.entries == 1 and not controller.walking and controller.pending_portal == null, "Enter walks into range then fires exactly once")
	_click(controller, portal.global_position, MOUSE_BUTTON_LEFT)
	check(portal.entries == 2 and not controller.walking, "Nearby left-click enters immediately")
	game.combat.actors.player.x = 0
	game._update_sprite_position("player")
	_click(controller, portal.global_position, MOUSE_BUTTON_RIGHT)
	check(game.context_menu.actions.size() == 2 and String(game.context_menu.actions[0].label).begins_with("Enter ") and game.context_menu.actions[1].label == "Walk here", "Right-click doorway offers Enter and Walk here")
	var walk_action: Callable = game.context_menu.actions[1].action
	game.context_menu.hide()
	walk_action.call()
	check(controller.walking and controller.pending_portal == null and controller.destination == portal.approach_position() / game.TILE_SIZE, "Walk here targets safe approach without Enter intent")
	_walk_to_end(controller)
	check(portal.entries == 2 and not controller.walking, "Walking to the entrance never teleports")
	game.combat.actors.player.x = 0
	game._update_sprite_position("player")
	controller.request_portal(portal)
	controller.cancel_walk()
	check(controller.pending_portal == null and not controller.walking, "Manual movement cancellation clears queued Enter")
	controller.request_portal(portal)
	_click(controller, Vector2(160, 160), MOUSE_BUTTON_LEFT)
	check(controller.pending_portal == null and controller.walking and controller.destination == Vector2(5, 5), "Ground click replaces queued Enter with the chosen walk destination")
	_walk_to_end(controller)
	check(portal.entries == 2 and not controller.walking, "Replacement ground walk never triggers the cancelled portal")
	controller.request_portal(portal)
	game.world.blocked = true
	_walk_to_end(controller)
	check(not controller.walking and controller.pending_portal == null and portal.entries == 2, "Blocked approach cancels instead of teleporting through terrain")
	game.world.blocked = false
	controller.request_portal(portal)
	portal.enabled = false
	controller.update_walk(0.1)
	check(not controller.walking and portal.entries == 2, "Disabling a portal cancels its pending interaction")
	portal.enabled = true
	game.combat.actors.player.is_alive = false
	controller.request_portal(portal)
	check(not controller.walking and portal.entries == 2, "Dead player cannot queue or enter a portal")
	var real := CavePortal.new()
	real.destination_scene = "res://scenes/EastOutskirtsLayered.tscn"
	nested.add_child(real)
	check(not real.try_enter(game), "Production portal rejects a dead player")
	game.combat.actors.player.is_alive = true
	game.player.current_hp = 0
	check(not real.try_enter(game), "Production portal rejects zero-health player before travel")
	game.player.current_hp = 10
	real.position = Vector2(3000, 0)
	check(not real.try_enter(game), "Production portal cannot travel while outside interaction range")
	var stale := CavePortal.new()
	nested.add_child(stale)
	var stale_id := stale.get_instance_id()
	stale.free()
	controller._portal_instance(stale_id)
	check(not controller.walking, "Freed portal menu actions are safe")
	map.free()
	other_map.free()
	print("[Portal] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
