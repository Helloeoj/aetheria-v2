extends SceneTree
## Integration checks use the real map, journal controls, input dispatch and combat adapter.
const OUT := "C:/Users/Riptide/Documents/ChatGPT/Aetheria/work/ui-preview"
var checks := 0
var failures: Array[String] = []
var game: Node

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("[Interaction FAIL] ", label)

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event)
	var release := InputEventKey.new()
	release.keycode = code
	root.push_input(release)

func _click(screen_point: Vector2, button: MouseButton) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen_point
	motion.global_position = screen_point
	root.push_input(motion)
	var event := InputEventMouseButton.new()
	event.position = screen_point
	event.global_position = screen_point
	event.button_index = button
	event.pressed = true
	root.push_input(event)
	var release := InputEventMouseButton.new()
	release.position = screen_point
	release.global_position = screen_point
	release.button_index = button
	root.push_input(release)

func _screen(point: Vector2) -> Vector2:
	return game.get_global_transform_with_canvas() * point

func _find_button(text: String, parent: Node) -> Button:
	for widget: Node in parent.find_children("*", "Button", true, false):
		if widget.text == text or widget.tooltip_text == text:
			return widget
		# Item-card tooltips now also contain requirements; identify their exact
		# visible name without depending on the tooltip's full presentation.
		for label: Node in widget.find_children("*", "Label", true, false):
			if label.text == text:
				return widget
	return null

