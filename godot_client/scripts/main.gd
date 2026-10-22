extends Node2D

const TILE_SIZE := 32
const ORIGINAL_MAP_HEIGHT := 1024.0
const TICK_DURATION := GameTickConfig.TICK_DURATION_SECONDS
const PLAYER_COLOR := Color(0.0, 0.0, 1.0)
const MONSTER_COLOR := Color(0.09, 0.45, 0.27)
const MONSTER_TARGETED_COLOR := Color(1.0, 0.0, 0.0)
const PROJECTILE_COLOR := Color(1.0, 0.84, 0.0)
const MELEE_RANGE_TILES := 2.0
const PLAYER_MOVE_SPEED_TILES_PER_SECOND := 4.0
const CAMERA_MIN_ZOOM := 1.5
const CAMERA_MAX_ZOOM := 4.0
const CAMERA_ZOOM_STEP := 1.15
# F9 suspends Godot's embedded game, so keep practice on an ordinary key.
const FISHING_TEST_KEY := KEY_P
const SKILL_TEST_KEY := KEY_K

@export var max_skills_for_testing := false
@export var map_origin := Vector2.ZERO
@export var map_width := 1536.0
@export var map_height := 1024.0
@export var area_name := "Valtheiris"
@export var initial_spawn_id := ""

@onready var spawn_menu: SpawnMenu = $UI/SpawnMenu
@onready var item_menu: ItemMenu = $UI/ItemMenu
@onready var inventory_menu: InventoryMenu = $UI/InventoryMenu

var player := PlayerState.new("Player")
var skill_training_session := SkillTrainingSession.new()
var world: WorldState
var combat: CombatEngine
var loot_system := LootSystem.new()
var actor_sprites: Dictionary = {} # entity_id -> ActorSprite
var visual_positions: Dictionary = {} # Last synchronized position, independent of physics motion.
var sprite_preview: SpritePreview
var movement_controller: MovementController
var target_list: Array[String] = []
var target_index := -1
var auto_chase_target := false
var tick_elapsed := 0.0
var next_monster_number := 1
var spell_cast_requested := false
var map_scene_mode := false
var skill_debug_panel: SkillDebugPanel
var character_menu_button: Button
var ground_drops: Array[GroundItemDrop] = []
var context_menu: InteractionContextMenu
var interactions: WorldInteraction
var health_bar_layer: Node2D
var ui_root: Control
var fishing_panel: FishingPanel
var fishing_notice: Label
var fishing_notice_time := 0.0
var fishing_test_button: Button
var skill_test_button: Button
var fishing_practice_spot: FishingSpot
var food_button: Button
var food_notice: Label
var food_notice_time := 0.0
var crafting_panel: Control
var cooking_controller: Node
var online_view: Node

func request_crafting(station: Node2D) -> void:
	if cooking_controller != null and cooking_controller.panel.visible:
		return
	if not is_instance_valid(station) or not station.is_available(player):
		return
	if combat.active_spell_casts.has(player.entity_id):
		return
	inventory_menu.hide()
	spawn_menu.hide()
	item_menu.hide()
	if fishing_panel != null and fishing_panel.visible:
		fishing_panel.close()
	if context_menu != null:
		context_menu.dismiss()
	interactions.cancel_walk()
	_reset_held_movement()
	crafting_panel.show_station(station)

func _setup_crafting() -> void:
	crafting_panel = preload("res://scripts/ui_crafting.gd").new()
	crafting_panel.name = "CraftingPanel"
	ui_root.add_child(crafting_panel)
	crafting_panel.configure(self)
	if map_scene_mode and not get_parent().scene_file_path.ends_with("EastOutskirtsLayered.tscn"):
		return
	var definitions := [
		["furnace", "Blacksmith's Furnace"], ["anvil", "Blacksmith's Anvil"],
		["leatherworking", "Leatherworking Bench"], ["tailoring", "Tailoring Bench"],
		["fletching", "Fletching Bench"], ["bait_store", "Bait Store"]
	]
	for index in range(definitions.size()):
		var point := player.get_position() + Vector2(4 + (index % 3) * 3, floori(float(index) / 3.0) * 3)
		point.x = clampf(point.x, world.movement_min.x + 1, world.movement_max.x - 1)
		point.y = clampf(point.y, world.movement_min.y + 1, world.movement_max.y - 1)
		var station := preload("res://scripts/crafting_station.gd").new()
		station.setup(String(definitions[index][0]), String(definitions[index][1]), point)
		station.position = _screen_position(point.x, point.y)
		add_child(station)

func set_quick_food(item_name: String) -> bool:
	if Network.online():
		return Network.send_action({"type": "set_quick_food", "item_name": item_name})
	if int(player.backpack.get(item_name, 0)) <= 0 or int(GameData.get_item_by_name(item_name).get("food_healing", 0)) <= 0:
		return false
	player.quick_food_name = item_name
	_update_food_ui()
	return true

func eat_food(item_name: String) -> Dictionary:
	if Network.online():
		Network.send_action({"type": "eat", "item_name": item_name})
		return {"ok": true, "healing": 0, "message": "Food request sent to the server."}
	var reason := ""
	var actor: CombatActor = combat.actors.get(player.entity_id)
	if actor == null:
		reason = "Your character is unavailable."
	elif fishing_panel != null and fishing_panel.visible:
		reason = "Finish fishing and move your catch into the backpack before eating."
	elif item_name.is_empty():
		reason = "Choose food in your backpack [I]."
	else:
		# Combat HP is authoritative, including damage since the last UI refresh.
		player.current_hp = actor.hp
		reason = FishingSession.eating_error(player, item_name, combat)
	if not reason.is_empty():
		_show_food_notice(reason, false)
		return {"ok": false, "healing": 0, "message": reason}
	var restored := FishingSession.eat(player, item_name, combat)
	var message := "Ate %s: +%d HP (%d/%d)." % [item_name, restored, player.current_hp, player.get_max_hp()]
	_refresh_player_actor_from_player()
	_refresh_character_ui()
	_show_food_notice(message, true)
	_update_food_ui()
	return {"ok": true, "healing": restored, "message": message}

func _eat_quick_food() -> void:
	eat_food(player.get_quick_food())

func _show_food_notice(message: String, success: bool) -> void:
	food_notice.text = message
	food_notice.modulate = FantasyUI.TEAL if success else FantasyUI.GOLD
	food_notice_time = 4.0
	food_notice.show()

