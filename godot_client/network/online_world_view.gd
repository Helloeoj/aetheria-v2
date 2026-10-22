extends Node
## Read-only projection of authoritative actors and committed character progress.
const Codec = preload("res://network/character_codec.gd")
var game: Node
var activity_panel: Control
var status_label: Label
var _drops: Dictionary = {}

func configure(owner_game: Node) -> void:
	game = owner_game
	activity_panel = game.fishing_panel
	var logout := Button.new()
	logout.name = "OnlineLogoutButton"
	logout.text = "Save and log out"
	logout.position = Vector2(1040, 12)
	logout.custom_minimum_size = Vector2(210, 38)
	logout.pressed.connect(Network.request_logout)
	game.ui_root.add_child(logout)
	status_label = Label.new()
	status_label.name = "OnlineStatusLabel"
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
	if snapshot.get("state") is Dictionary and not snapshot.state.is_empty():
		Codec.apply_to(game.player, snapshot.state)
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
		game._update_sprite_position(id)
	for id: String in game.actor_sprites.keys():
		if id != game.player.entity_id and not seen.has(id):
			game.actor_sprites[id].queue_free()
			game.actor_sprites.erase(id)
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

func open_activity(station: Node, kind: String, title: String) -> void:
	if kind == "fish":
		game.request_fishing(station)
	elif kind == "cook":
		game.cooking_controller.open(station)