func _capture(file: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args():
		return
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OUT + "/" + file)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene := (load("res://scenes/EastOutskirtsLayered.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	game = scene.get_node("Combat")
	game.set_physics_process(false)
	game.skill_debug_panel.hide()
	game.player.backpack.clear()
	var controller: Node = game.interactions
	var menu: Control = game.context_menu
	var data := root.get_node("GameData")
	game.spawn_monster_by_id(int(game._active_monster_database().keys()[0]))
	var monster: MonsterState = game.world.monsters.back()
	var actor: CombatActor = game.combat.actors[monster.entity_id]
	actor.x = game.player.x + 1.0
	actor.y = game.player.y
	game._update_sprite_position(actor.entity_id)
	var sprite: ActorSprite = game.actor_sprites[actor.entity_id]
	game._clear_target()
	_key(KEY_SPACE)
	check(game.player.current_target.is_empty() and not game.auto_chase_target, "Space without selection does not find a nearby enemy")
	_click(_screen(sprite.position + Vector2(0, -12)), MOUSE_BUTTON_LEFT)
	check(game.player.current_target == actor.entity_id, "Left-click selects the clicked monster through camera projection")
	check(sprite.targeted and not game.combat.player_auto_attack_enabled and not game.auto_chase_target, "Selection highlights without attacking or chasing")
	var events: Array[Dictionary] = game.combat.process_realtime(game.world, 0.1)
	check(not events.any(func(e: Dictionary) -> bool: return e.get("attacker_id", "") == "player"), "Selecting an in-range enemy produces no automatic attack")
	var camera := scene.get_node("MapCamera") as Camera2D
	for zoom: float in [0.5, 4.0, 1.0]:
		camera.zoom = Vector2.ONE * zoom
		camera.force_update_scroll()
		game._clear_target()
		_click(_screen(sprite.position + Vector2(0, -12)), MOUSE_BUTTON_LEFT)
		check(game.player.current_target == actor.entity_id, "Monster selection follows camera zoom %.1f" % zoom)
	game.skill_debug_panel.show()
	game.skill_debug_panel.skill_editors.attack.get_line_edit().grab_focus()
	check(game._ui_is_editing(), "Practice editor has keyboard focus before world click")
	_click(_screen(sprite.position + Vector2(0, -12)), MOUSE_BUTTON_LEFT)
	check(not game._ui_is_editing(), "Selecting a world target releases practice-editor focus")
	game.skill_debug_panel.hide()
	_key(KEY_SPACE)
	check(game.auto_chase_target and game.combat.player_auto_attack_enabled, "Space initiates attack against selection")
	game._clear_target()
	_click(_screen(sprite.position + Vector2(0, -12)), MOUSE_BUTTON_RIGHT)
	await process_frame
	check(menu.visible, "Right-click monster opens context menu")
	check(menu.actions.any(func(e: Dictionary) -> bool: return String(e.label).begins_with("Attack ")), "Monster menu contains Attack")
	check(menu.actions.any(func(e: Dictionary) -> bool: return e.label == "Walk here"), "Monster menu contains Walk here")
	await _capture("7-monster-context.png")
	var attack_button: Button = _find_button("Attack " + actor.name, menu)
	check(attack_button != null, "Attack option is a real button")
	if attack_button != null:
		_click(attack_button.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	check(not menu.visible and game.auto_chase_target, "Clicking Attack dismisses menu and starts combat")
	controller.select_monster(actor.entity_id)
	check(not game.combat.player_auto_attack_enabled, "Reselecting an enemy cancels attack intent")
	_key(KEY_E)
	check(game.spell_cast_requested and not game.combat.player_auto_attack_enabled, "E requests a spell without starting weapon auto-attacks")
	game.spell_cast_requested = false
	game.player.add_item("Bronze Dagger", 3)
	check(game.drop_inventory_item("Bronze Dagger", 1), "Drop removes a backpack item into the world")
	check(int(game.player.backpack.get("Bronze Dagger", 0)) == 2 and game.ground_drops.size() == 1, "Drop transfers exactly one item")
	var drop: GroundItemDrop = game.ground_drops.back()
	check(drop.quantity == 1 and drop.sprite.texture != null, "Drop preserves quantity and has a visible ground icon")
	check(not game.drop_inventory_item("Bronze Dagger", 99) and not game.drop_inventory_item("Bronze Dagger", 0), "Invalid drop quantities do not mutate state")
	game.player.equip_item("Bronze Dagger")
	game.player.backpack.erase("Bronze Dagger")
	check(not game.drop_inventory_item("Bronze Dagger"), "Worn-only equipment cannot be dropped")
	check(not game.player.equipment.weapon.is_empty(), "Rejected drop leaves worn equipment intact")
	# Move the drop away from the monster so the pointer can select it independently.
	drop.position += Vector2(-16, 14)
	_click(_screen(drop.position), MOUSE_BUTTON_LEFT)
	check(controller.selected_drop == drop and drop.selected, "Left-click selects a ground item")
	check(not drop.collected and not game.player.backpack.has("Bronze Dagger"), "Selecting ground loot does not collect it")
	_click(_screen(drop.position), MOUSE_BUTTON_RIGHT)
	await process_frame
	check(menu.actions.any(func(e: Dictionary) -> bool: return String(e.label).begins_with("Pick up ")), "Ground item menu contains Pick up")
	check(menu.actions.any(func(e: Dictionary) -> bool: return e.label == "Walk here"), "Ground item menu contains Walk here")
	await _capture("8-ground-context.png")
	var pickup: Button = _find_button("Pick up Bronze Dagger", menu)
	if pickup != null:
		_click(pickup.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	for frame in range(120):
		if not controller.walking:
			break
		controller.update_walk(1.0 / 60.0)
	check(drop.collected and int(game.player.backpack.get("Bronze Dagger", 0)) == 1, "Pick up transfers item back into backpack")
	check(not game._collect_ground_drop(drop), "Collected drop cannot be picked up twice")
	await process_frame
	# An item without dedicated art must still be droppable and collectible.
	var fallback_name := ""
	for item: Dictionary in data.items_by_id.values():
		if not ItemVisualLibrary.has_ground_visual(String(item.name)):
			fallback_name = String(item.name)
			break
	check(not fallback_name.is_empty(), "Catalog includes a fallback-art item")
	if not fallback_name.is_empty():
		game.player.add_item(fallback_name, 5)
		check(game.drop_inventory_item(fallback_name, 5), "Whole stack without dedicated ground art can be dropped")
		var fallback: GroundItemDrop = game.ground_drops.back()
		check(fallback.sprite.texture != null and fallback.quantity == 5, "Fallback ground icon and stack count exist")
		check(game._collect_ground_drop(fallback) and int(game.player.backpack.get(fallback_name, 0)) == 5, "Fallback stack roundtrip preserves all five items")
	await process_frame
	# Distant pickup uses the same collision-constrained movement as WASD.
	game.player.add_item("Bronze Dagger", 2)
	game.drop_inventory_item("Bronze Dagger", 1)
	var distant: GroundItemDrop = game.ground_drops.back()
	distant.position = game.actor_sprites.player.position + Vector2(115, 0)
	check(not game._collect_ground_drop(distant), "Direct collection respects pickup range")
	controller.request_pickup(distant)
	check(controller.walking and controller.pending_pickup == distant, "Distant Pick up queues walking")
	# Isolate intent/movement from map scenery for deterministic arrival.
	var collision_handler: Callable = game.world.collision_move_handler
	game.world.collision_move_handler = Callable()
	for frame in range(180):
		controller.update_walk(1.0 / 60.0)
		if not controller.walking:
			break
	check(distant.collected and not controller.walking, "Queued pickup walks into range and collects exactly once")
	game.world.collision_move_handler = collision_handler
	await process_frame
	controller.walk_here(game.actor_sprites.player.global_position + Vector2(50, 0))
	check(controller.walking and not game.auto_chase_target and not game.combat.player_auto_attack_enabled, "Walk here cancels attack intent")
	game.movement_controller.on_input("w", true)
	game._move_player(0.01)
	check(not controller.walking, "Manual movement cancels queued walking")
	game._reset_held_movement()
	# Inventory/equipment context menus go through actual GUI hit-testing.
	game.inventory_menu.toggle()
	game.inventory_menu.select_page(0)
	await process_frame
	await process_frame
	var item_button := _find_button("Bronze Dagger", game.inventory_menu)
	check(item_button != null, "Inventory renders test item")
	if item_button != null:
		_click(item_button.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	await process_frame
	check(menu.visible and menu.actions[0].label == "Equip" and menu.actions[1].label == "Drop", "Inventory right-click exposes Equip and Drop")
	check(menu.panel.position.distance_to(menu._anchor) < 1 and menu.panel.position.y > 250, "Inventory context menu opens at the clicked card")
	await _capture("9-inventory-context.png")
	var before := int(game.player.backpack.get("Bronze Dagger", 0))
	var drop_button := _find_button("Drop", menu)
	if drop_button != null:
		_click(drop_button.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	check(int(game.player.backpack.get("Bronze Dagger", 0)) == before - 1, "Inventory Drop action transfers one item")
	await process_frame
	await process_frame
	item_button = _find_button("Bronze Dagger", game.inventory_menu)
	if item_button != null:
		_click(item_button.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	await process_frame
	var drop_all := _find_button("Drop all (%d)" % (before - 1), menu)
	check(drop_all != null, "Stacks offer a separate Drop all action")
	if drop_all != null:
		_click(drop_all.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	check(not game.player.backpack.has("Bronze Dagger") and game.ground_drops.back().quantity == before - 1, "Drop all preserves the complete stack quantity")
	check(not game.player.equipment.weapon.is_empty(), "Dropping backpack copies does not drop the worn copy")
	game.inventory_menu.select_page(3)
	await process_frame
	await process_frame
	var equipped_button: Button
	for widget: Node in game.inventory_menu.body.find_children("*", "Button", true, false):
		if widget.find_children("*", "Label", true, false).any(func(n: Node) -> bool: return n.text == "Bronze Dagger"):
			equipped_button = widget
	check(equipped_button != null, "Equipment page renders worn weapon")
	if equipped_button != null:
		_click(equipped_button.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	check(not game.player.equipment.weapon.is_empty() and game.inventory_menu.selected_equipment_slot == "weapon", "Equipment left-click selects without unequipping")
	await process_frame
	await process_frame
	equipped_button = null
	for widget: Node in game.inventory_menu.body.find_children("*", "Button", true, false):
		if widget.find_children("*", "Label", true, false).any(func(n: Node) -> bool: return n.text == "Bronze Dagger"):
			equipped_button = widget
	if equipped_button != null:
		_click(equipped_button.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	await process_frame
	check(menu.visible and menu.actions.size() == 1 and menu.actions[0].label == "Unequip", "Worn gear menu offers Unequip and no Drop")
	await _capture("10-equipment-context.png")
	before = int(game.player.backpack.get("Bronze Dagger", 0))
	var unequip := _find_button("Unequip", menu)
	if unequip != null:
		_click(unequip.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	check(game.player.equipment.weapon.is_empty() and int(game.player.backpack.get("Bronze Dagger", 0)) == before + 1, "Unequip returns worn weapon to inventory")
	var entries: Array[Dictionary] = [{"label": "Test", "action": Callable()}]
	menu.show_options("Choose option", entries, Vector2(1279, 719))
	await process_frame
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(menu.panel.get_global_rect()), "Context menu stays inside viewport at bottom-right")
	_key(KEY_ESCAPE)
	check(not menu.visible and game.inventory_menu.visible, "Escape dismisses context menu before closing journal")
	menu.show_options("Choose option", entries, Vector2(500, 300))
	_click(Vector2(10, 700), MOUSE_BUTTON_LEFT)
	check(not menu.visible and game.inventory_menu.visible, "Click outside dismisses menu without clicking through")
	game.inventory_menu.toggle()
	# Exercise actual ranged and melee output, while isolating world terrain.
	game.world.terrain_collision_handler = Callable()
	actor.x = game.player.x + 1
	actor.y = game.player.y
	actor.hp = 1000
	actor.max_hp = 1000
	game.player.give_and_equip("Bronze Bow")
	game._refresh_player_actor_from_player()
	controller.select_monster(actor.entity_id)
	_key(KEY_SPACE)
	var player_actor: CombatActor = game.combat.actors.player
	player_actor.attack_cooldown_seconds = 0
	events = game.combat.process_realtime(game.world, 0.01)
	check(events.any(func(e: Dictionary) -> bool: return e.get("type") == "projectile_spawned" and e.get("attacker_id") == "player" and e.get("damage_type") == "ranged"), "Space with a bow launches a ranged attack at selection")
	game.combat.projectiles.clear()
	game.player.give_and_equip("Bronze Shortsword")
	game._refresh_player_actor_from_player()
	controller.select_monster(actor.entity_id)
	_key(KEY_SPACE)
	player_actor.attack_cooldown_seconds = 0
	events = game.combat.process_realtime(game.world, 0.01)
	check(events.any(func(e: Dictionary) -> bool: return e.get("type") == "entity_hit" and e.get("attacker_id") == "player"), "Space with a sword initiates melee")
	for item: Dictionary in data.items_by_id.values():
		if item.get("slot") == "weapon" and int(item.get("attack_bonuses", {}).get("magic", 0)) > 0:
			game.player.give_and_equip(String(item.name))
			break
	game._refresh_player_actor_from_player()
	controller.select_monster(actor.entity_id)
	_key(KEY_SPACE)
	check(not game.combat.player_auto_attack_enabled and not game.auto_chase_target, "Magic weapon does not launch automatic spells from Space")
	game.player.set_skill_level("magic", 100)
	game.player.current_mana = game.player.get_max_mana()
	game._refresh_player_actor_from_player()
	_key(KEY_E)
	if game.spell_cast_requested:
		game.spell_cast_requested = false
		game._cast_selected_spell()
	check(game.combat.active_spell_casts.has("player"), "E starts a real selected-spell cast")
	check(not game.combat.player_auto_attack_enabled, "Spell cast keeps automatic weapon attacks disabled")
	# A stale context action must remain safe after another pickup frees its node.
	game.player.add_item("Bronze Dagger", 1)
	game.drop_inventory_item("Bronze Dagger")
	var stale: GroundItemDrop = game.ground_drops.back()
	var stale_id := stale.get_instance_id()
	game._collect_ground_drop(stale)
	await process_frame
	controller._pickup_instance(stale_id)
	check(not controller.walking, "Stale pickup menu does not restart movement or duplicate loot")
	print("[Interaction] %d checks, %d failures" % [checks, failures.size()])
	var report := FileAccess.open(OUT + "/interaction-validation.txt", FileAccess.WRITE)
	report.store_string("%d checks, %d failures\n%s\n" % [checks, failures.size(), "\n".join(failures)])
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