func _update_food_ui() -> void:
	if food_button == null:
		return
	var modal := inventory_menu.visible or spawn_menu.visible or item_menu.visible
	modal = modal or (crafting_panel != null and crafting_panel.visible)
	modal = modal or (fishing_panel != null and fishing_panel.visible)
	modal = modal or (sprite_preview != null and sprite_preview.visible)
	modal = modal or (skill_debug_panel != null and skill_debug_panel.visible)
	food_button.visible = not modal
	food_notice.visible = not modal and food_notice_time > 0.0
	var item_name := player.get_quick_food()
	var item := GameData.get_item_by_name(item_name)
	var quantity := int(player.backpack.get(item_name, 0))
	var status := "Ready"
	if quantity <= 0:
		status = "Choose food in backpack [I]" if item_name.is_empty() else "No food left - choose another [I]"
	elif player.current_hp <= 0:
		status = "Cannot eat while defeated"
	elif player.food_cooldown_seconds > 0.0:
		status = "Eating cooldown: %.1fs" % (ceilf(player.food_cooldown_seconds * 10.0) / 10.0)
	elif combat.active_spell_casts.has(player.entity_id):
		status = "Finish casting first"
	elif player.current_hp >= player.get_max_hp():
		status = "Full health"
	food_button.text = "Food [H]\n%s" % status if item_name.is_empty() else "Eat [H]  %s x%d  (+%d HP)\n%s" % [item_name, quantity, int(item.get("food_healing", 0)), status]
	food_button.disabled = quantity <= 0 or not FishingSession.eating_error(player, item_name, combat).is_empty()
	food_button.tooltip_text = "Choose a fish in the backpack and select Set quick food. Eating adds one weapon attack interval (%.2fs) to the remaining attack delay. Meals share a %.1fs cooldown." % [FishingSession.eating_attack_delay_seconds(player), FishingSession.EATING_COOLDOWN_SECONDS]
	food_button.icon = ItemVisualLibrary.texture(item_name) if not item_name.is_empty() else FantasyUI.icon("health")

func toggle_skill_debug_panel() -> void:
	if Network.online():
		return
	if skill_debug_panel == null:
		return
	var show_panel := not skill_debug_panel.visible
	if show_panel:
		if fishing_panel != null and fishing_panel.visible:
			fishing_panel.close()
		if sprite_preview != null and sprite_preview.visible:
			sprite_preview.hide_preview()
		if context_menu != null:
			context_menu.dismiss()
		spawn_menu.hide()
		item_menu.hide()
		inventory_menu.hide()
		if interactions != null:
			interactions.cancel_walk()
		_clear_target()
		get_viewport().gui_release_focus()
		skill_debug_panel.refresh()
	skill_debug_panel.visible = show_panel
	_reset_held_movement()
	spell_cast_requested = false

func start_fishing_test() -> void:
	if Network.online():
		return
	if fishing_panel.visible:
		return
	if player.current_hp <= 0 or player.in_combat or combat.active_spell_casts.has(player.entity_id):
		show_fishing_notice("Restore health and finish combat or casting before testing fishing.")
		return
	# Supply the test kit without duplicating poles or accumulating bait on re-entry.
	for item_name: String in FishingSession.RODS + FishingSession.BAITS:
		var wanted := 50 if item_name in FishingSession.BAITS else 1
		var missing := maxi(0, wanted - int(player.backpack.get(item_name, 0)))
		if missing > 0:
			player.add_item(item_name, missing)
	if not is_instance_valid(fishing_practice_spot):
		fishing_practice_spot = FishingSpot.new()
		fishing_practice_spot.name = "FishingPracticeSpot"
		fishing_practice_spot.spot_name = "Fishing practice"
		fishing_practice_spot.hide()
		add_child(fishing_practice_spot)
	var sprite: ActorSprite = actor_sprites.get(player.entity_id)
	if sprite == null:
		return
	fishing_practice_spot.global_position = sprite.global_position - fishing_practice_spot.shore_offset
	_clear_target()
	request_fishing(fishing_practice_spot)

func fishing_spots() -> Array[FishingSpot]:
	var result: Array[FishingSpot] = []
	for child: Node in get_children():
		if child is FishingSpot and child != fishing_practice_spot:
			result.append(child)
	return result

func show_fishing_notice(message: String) -> void:
	fishing_notice.text = message
	fishing_notice_time = 5.0

func request_fishing(spot: FishingSpot) -> void:
	if Network.online() and online_view != null:
		online_view.open_activity(spot, "fish", spot.spot_name)
		return
	var sprite: ActorSprite = actor_sprites.get(player.entity_id)
	if player.current_hp <= 0 or sprite == null:
		return
	if sprite.global_position.distance_to(spot.shore_position()) > spot.interact_radius:
		show_fishing_notice("Walk closer to the fishing spot, then click it or press F.")
		return
	if player.in_combat or not player.current_target.is_empty():
		show_fishing_notice("Finish combat and clear your target before fishing.")
		return
	_reset_held_movement()
	interactions.cancel_walk()
	interactions.clear_drop_selection()
	_clear_target()
	context_menu.dismiss()
	spawn_menu.hide()
	item_menu.hide()
	inventory_menu.hide()
	if skill_debug_panel != null:
		skill_debug_panel.hide()
	spell_cast_requested = false
	fishing_notice.text = ""
	fishing_panel.open(spot)

func try_nearby_fishing() -> bool:
	var sprite: ActorSprite = actor_sprites.get(player.entity_id)
	if sprite == null:
		return false
	var nearest: FishingSpot
	var best := INF
	for spot: FishingSpot in fishing_spots():
		var distance := sprite.global_position.distance_to(spot.shore_position())
		if distance <= spot.interact_radius and distance < best:
			nearest = spot
			best = distance
	if nearest == null:
		return false
	request_fishing(nearest)
	return true

