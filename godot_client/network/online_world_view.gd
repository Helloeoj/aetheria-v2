extends Node
## Read-only projection of authoritative actors and committed character progress.
const Codec = preload("res://network/character_codec.gd")
const Prediction = preload("res://network/movement_prediction.gd")
const Interpolation = preload("res://network/snapshot_interpolation.gd")
const ActivityPanel = preload("res://network/online_activity_panel.gd")
var game: Node
var activity_panel: Control
var status_label: Label
var _drops: Dictionary = {}
var _prediction := Prediction.new()
var _motion: Dictionary = {}
var _server_time := 0.0
var _received_elapsed := 0.0
var _interval := 0.1
var _has_self := false
var _keyboard := false
var _movement_enabled := false

func configure(owner_game: Node) -> void:
	game = owner_game
	_prediction.move_resolver = _resolve_movement
	activity_panel = ActivityPanel.new()
	game.ui_root.add_child(activity_panel)
	activity_panel.configure(game)
	var logout := Button.new()
	logout.text = "Save and log out"
	logout.position = Vector2(1040, 12)
	logout.custom_minimum_size = Vector2(210, 38)
	logout.pressed.connect(Network.request_logout)
	game.ui_root.add_child(logout)
	status_label = Label.new()
	status_label.position = Vector2(735, 53)
	status_label.size = Vector2(510, 42)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.add_theme_font_size_override("font_size", 15)
	status_label.text = Network.status
	game.ui_root.add_child(status_label)
	Network.status_changed.connect(_status)
	game.fishing_test_button.hide()
	game.skill_test_button.hide()
	game.spawn_menu.hide()
	game.item_menu.hide()
	game.skill_debug_panel.hide()

func _status() -> void:
	if is_instance_valid(status_label):
		status_label.text = Network.status

func apply(snapshot: Dictionary) -> void:
	if not is_instance_valid(game) or not Network.authenticated:
		return
	var live_position: Vector2 = game.player.get_position()
	if snapshot.get("state") is Dictionary and not snapshot.state.is_empty():
		Codec.apply_to(game.player, snapshot.state)
		# Durable checkpoints are not live movement corrections.
		game.player.x = live_position.x
		game.player.y = live_position.y
	_server_time = float(snapshot.get("server_time", _server_time + _interval))
	_interval = clampf(float(snapshot.get("snapshot_interval", 0.1)), 1.0 / 60.0, 0.5)
	_received_elapsed = 0.0
	_movement_enabled = bool(snapshot.get("movement_enabled", false))
	var seen := {}
	for data: Dictionary in snapshot.get("actors", []):
		var id := String(data.entity_id)
		seen[id] = true
		var monster := bool(data.get("is_monster", false))
		var actor: CombatActor = game.combat.actors.get(id)
		if actor == null:
			actor = CombatActor.new().configure(data)
			game.combat.add_actor(actor)
		actor.x = float(data.x)
		actor.y = float(data.y)
		actor.hp = int(data.hp)
		actor.max_hp = int(data.max_hp)
		actor.is_alive = bool(data.is_alive)
		actor.is_monster = monster
		actor.current_target_id = String(data.get("target_id", ""))
		var sprite: ActorSprite = game.actor_sprites.get(id)
		if sprite == null:
			sprite = ActorSprite.new().configure(Vector2(32, 32), game.MONSTER_COLOR if monster else game.PLAYER_COLOR, id)
			sprite.set_skin(CharacterSpriteLibrary.skin_for_monster(String(data.name)) if monster else CharacterSpriteLibrary.default_player_skin())
			game.add_child(sprite)
			game.actor_sprites[id] = sprite
			if monster:
				var template := GameData.get_monster_by_name(String(data.name))
				if not template.is_empty():
					var state := MonsterState.new(template, actor.x, actor.y)
					state.entity_id = id
					game.world.monsters.append(state)
					game._register_monster_for_targeting(state)
		if not monster:
			var equipment := {}
			for slot: String in data.get("equipment", {}):
				var item_name: Variant = data.equipment[slot]
				if item_name is String:
					equipment[slot] = GameData.get_item_by_name(item_name)
			sprite.set_equipment(equipment)
		sprite.set_dead(not actor.is_alive)
		if id == game.player.entity_id:
			game.player.x = actor.x
			game.player.y = actor.y
			game.player.current_hp = actor.hp
			game.player.current_target = actor.current_target_id
			game.player.in_combat = bool(snapshot.get("in_combat", false))
			var point := Vector2(actor.x, actor.y)
			if not _has_self:
				_prediction.reset(point)
				_has_self = true
			_prediction.reconcile(point, int(snapshot.get("movement_ack", -1)), float(snapshot.get("movement_age", 0.0)), _movement_enabled and actor.is_alive)
		if not _motion.has(id):
			_motion[id] = Interpolation.new()
		_motion[id].push(_server_time, Vector2(actor.x, actor.y))
		if id == game.player.entity_id and (not actor.is_alive or not _movement_enabled):
			_render_actor(id, Vector2(actor.x, actor.y))
		elif _motion[id]._samples.size() == 1:
			_render_actor(id, Vector2(actor.x, actor.y))
	if not seen.has(game.player.entity_id):
		_movement_enabled = false
		_prediction.reconcile(game.player.get_position(), -1, 0.0, false)
		_render_actor(game.player.entity_id, game.player.get_position())
	for id: String in game.actor_sprites.keys():
		if id != game.player.entity_id and not seen.has(id):
			game.actor_sprites[id].queue_free()
			game.actor_sprites.erase(id)
			_motion.erase(id)
			game.combat.remove_actor(id)
			for monster: MonsterState in game.world.monsters.duplicate():
				if monster.entity_id == id:
					game.world.monsters.erase(monster)
			game._unregister_monster_for_targeting(id)
	var drop_ids := {}
	for data: Dictionary in snapshot.get("drops", []):
		var id := String(data.drop_id)
		drop_ids[id] = true
		if not _drops.has(id):
			var drop := GroundItemDrop.new().configure(String(data.item_name), int(data.quantity))
			drop.set_meta("online_drop_id", id)
			drop.position = game._screen_position(float(data.x), float(data.y))
			game.add_child(drop)
			game.ground_drops.append(drop)
			_drops[id] = drop
	for id: String in _drops.keys():
		if not drop_ids.has(id):
			game.ground_drops.erase(_drops[id])
			if is_instance_valid(_drops[id]):
				_drops[id].queue_free()
			_drops.erase(id)
	game.inventory_menu.queue_redraw()
	game._update_target_highlight()
	game._update_food_ui()
	game._update_map_camera()
	game.queue_redraw()

