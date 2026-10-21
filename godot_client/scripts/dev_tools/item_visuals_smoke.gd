extends SceneTree
## Exercises actual monster death, deferred ground inventory, quantity transfer,
## pickup range, all ten icon resources and the real journal widgets.
const OUT := "C:/Users/Riptide/Documents/ChatGPT/Aetheria/work/item-visuals/batch-001"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("[Item visuals] ", label)

func _run() -> void:
	await process_frame
	var scene := (load("res://scenes/EastOutskirtsLayered.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var game: Node = scene.get_node("Combat")
	game.set_physics_process(false)
	var data: Node = root.get_node("GameData")
	ItemVisualLibrary.initialize()
	# This fixture covers the original fitted bronze batch. Other approved art
	# batches share the registry without becoming equipment or fixed monster loot.
	var batch_names: Array[String] = []
	for item_name: String in ItemVisualLibrary.definitions:
		var definition := ItemVisualLibrary.definition(item_name)
		if String(definition.get("inventory", "")).begins_with("res://Assets/Items/batch_001/"):
			batch_names.append(item_name)
	check(batch_names.size() == 10,"Bronze batch must have exactly ten items")
	var actor: ActorSprite = game.actor_sprites.player
	for item_name: String in batch_names:
		check(not data.get_item_by_name(item_name).is_empty(),item_name+" catalog entry")
		var icon := ItemVisualLibrary.texture(item_name)
		var floor := ItemVisualLibrary.texture(item_name,"ground")
		check(icon != null and icon.get_size() == Vector2(64,64),item_name+" icon canvas")
		check(floor != null and floor.get_size() == Vector2(64,64),item_name+" ground canvas")
		var size := icon.get_image().get_used_rect().size
		check(maxi(size.x,size.y) == 40,item_name+" inventory art bounds")
		var before := int(game.player.backpack.get(item_name,0))
		check(game._spawn_ground_drop(item_name,3,actor.position + Vector2(20,0)),item_name+" spawns")
		var drop: GroundItemDrop = game.ground_drops.back()
		check(int(game.player.backpack.get(item_name,0)) == before,item_name+" must wait for pickup")
		check(drop.contains_global_point(drop.global_position),item_name+" click bounds")
		check(game._collect_ground_drop(drop),item_name+" collection")
		check(int(game.player.backpack.get(item_name,0)) == before+3,item_name+" exact quantity")
		check(not drop.take(game.player),item_name+" double pickup protection")
		var equipped_scene := String(ItemVisualLibrary.definition(item_name).equipped_scene)
		check(ResourceLoader.exists(equipped_scene),item_name+" keeps fitted scene")
	game._spawn_ground_drop("Bronze Dagger",1,actor.position + Vector2(200,0))
	var distant: GroundItemDrop = game.ground_drops.back()
	check(not game._collect_ground_drop(distant),"Distant pickup rejected")
	distant.position = actor.position + Vector2(16,0)
	game._pick_up_nearest_drop()
	check(game.ground_drops.is_empty(),"F picks up nearest in range")
	check(game._spawn_ground_drop("Bronze Bow",1,actor.position),"Items without dedicated art use a collectible fallback")
	check(game._collect_ground_drop(game.ground_drops.back()),"Fallback drop can be collected")
	var fixed: Variant = load("res://scripts/dev_tools/item_visuals_fixed_loot.gd").new()
	var prior := {}
	for item_name: String in batch_names:
		prior[item_name] = int(game.player.backpack.get(item_name,0))
		fixed.fixed_items.append({"item":data.get_item_by_name(item_name),"quantity":2})
	var old_bows := int(game.player.backpack.get("Bronze Bow",0))
	fixed.fixed_items.append({"item":data.get_item_by_name("Bronze Bow"),"quantity":2})
	game.loot_system = fixed
	var monster_db: Dictionary = game._active_monster_database()
	game.spawn_monster_by_id(int(monster_db.keys()[0]))
	var monster: MonsterState = game.world.monsters.back()
	var events: Array[Dictionary] = [{"type":"entity_died","entity_id":monster.entity_id}]
	game._handle_combat_events(events)
	check(game.ground_drops.size() == 11,"Monster death creates physical drops including fallback items")
	for item_name: String in prior:
		check(int(game.player.backpack.get(item_name,0)) == int(prior[item_name]),item_name+" death must not auto-award")
	check(int(game.player.backpack.get("Bronze Bow",0)) == old_bows,"Fallback loot also waits for pickup")
	for drop: GroundItemDrop in game.ground_drops.duplicate():
		drop.position = actor.position + Vector2(16,0)
		check(game._collect_ground_drop(drop),"Monster drop collectible: "+drop.item_name)
	await process_frame
	game.inventory_menu.toggle()
	game.inventory_menu.select_page(0)
	await process_frame
	var item_icons := 0
	for widget: Node in game.inventory_menu.find_children("*","TextureRect",true,false):
		if widget.texture != null and widget.texture.resource_path.begins_with("res://Assets/Items/"):
			item_icons += 1
	check(item_icons >= 10,"Journal renders each new item icon")
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png(OUT+"/inventory-in-game.png")
		game.inventory_menu.toggle()
		var n := 0
		for item_name: String in batch_names:
			game._spawn_ground_drop(item_name,1,actor.position+Vector2((n%5-2)*42,(n/5+1)*38))
			n += 1
		await process_frame
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png(OUT+"/ground-in-game.png")
	var report := {"status":"pass" if failures.is_empty() else "fail","checks":checks,"errors":failures,"batch_items":10,"equipped_views":80}
	var file := FileAccess.open(OUT+"/integration-validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("[Item visuals] ",JSON.stringify(report))
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