func _ready() -> void:
	# Character progress belongs to the running session, rather than a map scene.
	var travel := get_node_or_null("/root/SceneTravel")
	var resuming_character := false
	if Network.online() and Network.authenticated:
		var decoded: Dictionary = preload("res://network/character_codec.gd").decode(Network.saved_state, Network.username, Network.character_id)
		if decoded.ok:
			player = decoded.player
			resuming_character = true
	elif travel != null and not has_meta("online_server_geometry"):
		resuming_character = travel.bind_game(self)
	DiagnosticCore.register_context_provider(_diagnostic_context)
	AetheriaDiagnostics.event("Character", "initialize player", {"entity": player.entity_id})
	map_scene_mode = get_node_or_null("../MapCamera") != null
	y_sort_enabled = true
	if map_scene_mode:
		# Extending north or west changes simulation bounds, while existing map nodes stay put.
		if not resuming_character:
			player.x += _map_x_offset_tiles()
			player.y += _map_y_offset_tiles()
		var collision_camera := get_node_or_null("../CollisionGeometry/ReferenceCamera") as Camera2D
		if collision_camera != null:
			collision_camera.enabled = false
		var map_camera := get_node_or_null("../MapCamera") as Camera2D
		if map_camera != null:
			map_camera.zoom = Vector2.ONE * clampf(map_camera.zoom.x, CAMERA_MIN_ZOOM, CAMERA_MAX_ZOOM)
			map_camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
			map_camera.make_current()
	if travel != null and not has_meta("online_server_geometry") and not Network.online():
		travel.resolve_spawn(self)
	if not resuming_character and not initial_spawn_id.is_empty():
		var initial_spawn := get_parent().get_node_or_null("SpawnPoints/" + initial_spawn_id) as Node2D
		if initial_spawn != null:
			var spawn_point := to_local(initial_spawn.global_position)
			player.x = (spawn_point.x - map_origin.x) / TILE_SIZE
			player.y = (map_origin.y + map_height - spawn_point.y) / TILE_SIZE
	if max_skills_for_testing and not resuming_character:
		for skill: String in SkillProgression.SKILL_IDS:
			player.set_skill_level(skill, SkillProgression.MAX_LEVEL)
	if not resuming_character:
		player.current_hp = player.get_max_hp()
	var initial_spell := GameData.get_spell(player.selected_spell_id)
	if initial_spell.is_empty():
		initial_spell = player.cycle_known_spell(1)
	print("[Spellbook] Combat level %d (Magic %d). Selected %s. Use Q/R to browse and E to cast." % [
		player.get_combat_level(), player.get_magic_level(), String(initial_spell.get("name", "spell"))
	])
	world = WorldState.new(player, [])
	if map_scene_mode:
		world.world.width = int(map_width / TILE_SIZE)
		world.world.height = int(map_height / TILE_SIZE)
		world.set_movement_bounds(
			Vector2(0.5, 0.5),
			Vector2(map_width / TILE_SIZE - 0.5, map_height / TILE_SIZE - 0.5)
		)
		world.set_collision_handlers(
			Callable(self, "_move_actor_with_map_collision"),
			Callable(self, "_query_map_terrain_collision")
		)
	combat = world.combat
	combat.player_auto_attack_enabled = false
	movement_controller = MovementController.new()
	var player_sprite := ActorSprite.new().configure(Vector2(TILE_SIZE, TILE_SIZE), PLAYER_COLOR, player.entity_id)
	player_sprite.set_skin(CharacterSpriteLibrary.default_player_skin())
	add_child(player_sprite)
	actor_sprites[player.entity_id] = player_sprite
	_update_sprite_position(player.entity_id)
	world.register_player_actor(_create_actor_from_stats(player.entity_id, player.name, player.x, player.y, player.get_combat_stats()))
	# Scale only the interface: camera zoom and the world remain independent.
	ui_root = Control.new()
	ui_root.name = "ReadableUI"
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(ui_root)
	for widget: Control in [spawn_menu, item_menu, inventory_menu]:
		widget.reparent(ui_root)
	get_viewport().size_changed.connect(_update_ui_scale)
	_update_ui_scale()
	spawn_menu.configure(self, _active_monster_database())
	item_menu.configure(self, GameData.items_by_id)
	inventory_menu.configure(self)
	skill_debug_panel = SkillDebugPanel.new()
	skill_debug_panel.name = "SkillDebugPanel"
	ui_root.add_child(skill_debug_panel)
	skill_debug_panel.configure(self)
	skill_debug_panel.hide()
	skill_debug_panel.skill_levels_changed.connect(_on_practice_skill_levels_changed)
	skill_debug_panel.health_restored.connect(_refresh_character_ui)
	skill_debug_panel.close_requested.connect(toggle_skill_debug_panel)
	character_menu_button = Button.new()
	character_menu_button.name = "JournalButton"
	character_menu_button.theme = FantasyUI.make_theme()
	character_menu_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	character_menu_button.text = "Journal  [I]"
	character_menu_button.icon = FantasyUI.icon("bag")
	character_menu_button.expand_icon = true
	character_menu_button.add_theme_constant_override("icon_max_width", 22)
	character_menu_button.position = Vector2(22, 10)
	character_menu_button.custom_minimum_size = Vector2(190, 42)
	character_menu_button.focus_mode = Control.FOCUS_NONE
	character_menu_button.pressed.connect(_toggle_character_menu)
	ui_root.add_child(character_menu_button)
	fishing_test_button = Button.new()
	fishing_test_button.name = "FishingTestButton"
	fishing_test_button.theme = FantasyUI.make_theme()
	fishing_test_button.text = "Test fishing  [P]"
	fishing_test_button.tooltip_text = "Open fishing here with all test poles and 50 of each bait. Normal Fishing level requirements apply."
	fishing_test_button.position = Vector2(226, 10)
	fishing_test_button.custom_minimum_size = Vector2(230, 42)
	fishing_test_button.focus_mode = Control.FOCUS_NONE
	fishing_test_button.pressed.connect(start_fishing_test)
	ui_root.add_child(fishing_test_button)
	skill_test_button = Button.new()
	skill_test_button.name = "SkillTestButton"
	skill_test_button.theme = FantasyUI.make_theme()
	skill_test_button.text = "Test skills  [K]"
	skill_test_button.tooltip_text = "Adjust all skill levels manually and restore health for testing."
	skill_test_button.position = Vector2(470, 10)
	skill_test_button.custom_minimum_size = Vector2(230, 42)
	skill_test_button.focus_mode = Control.FOCUS_NONE
	skill_test_button.pressed.connect(toggle_skill_debug_panel)
	ui_root.add_child(skill_test_button)
	sprite_preview = SpritePreview.new()
	ui_root.add_child(sprite_preview)
	sprite_preview.closed.connect(_reset_held_movement)
	sprite_preview.spawn_requested.connect(spawn_monster_by_id)
	context_menu = InteractionContextMenu.new()
	context_menu.name = "InteractionContextMenu"
	ui_root.add_child(context_menu)
	interactions = WorldInteraction.new()
	interactions.name = "WorldInteraction"
	add_child(interactions)
	interactions.configure(self)
	fishing_panel = FishingPanel.new()
	fishing_panel.name = "FishingPanel"
	ui_root.add_child(fishing_panel)
	fishing_panel.configure(self)
	fishing_notice = Label.new()
	fishing_notice.position = Vector2(22, 58)
	fishing_notice.add_theme_font_size_override("font_size", 18)
	fishing_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(fishing_notice)
	food_button = Button.new()
	food_button.name = "QuickFoodButton"
	food_button.theme = FantasyUI.make_theme()
	food_button.focus_mode = Control.FOCUS_NONE
	food_button.expand_icon = true
	food_button.add_theme_constant_override("icon_max_width", 36)
	food_button.custom_minimum_size = Vector2(350, 64)
	food_button.pressed.connect(_eat_quick_food)
	ui_root.add_child(food_button)
	food_notice = Label.new()
	food_notice.name = "FoodNotice"
	food_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	food_notice.add_theme_font_size_override("font_size", 18)
	food_notice.add_theme_color_override("font_shadow_color", Color.BLACK)
	food_notice.add_theme_constant_override("shadow_offset_x", 1)
	food_notice.add_theme_constant_override("shadow_offset_y", 1)
	ui_root.add_child(food_notice)
	_update_ui_scale()
	_update_food_ui()
	# Provision only once; entering another area must not duplicate the starter kit.
	_setup_crafting()
	cooking_controller = preload("res://scripts/cooking_controller.gd").new()
	cooking_controller.name = "CookingController"
	add_child(cooking_controller)
	cooking_controller.configure(self)
	if not resuming_character:
		player.add_item("Beginner Rod")
		player.add_item("Low Grade Fish Food", 30)
	# Health indicators render above scenery independently of actor Y sorting.
	health_bar_layer = Node2D.new()
	health_bar_layer.name = "HealthBarOverlay"
	health_bar_layer.z_as_relative = false
	health_bar_layer.z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	health_bar_layer.draw.connect(_draw_health_bars)
	add_child(health_bar_layer)
	_update_map_camera()
	print("[UI] I opens the character journal; K toggles skill testing. F5 spawns monsters; F7 opens the sprite viewer; P tests fishing anywhere.")
	queue_redraw()
	if Network.online():
		online_view = preload("res://network/online_world_view.gd").new()
		add_child(online_view)
		online_view.configure(self)
		Network.bind_game(self)
		var social := get_node_or_null("/root/Social")
		if social != null and social.panel != null:
			social.panel.show()
	elif not has_meta("online_server_geometry"):
		var online_login := Button.new()
		online_login.name = "OnlineLoginButton"
		online_login.text = "Developer sandbox · Online login"
		online_login.position = Vector2(970, 10)
		online_login.custom_minimum_size = Vector2(285, 42)
		online_login.focus_mode = Control.FOCUS_NONE
		online_login.tooltip_text = "This sandbox keeps all developer controls. Log in separately to play your saved online character."
		online_login.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/Login.tscn"))
		ui_root.add_child(online_login)