func record_command(sequence: int, command: Dictionary) -> void:
	if command.get("type") == "move":
		var direction: Array = command.direction
		_prediction.record_input(sequence, Vector2(float(direction[0]), float(direction[1])))
		_keyboard = true
	elif command.get("type") in ["walk", "attack", "target", "cast", "travel"]:
		_keyboard = false
		_prediction.reset(_prediction.render_position())

func _process(delta: float) -> void:
	if Network.authenticated and Network.game == game:
		advance_presentation(delta, Network.movement_direction())

func advance_presentation(delta: float, direction: Vector2) -> void:
	if not is_instance_valid(game) or not _has_self:
		return
	_received_elapsed += delta
	if _movement_enabled:
		# Only remote actors need the buffered timeline. Own click/chase updates
		# ease toward authority immediately instead of adding another packet delay.
		_prediction.advance(delta, direction if _keyboard else Vector2.ZERO)
		_render_actor(game.player.entity_id, _prediction.render_position())
	for id: String in _motion:
		if id == game.player.entity_id:
			continue
		_render_actor(id, _motion[id].sample(_server_time + _received_elapsed - _interval))
	game._update_map_camera()
	game.queue_redraw()

func _render_actor(id: String, point: Vector2) -> void:
	var sprite: ActorSprite = game.actor_sprites.get(id)
	if sprite == null:
		return
	var next: Vector2 = game._screen_position(point.x, point.y)
	var previous := sprite.position
	sprite.position = next
	sprite.update_visual_motion(next - previous)
	game.visual_positions[id] = next

func _resolve_movement(start: Vector2, motion: Vector2) -> Vector2:
	var bounded: Vector2 = (start + motion).clamp(game.world.movement_min, game.world.movement_max)
	var displacement := bounded - start
	var sprite: ActorSprite = game.actor_sprites.get(game.player.entity_id)
	if sprite == null:
		return start
	var rendered := sprite.position
	sprite.position = game._screen_position(start.x, start.y)
	var actual: Vector2 = game._move_actor_with_map_collision(game.player.entity_id, displacement)
	sprite.position = rendered
	if not actual.is_finite() or actual.length() > displacement.length() + 0.001:
		return start
	return (start + actual.limit_length(displacement.length())).clamp(game.world.movement_min, game.world.movement_max)

func open_activity(station: Node, kind: String, title: String) -> void:
	var path := str(game.get_parent().get_path_to(station))
	game._reset_held_movement()
	activity_panel.open_station(path, kind, title)