func apply_online_snapshot(snapshot: Dictionary) -> void:
	if online_view != null:
		online_view.apply(snapshot)

func _update_ui_scale() -> void:
	if ui_root == null:
		return
	var pixels := get_viewport_rect().size
	var factor := maxf(0.5, minf(pixels.x / 1280.0, pixels.y / 720.0))
	ui_root.scale = Vector2.ONE * factor
	ui_root.size = pixels / factor
	if food_button != null:
		food_button.position = Vector2(22, ui_root.size.y - 294)
		food_notice.position = Vector2(22, ui_root.size.y - 328)
	if inventory_menu != null:
		inventory_menu._update_layout()
	if skill_debug_panel != null:
		skill_debug_panel._update_layout()
	if item_menu != null:
		item_menu.queue_redraw()

func _diagnostic_context() -> Dictionary:
	if not is_inside_tree():
		return {}
	var scene := get_tree().current_scene
	return {"scene": scene.scene_file_path if scene != null else scene_file_path, "map": area_name if map_scene_mode else "combat demo", "player_id": player.entity_id, "player_position_tiles": [player.x, player.y], "target_id": player.current_target}

func _input(event: InputEvent) -> void:
	var social: Node = get_node_or_null("/root/Social")
	if social != null and social.handle_game_key(event, self):
		return
	if Network.online() and online_view != null and online_view.activity_panel.visible:
		if event is InputEventKey:
			online_view.activity_panel.handle_key(event)
			get_viewport().set_input_as_handled()
		return
	if cooking_controller != null and cooking_controller.panel.visible:
		if event is InputEventKey:
			cooking_controller.panel.handle_key(event)
			get_viewport().set_input_as_handled()
		return
	if crafting_panel != null and crafting_panel.visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			crafting_panel.close()
		# Let native buttons receive clicks while blocking world/keyboard actions.
		if event is InputEventKey:
			get_viewport().set_input_as_handled()
		return
	# Skill testing must remain reachable while the fishing modal owns input.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == SKILL_TEST_KEY:
		toggle_skill_debug_panel()
		get_viewport().set_input_as_handled()
		return
	if fishing_panel != null and fishing_panel.visible:
		if event is InputEventKey:
			if context_menu != null and context_menu.visible:
				if event.pressed and event.keycode == KEY_ESCAPE:
					context_menu.dismiss()
			else:
				fishing_panel.handle_key(event)
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == FISHING_TEST_KEY:
		start_fishing_test()
		get_viewport().set_input_as_handled()
		return
	if context_menu != null and context_menu.visible:
		if event.keycode == KEY_ESCAPE:
			context_menu.dismiss()
		get_viewport().set_input_as_handled()
		return
	if sprite_preview != null and sprite_preview.visible:
		return
	if _ui_is_editing():
		if event.keycode == KEY_ESCAPE:
			get_viewport().gui_release_focus()
			get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_H and not (spawn_menu.visible or item_menu.visible or skill_debug_panel.visible):
		_eat_quick_food()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_I and inventory_menu != null:
		_toggle_character_menu()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and inventory_menu != null and inventory_menu.visible:
		_toggle_character_menu()
		get_viewport().set_input_as_handled()

func _ui_is_editing() -> bool:
	if skill_debug_panel != null and skill_debug_panel.is_editing():
		return true
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit

func _toggle_character_menu() -> void:
	if context_menu != null:
		context_menu.dismiss()
	if interactions != null:
		interactions.cancel_walk()
	spawn_menu.visible = false
	item_menu.visible = false
	inventory_menu.toggle()
	_reset_held_movement()
	spell_cast_requested = false

func _refresh_character_ui() -> void:
	inventory_menu.refresh_view()
	if skill_debug_panel != null:
		skill_debug_panel.refresh()

func reset_skill_training_session() -> void:
	skill_training_session.reset()
	_refresh_character_ui()

func _on_practice_skill_levels_changed() -> void:
	reset_skill_training_session()

func _physics_process(delta: float) -> void:
	if Network.online():
		if interactions.walking:
			interactions.update_walk(delta)
		if spell_cast_requested:
			spell_cast_requested = false
			_cast_selected_spell()
		_update_map_camera()
		_update_food_ui()
		queue_redraw()
		return
	skill_training_session.advance(delta)
	food_notice_time = maxf(0.0, food_notice_time - delta)
	if fishing_notice_time > 0.0:
		fishing_notice_time -= delta
		if fishing_notice_time <= 0.0:
			fishing_notice.text = ""
	if sprite_preview != null and sprite_preview.visible:
		return
	if spell_cast_requested:
		spell_cast_requested = false
		_cast_selected_spell()
	_refresh_player_actor_from_player()
	var moved_manually := _move_player(delta)
	if not moved_manually:
		if interactions.walking:
			interactions.update_walk(delta)
		else:
			_update_auto_chase(delta)
	var realtime_events := combat.process_realtime(world, delta)
	_handle_combat_events(realtime_events)
	_sync_actor_states()
	tick_elapsed += delta
	while tick_elapsed >= TICK_DURATION:
		tick_elapsed -= TICK_DURATION
		_do_tick()
	_update_map_camera()
	_update_food_ui()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if Network.online() and (not Network.authenticated or (online_view != null and online_view.activity_panel.visible)):
		return
	if Network.online() and event is InputEventKey and event.keycode in [KEY_F5, KEY_F6, KEY_F7]:
		get_viewport().set_input_as_handled()
		return
	if cooking_controller != null and cooking_controller.panel.visible:
		return
	if crafting_panel != null and crafting_panel.visible:
		return
	if fishing_panel != null and fishing_panel.visible:
		return
	if _ui_is_editing() and event is InputEventKey:
		if not event.pressed:
			movement_controller.on_key_release(event)
		get_viewport().set_input_as_handled()
		return
	if sprite_preview != null and sprite_preview.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_F7]:
			sprite_preview.hide_preview()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if map_scene_mode and not (spawn_menu.visible or item_menu.visible or inventory_menu.visible):
				var direction := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
				_zoom_map_camera(direction * (event.factor if event.factor > 0.0 else 1.0))
				get_viewport().set_input_as_handled()
			return
	if event is InputEventKey:
		if event.pressed:
			if event.echo:
				return
			if event.keycode == KEY_F7:
				_reset_held_movement()
				spell_cast_requested = false
				sprite_preview.show_preview()
				get_viewport().set_input_as_handled()
				return
			if spawn_menu.visible:
				spawn_menu.on_key_press(event)
				return
			if item_menu.visible:
				item_menu.on_key_press(event)
				return
			if inventory_menu.visible:
				inventory_menu.on_key_press(event)
				return
			match event.keycode:
				KEY_F:
					if not try_nearby_fishing():
						_pick_up_nearest_drop()
					return
				KEY_F5:
					spawn_menu.toggle()
					return
				KEY_F6:
					item_menu.toggle()
					return
				KEY_I:
					inventory_menu.toggle()
					return
				KEY_T:
					_cycle_target()
					return
				KEY_U:
					_clear_target()
					return
				KEY_Q:
					_cycle_spell_selection(-1)
					return
				KEY_R:
					_cycle_spell_selection(1)
					return
				KEY_E:
					spell_cast_requested = true
					return
				KEY_SPACE:
					_start_auto_chase()
					return
			movement_controller.on_key_press(event)
		elif not event.pressed:
			movement_controller.on_key_release(event)
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		if inventory_menu.visible:
			inventory_menu.on_mouse_press(event.position)
		elif not (spawn_menu.visible or item_menu.visible):
			interactions.handle_click(event, get_canvas_transform().affine_inverse() * event.position)

func _draw() -> void:
	_draw_projectiles()
	if health_bar_layer != null:
		health_bar_layer.queue_redraw()

func _create_actor_from_stats(entity_id: String, actor_name: String, x_pos: float, y_pos: float,
		stats: Dictionary, is_monster: bool = false, monster_attack_type: String = "") -> CombatActor:
	var health: Dictionary = stats.get("health", {})
	return CombatActor.new().configure({
		"entity_id": entity_id,
		"name": actor_name,
		"x": x_pos,
		"y": y_pos,
		"hp": int(health.get("current", health.get("max", 1))),
		"max_hp": int(health.get("max", health.get("current", 1))),
		"attack_style": String(stats.get("style", "slash")),
		"damage_roll_level": int(stats.get("damage_roll_level", 0)),
		"magic_level": int(stats.get("magic_level", 1)),
		"magic_accuracy": float(stats.get("magic_accuracy", 0.5)),
		"min_damage": int(stats.get("min_damage", 0)),
		"max_damage": int(stats.get("max_damage", 1)),
		"accuracy": float(stats.get("accuracy", 0.5)),
		"melee_attack_roll": float(stats.get("melee_attack_roll", -1.0)),
		"melee_max_damage": int(stats.get("melee_max_damage", -1)),
		"melee_defence_rolls": stats.get("melee_defence_rolls", {}),
		"defence_level": int(stats.get("defence_level", 1)),
		"crit_chance": float(stats.get("crit_chance", 0.0)),
		"crit_multiplier": float(stats.get("crit_multiplier", 1.5)),
		"resistances": stats.get("resistances", {}),
		"damage_reductions": stats.get("damage_reductions", {}),
		"uses_armour_rating": bool(stats.get("uses_armour_rating", false)),
		"attack_speed": 1,
		"attack_interval_seconds": float(stats.get(
			"attack_interval_seconds", GameTickConfig.TICK_DURATION_SECONDS
		)),
		"attack_range": float(stats.get("attack_range", 2.0)),
		"projectile_speed": float(stats.get("projectile_speed", 0.0)),
		"orb_element": String(stats.get("orb_element", "")),
		"requires_line_of_sight": bool(stats.get("requires_line_of_sight", true)),
		"status_effects": stats.get("status_effects", []),
		"is_monster": is_monster,
		"monster_attack_type": monster_attack_type,
		"hybrid_melee_style": String(stats.get("hybrid_melee_style", "slash")),
		"hybrid_secondary_style": String(stats.get("hybrid_secondary_style", "magic"))
	})

func _active_monster_database() -> Dictionary:
	var database := {}
	for template: Dictionary in GameData.get_active_monster_templates():
		database[int(template.get("id", -1))] = template
	for template: Dictionary in GameData.monsters:
		if not CharacterSpriteLibrary.skin_for_monster(String(template.get("name", ""))).is_empty():
			database[int(template.get("id", -1))] = template
	return database

func _register_monster_for_targeting(monster: MonsterState) -> void:
	if not monster.entity_id.is_empty() and monster.entity_id not in target_list:
		target_list.append(monster.entity_id)

func _unregister_monster_for_targeting(entity_id: String) -> void:
	target_list.erase(entity_id)
	if player.current_target == entity_id:
		_clear_target()

func _update_target_highlight() -> void:
	for monster: MonsterState in world.monsters:
		var sprite: ActorSprite = actor_sprites.get(monster.entity_id)
		if sprite == null:
			continue
		sprite.set_targeted(monster.entity_id == player.current_target)

func _set_target(entity_id: String) -> void:
	if Network.online():
		Network.send_action({"type": "target", "target_id": entity_id})
		player.current_target = entity_id
		_update_target_highlight()
		return
	auto_chase_target = false
	combat.player_auto_attack_enabled = false
	player.current_target = entity_id
	var player_actor: CombatActor = combat.actors.get(player.entity_id)
	if player_actor != null:
		player_actor.current_target_id = entity_id
	_update_target_highlight()

func _clear_target() -> void:
	if Network.online():
		Network.send_action({"type": "target", "target_id": ""})
		player.current_target = ""
		_update_target_highlight()
		return
	auto_chase_target = false
	combat.player_auto_attack_enabled = false
	player.current_target = ""
	var player_actor: CombatActor = combat.actors.get(player.entity_id)
	if player_actor != null:
		player_actor.current_target_id = ""
	_update_target_highlight()

func _cycle_target() -> void:
	if target_list.is_empty():
		return
	target_index = (target_index + 1) % target_list.size()
	_set_target(target_list[target_index])

func spawn_monster_by_id(monster_id: int) -> void:
	if Network.online():
		return
	AetheriaDiagnostics.event("Character", "spawn monster", {"template_id": monster_id})
	var template: Dictionary = _active_monster_database().get(monster_id, {})
	if template.is_empty():
		AetheriaDiagnostics.report("Character", "Unknown active monster template", {"template_id": monster_id})
		print("[Error] No active monster with ID %d" % monster_id)
		return
	var x_pos := 15.0
	var y_pos := 15.0
	if map_scene_mode:
		x_pos += _map_x_offset_tiles()
		y_pos += _map_y_offset_tiles()
	var monster := MonsterState.new(template, x_pos, y_pos)
	monster.entity_id = "monster_%d" % next_monster_number
	next_monster_number += 1
	var sprite := ActorSprite.new().configure(Vector2(TILE_SIZE, TILE_SIZE), MONSTER_COLOR, monster.entity_id)
	sprite.set_skin(CharacterSpriteLibrary.skin_for_monster(monster.name))
	add_child(sprite)
	actor_sprites[monster.entity_id] = sprite
	world.register_monster_actor(monster, _create_actor_from_stats(
		monster.entity_id, monster.name, x_pos, y_pos, monster.get_combat_stats(), true, monster.damage_type
	))
	_update_sprite_position(monster.entity_id)
	_register_monster_for_targeting(monster)
	print("[Spawned] %s (ID %d)" % [monster.name, monster_id])

func _find_monster_by_entity_id(entity_id: String) -> MonsterState:
	for monster: MonsterState in world.monsters:
		if monster.entity_id == entity_id:
			return monster
	return null

func _despawn_monster(entity_id: String) -> void:
	AetheriaDiagnostics.event("Character", "despawn monster", {"entity": entity_id})
	world.remove_monster(entity_id)
	var sprite: ActorSprite = actor_sprites.get(entity_id)
	if sprite != null:
		sprite.set_dead(true)
		sprite.collision_layer = 0
		sprite.collision_mask = 0
		var fade := sprite.create_tween()
		fade.tween_property(sprite, "modulate:a", 0.0, 0.35)
		fade.tween_callback(sprite.queue_free)
	actor_sprites.erase(entity_id)
	visual_positions.erase(entity_id)
	_unregister_monster_for_targeting(entity_id)
	if auto_chase_target and player.current_target.is_empty():
		auto_chase_target = false

func _handle_combat_events(events: Array[Dictionary]) -> void:
	for event: Dictionary in events:
		var event_type := String(event.get("type", ""))
		_show_combat_sprite_event(event)
		if event_type == "skill_experience_gained":
			skill_training_session.record_event(event)
			if bool(event.get("level_up", false)):
				print("[Skills] %s reached level %d." % [
					String(event.get("skill_name", "Skill")), int(event.get("new_level", 1))
				])
			if bool(event.get("combat_level_up", false)):
				print("[Combat] You reached combat level %d." % int(event.get("new_combat_level", 1)))
				inventory_menu.queue_redraw()
			continue
		if event_type.begins_with("spell_"):
			if event_type == "spell_cast_started":
				print("[Spell] Casting %s... (%d mana remaining)" % [
					String(event.get("spell_name", "spell")), int(event.get("mana_remaining", 0))
				])
			elif event_type == "spell_cast_completed":
				print("[Spell] %s resolved." % String(event.get("spell_name", event.get("spell_id", "spell"))))
			elif event_type == "spell_cast_failed":
				if String(event.get("reason", "")) == "cast_fizzled":
					print("[Spell] Your %s cast fizzled." % String(event.get("spell_name", event.get("spell_id", "spell"))))
				else:
					print("[Spell] Cast failed: %s" % String(event.get("reason", "target unavailable")))
			elif event_type == "spell_projectile_spawned":
				print("[Spell] %s hit is on its way." % String(event.get("spell_id", "spell")))
			elif event_type == "spell_area_resolved":
				var targets_value: Variant = event.get("targets", [])
				var target_count: int = targets_value.size() if targets_value is Array else 0
				print("[Spell] %s struck %d target(s)." % [
					String(event.get("spell_id", "spell")), target_count
				])
			elif event_type == "spell_healed":
				print("[Spell] %s restored %d health." % [
					String(event.get("spell_id", "spell")), int(event.get("healing", 0))
				])
			elif event_type == "spell_wall_created":
				print("[Spell] Stoneward raised a temporary projectile barrier.")
			elif event_type == "spell_knockback":
				print("[Spell] Repelling Gust pushed the target back.")
			continue
		if event_type == "projectile_hit" and not String(event.get("spell_id", "")).is_empty():
			print("[Spell] %s dealt %d damage." % [
				String(event.get("spell_id", "spell")), int(event.get("damage", 0))
			])
		if String(event.get("type", "")) != "entity_died":
			continue
		var entity_id := String(event.get("entity_id", ""))
		var actor: CombatActor = combat.actors.get(entity_id)
		if actor != null:
			actor.hp = maxi(0, actor.hp)
		if entity_id == "player":
			continue
		var monster := _find_monster_by_entity_id(entity_id)
		if monster != null:
			var loot := loot_system.roll_monster_loot(monster)
			var gold_amount := int(loot.get("gold", 0))
			player.gold += gold_amount
			var drop_messages: Array[String] = []
			var item_drops: Array = loot.get("items", [])
			if item_drops.is_empty():
				var legacy_item: Variant = loot.get("item", null)
				if legacy_item is Dictionary and not legacy_item.is_empty():
					item_drops.append({"item": legacy_item, "quantity": loot.get("quantity", 1)})
			for drop: Variant in item_drops:
				if not drop is Dictionary:
					continue
				var item_value: Variant = drop.get("item", null)
				if not item_value is Dictionary or item_value.is_empty():
					continue
				var quantity := maxi(1, int(drop.get("quantity", 1)))
				var item_name := String(item_value.get("name", ""))
				var drop_position := _screen_position(monster.x, monster.y)
				var monster_sprite: ActorSprite = actor_sprites.get(entity_id)
				if monster_sprite != null:
					drop_position = monster_sprite.position
				var angle := float(drop_messages.size()) * 2.4
				var scatter := Vector2.from_angle(angle) * minf(18.0, float(drop_messages.size()) * 9.0)
				if not _spawn_ground_drop(item_name, quantity, drop_position + scatter):
					player.add_item(item_name, quantity)
				var quantity_label := "%dx " % quantity if quantity > 1 else ""
				drop_messages.append(quantity_label + item_name)
			if drop_messages.is_empty():
				print("[Loot] %s dropped %d gold." % [monster.name, gold_amount])
			else:
				print("[Loot] %s dropped %d gold and %s." % [monster.name, gold_amount, ", ".join(drop_messages)])
		_despawn_monster(entity_id)

func _spawn_ground_drop(item_name: String, quantity: int, at: Vector2) -> bool:
	AetheriaDiagnostics.event("Inventory", "spawn ground item", {"item": item_name, "quantity": quantity, "position": at})
	if quantity <= 0 or GameData.get_item_by_name(item_name).is_empty():
		return false
	var drop := GroundItemDrop.new().configure(item_name, quantity)
	drop.position = at
	add_child(drop)
	ground_drops.append(drop)
	return true

func _collect_ground_drop(drop: GroundItemDrop) -> bool:
	if Network.online():
		var sprite: Node2D = actor_sprites.get(player.entity_id)
		return is_instance_valid(drop) and sprite != null and sprite.global_position.distance_to(drop.global_position) <= TILE_SIZE * 2.0 and Network.send_action({"type": "pickup", "drop_id": str(drop.get_meta("online_drop_id", ""))})
	if not is_instance_valid(drop) or drop.collected or drop not in ground_drops:
		return false
	AetheriaDiagnostics.event("Inventory", "collect ground item", {"item": drop.item_name, "quantity": drop.quantity})
	var player_sprite: ActorSprite = actor_sprites.get(player.entity_id)
	if player_sprite == null or player_sprite.global_position.distance_to(drop.global_position) > TILE_SIZE * 2.0:
		return false
	if not drop.take(player):
		return false
	ground_drops.erase(drop)
	inventory_menu.refresh_view()
	print("[Loot] Picked up %dx %s." % [drop.quantity, drop.item_name])
	return true

func drop_inventory_item(item_name: String, quantity: int = 1) -> bool:
	if Network.online():
		return Network.send_action({"type": "drop", "item_name": item_name, "quantity": quantity})
	AetheriaDiagnostics.event("Inventory", "drop backpack item", {"item": item_name, "quantity": quantity})
	# Backpack ownership is the sole source; worn slots cannot be dropped.
	var sprite: ActorSprite = actor_sprites.get(player.entity_id)
	if sprite == null or quantity <= 0 or int(player.backpack.get(item_name, 0)) < quantity:
		return false
	if not _spawn_ground_drop(item_name, quantity, sprite.position):
		return false
	if not player.remove_item(item_name, quantity):
		var failed_drop: GroundItemDrop = ground_drops.pop_back()
		failed_drop.queue_free()
		return false
	inventory_menu.refresh_view()
	print("[Loot] Dropped %dx %s." % [quantity, item_name])
	return true

func drop_fishing_pale_item(slot: int, expected_name: String = "") -> bool:
	if Network.online():
		return Network.send_action({"type": "pale_drop", "slot": slot})
	if slot < 0 or slot >= player.fishing_pale.size():
		return false
	var fish_name := player.fishing_pale[slot]
	if fish_name.is_empty() or (not expected_name.is_empty() and fish_name != expected_name):
		return false
	var sprite: ActorSprite = actor_sprites.get(player.entity_id)
	if sprite == null or not _spawn_ground_drop(fish_name, 1, sprite.position):
		return false
	if not player.remove_fishing_catch(slot, fish_name):
		var failed_drop: GroundItemDrop = ground_drops.pop_back()
		failed_drop.queue_free()
		return false
	inventory_menu.refresh_view()
	return true

func _pick_up_nearest_drop() -> void:
	var player_sprite: ActorSprite = actor_sprites.get(player.entity_id)
	if player_sprite == null:
		return
	var nearest: GroundItemDrop
	var best_distance := float(TILE_SIZE * 2)
	for drop: GroundItemDrop in ground_drops:
		if not is_instance_valid(drop) or drop.collected:
			continue
		var distance := player_sprite.global_position.distance_to(drop.global_position)
		if distance <= best_distance:
			best_distance = distance
			nearest = drop
	if nearest != null:
		_collect_ground_drop(nearest)

func _cycle_spell_selection(direction: int) -> void:
	if Network.online():
		var spells := player.get_known_spells()
		if not spells.is_empty():
			var index := -1
			for i in spells.size():
				if spells[i].id == player.selected_spell_id:
					index = i
			Network.send_action({"type": "select_spell", "spell_id": spells[posmod(index + direction, spells.size())].id})
		return
	var spell := player.cycle_known_spell(direction)
	if spell.is_empty():
		print("[Spellbook] No spells are unlocked.")
		return
	var required_magic_level := int(spell.get("unlock_level", SkillProgression.MIN_LEVEL))
	var failure_chance := SkillProgression.magic_cast_failure_chance(player.get_magic_level(), required_magic_level)
	print("[Spellbook] Selected %s (Magic %d; unlocks at %d; cast failure %d%%)." % [
		String(spell.get("name", "spell")), player.get_magic_level(), required_magic_level,
		roundi(failure_chance * 100.0)
	])

func _cast_selected_spell() -> void:
	if Network.online():
		Network.send_action({"type": "cast", "spell_id": player.selected_spell_id, "target_id": player.current_target})
		return
	if player.selected_spell_id.is_empty():
		_cycle_spell_selection(1)
		return
	var result := combat.cast_spell(world, player.entity_id, player.selected_spell_id)
	if not bool(result.get("ok", false)):
		print("[Spell] %s" % String(result.get("error", "Spell could not be cast.")))
		return
	var events_value: Variant = result.get("events", [])
	if events_value is Array:
		var cast_events: Array[Dictionary] = []
		for event: Variant in events_value:
			if event is Dictionary:
				cast_events.append(event)
		_handle_combat_events(cast_events)

func _do_tick() -> void:
	var events := world.tick()
	_handle_combat_events(events)
	_sync_actor_states()
	_update_target_highlight()
	queue_redraw()

func _sync_actor_states() -> void:
	for actor: CombatActor in combat.actors.values():
		if not actor.is_monster:
			player.x = actor.x
			player.y = actor.y
			player.current_hp = actor.hp
		else:
			var monster := _find_monster_by_entity_id(actor.entity_id)
			if monster != null:
				monster.current_hp = actor.hp
				monster.is_alive = actor.hp > 0
		_update_sprite_position(actor.entity_id)

func _move_player(delta: float) -> bool:
	if cooking_controller != null and cooking_controller.panel.visible:
		return false
	if fishing_panel != null and fishing_panel.visible:
		return false
	if spawn_menu.visible or item_menu.visible or inventory_menu.visible or _ui_is_editing() or context_menu.visible:
		return false
	var player_actor: CombatActor = combat.actors.get(player.entity_id)
	if player_actor == null or not player_actor.is_alive:
		return false
	var direction := movement_controller.get_move_vector()
	if direction.is_zero_approx():
		return false
	# Simulation Y points upward on the map; the original grid uses screen Y.
	if not map_scene_mode:
		direction.y *= -1.0
	var sprite: ActorSprite = actor_sprites.get(player.entity_id)
	if sprite != null:
		sprite.face_direction(Vector2(direction.x, -direction.y if map_scene_mode else direction.y))
	auto_chase_target = false
	combat.player_auto_attack_enabled = false
	interactions.cancel_walk()
	world.move_actor_continuous(
		player.entity_id, direction * PLAYER_MOVE_SPEED_TILES_PER_SECOND * delta
	)
	_update_sprite_position(player.entity_id)
	return true

func _move_actor_with_map_collision(entity_id: String, displacement: Vector2) -> Vector2:
	var actor_body: ActorSprite = actor_sprites.get(entity_id)
	if actor_body == null:
		return displacement
	var start_position := actor_body.position
	var remaining_motion := Vector2(displacement.x * TILE_SIZE, -displacement.y * TILE_SIZE)
	for _attempt in range(4):
		if remaining_motion.is_zero_approx():
			break
		var collision := actor_body.move_and_collide(remaining_motion)
		if collision == null:
			break
		remaining_motion = collision.get_remainder().slide(collision.get_normal())
	var actual_motion := actor_body.position - start_position
	return Vector2(actual_motion.x / TILE_SIZE, -actual_motion.y / TILE_SIZE)

func _query_map_terrain_collision(start: Vector2, finish: Vector2) -> Dictionary:
	var from_position := _screen_position(start.x, start.y)
	var to_position := _screen_position(finish.x, finish.y)
	var query := PhysicsRayQueryParameters2D.create(from_position, to_position, 1)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var hit_position: Vector2 = hit.get("position", to_position)
	var hit_world_position := Vector2(
		(hit_position.x - map_origin.x) / TILE_SIZE,
		(map_origin.y + map_height - hit_position.y) / TILE_SIZE
	)
	var segment_length := start.distance_to(finish)
	var fraction := start.distance_to(hit_world_position) / segment_length if segment_length > 0.0 else 0.0
	var collider := hit.get("collider") as Node
	return {
		"type": "terrain",
		"actor": null,
		"entity_id": String(collider.name) if collider != null else "map_geometry",
		"point": hit_world_position,
		"fraction": fraction
	}

func _start_auto_chase() -> void:
	if Network.online():
		Network.send_action({"type": "attack", "target_id": player.current_target})
		return
	var actor: CombatActor = combat.actors.get("player")
	if actor == null or not actor.is_alive:
		return
	var target_actor: CombatActor = combat.actors.get(player.current_target) if not player.current_target.is_empty() else null
	if target_actor == null or not target_actor.is_alive or not target_actor.is_monster:
		return
	if String(player.get_combat_stats().get("style", "blunt")) == "magic":
		print("[Combat] Use E to cast the selected spell.")
		return
	interactions.cancel_walk()
	combat.player_auto_attack_enabled = true
	auto_chase_target = true

func _update_auto_chase(delta: float) -> void:
	if not auto_chase_target or spawn_menu.visible or item_menu.visible or inventory_menu.visible or _ui_is_editing() or context_menu.visible:
		return
	var actor: CombatActor = combat.actors.get("player")
	var target_actor: CombatActor = combat.actors.get(player.current_target) if not player.current_target.is_empty() else null
	if actor == null or not actor.is_alive or target_actor == null or not target_actor.is_alive:
		return
	var offset := Vector2(target_actor.x - actor.x, target_actor.y - actor.y)
	var distance := offset.length()
	var stop_distance := maxf(0.0, actor.attack_range - 0.05)
	if distance <= stop_distance:
		return
	var travel_distance := minf(
		PLAYER_MOVE_SPEED_TILES_PER_SECOND * delta,
		maxf(0.0, distance - stop_distance)
	)
	world.move_actor_continuous(actor.entity_id, offset.normalized() * travel_distance)
	_update_sprite_position(actor.entity_id)

func _refresh_player_actor_from_player() -> void:
	var actor: CombatActor = combat.actors.get(player.entity_id)
	if actor == null:
		return
	var player_sprite: ActorSprite = actor_sprites.get(player.entity_id)
	if player_sprite != null:
		player_sprite.set_skin(CharacterSpriteLibrary.default_player_skin())
		player_sprite.set_equipment(player.equipment)
		player_sprite.set_dead(player.current_hp <= 0)
	var stats := player.get_combat_stats()
	actor.attack_style = String(stats.get("style", "slash"))
	if actor.attack_style == "magic":
		combat.player_auto_attack_enabled = false
		auto_chase_target = false
	actor.damage_roll_level = int(stats.get("damage_roll_level", 0))
	actor.magic_level = int(stats.get("magic_level", 1))
	actor.magic_accuracy = float(stats.get("magic_accuracy", 0.5))
	actor.min_damage = int(stats.get("min_damage", 0))
	actor.max_damage = int(stats.get("max_damage", 1))
	actor.accuracy = float(stats.get("accuracy", 0.5))
	actor.melee_attack_roll = float(stats.get("melee_attack_roll", -1.0))
	actor.melee_defence_rolls = stats.get("melee_defence_rolls", {}).duplicate(true)
	actor.defence_level = int(stats.get("defence_level", 1))
	actor.crit_chance = float(stats.get("crit_chance", 0.0))
	actor.crit_multiplier = float(stats.get("crit_multiplier", 1.5))
	actor.resistances = stats.get("resistances", {})
	actor.uses_armour_rating = bool(stats.get("uses_armour_rating", false))
	actor.attack_speed = 1
	actor.attack_interval_seconds = float(stats.get(
		"attack_interval_seconds", GameTickConfig.TICK_DURATION_SECONDS
	))
	actor.attack_range = float(stats.get("attack_range", 2.0))
	actor.projectile_speed = float(stats.get("projectile_speed", 0.0))
	actor.orb_element = String(stats.get("orb_element", ""))
	actor.requires_line_of_sight = bool(stats.get("requires_line_of_sight", true))
	actor.hp = player.current_hp
	actor.max_hp = player.get_max_hp()
	actor.is_alive = actor.hp > 0
	if actor.is_alive:
		actor.death_reported = false

func _update_sprite_position(entity_id: String) -> void:
	var actor: CombatActor = combat.actors.get(entity_id) if combat != null else null
	var sprite: ActorSprite = actor_sprites.get(entity_id)
	if actor == null or sprite == null:
		if entity_id == player.entity_id:
			sprite = actor_sprites.get(entity_id)
			if sprite != null:
				sprite.position = _screen_position(player.x, player.y)
				visual_positions[entity_id] = sprite.position
		return
	var next_position := _screen_position(actor.x, actor.y)
	var previous_position: Vector2 = visual_positions.get(entity_id, next_position)
	sprite.position = next_position
	sprite.update_visual_motion(next_position - previous_position)
	visual_positions[entity_id] = next_position
	sprite.set_dead(not actor.is_alive)
	# Actor and map objects share Z; their feet establish overlap through Y sort.
	sprite.z_index = 0

func _map_x_offset_tiles() -> float:
	return -map_origin.x / TILE_SIZE

func _map_y_offset_tiles() -> float:
	return (map_origin.y + map_height - ORIGINAL_MAP_HEIGHT) / TILE_SIZE

func _screen_position(world_x: float, world_y: float) -> Vector2:
	if map_scene_mode:
		return Vector2(map_origin.x + world_x * TILE_SIZE, map_origin.y + map_height - world_y * TILE_SIZE)
	return Vector2(world_x * TILE_SIZE, world_y * TILE_SIZE)

func _update_map_camera() -> void:
	if not map_scene_mode:
		return
	var map_camera := get_node_or_null("../MapCamera") as Camera2D
	if map_camera == null:
		return
	# Follow the rendered actor, including at map edges and after collision resolution.
	var player_sprite: ActorSprite = actor_sprites.get(player.entity_id)
	map_camera.global_position = player_sprite.global_position if player_sprite != null else to_global(_screen_position(player.x, player.y))

func _zoom_map_camera(wheel_steps: float) -> void:
	var map_camera := get_node_or_null("../MapCamera") as Camera2D
	if map_camera == null:
		return
	var next_zoom := clampf(map_camera.zoom.x * pow(CAMERA_ZOOM_STEP, wheel_steps), CAMERA_MIN_ZOOM, CAMERA_MAX_ZOOM)
	map_camera.zoom = Vector2.ONE * next_zoom
	_update_map_camera()

func _draw_health_bars() -> void:
	for actor: CombatActor in combat.actors.values():
		var sprite: ActorSprite = actor_sprites.get(actor.entity_id)
		if sprite == null:
			continue
		var ratio := clampf(float(actor.hp) / float(actor.max_hp), 0.0, 1.0) if actor.max_hp > 0 else 0.0
		var bar_left := sprite.position.x - TILE_SIZE * 0.5
		var bar_top := sprite.position.y + sprite.get_health_bar_offset().y
		health_bar_layer.draw_rect(Rect2(bar_left, bar_top, TILE_SIZE, 5), Color.RED)
		health_bar_layer.draw_rect(Rect2(bar_left, bar_top, TILE_SIZE * ratio, 5), Color.GREEN)

func _draw_projectiles() -> void:
	for projectile: CombatProjectile in combat.projectiles.values():
		var point := _screen_position(projectile.x, projectile.y)
		draw_string(ThemeDB.fallback_font, point, "➤", HORIZONTAL_ALIGNMENT_CENTER, -1, 22, PROJECTILE_COLOR)

func _reset_held_movement() -> void:
	if movement_controller == null:
		return
	for direction: String in movement_controller.holding:
		movement_controller.holding[direction] = false

func _show_combat_sprite_event(event: Dictionary) -> void:
	var event_type := String(event.get("type", ""))
	if event_type in ["entity_hit", "projectile_spawned", "spell_cast_started"]:
		var attacker_id := String(event.get("attacker_id", event.get("caster_id", "")))
		var attacker: ActorSprite = actor_sprites.get(attacker_id)
		var target_id := String(event.get("target_id", ""))
		var target: CombatActor = combat.actors.get(target_id)
		var source: CombatActor = combat.actors.get(attacker_id)
		if attacker != null:
			var direction := Vector2.ZERO
			if target != null and source != null:
				direction = _screen_position(target.x, target.y) - _screen_position(source.x, source.y)
			attacker.play_attack(direction)
	if event_type in ["entity_hit", "projectile_hit", "spell_area_hit"] and int(event.get("damage", 0)) > 0:
		var victim: ActorSprite = actor_sprites.get(String(event.get("target_id", "")))
		if victim != null:
			victim.play_hurt()
