extends SceneTree
## Real Main + map + CombatEngine collision path, with optional 4x captures.
var failures := 0
var checks := 0
var output := ""
var game: Node
var map: Node
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Spell visuals FAIL] ",label)
func run() -> void:
	if not ResourceLoader.exists("res://scripts/spell_visuals.gd"):
		check(false,"spell visuals are installed")
		finish()
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--spell-capture="): output=arg.trim_prefix("--spell-capture=")
	root.size=Vector2i(1280,720)
	map=load("res://scenes/EastOutskirtsLayered.tscn").instantiate()
	map.get_node("Combat").set("initial_spawn_id","TavernReturn")
	root.get_node("SceneTravel").set("_player",null)
	root.add_child(map)
	current_scene=map
	game=map.get_node("Combat")
	game.set_physics_process(false)
	for frame in range(180):
		await physics_frame
		if game.grid_adapter!=null and game.grid_adapter.completed: break
	var visuals: Node=game.get("spell_visuals")
	check(visuals!=null,"real Main installs independent visuals")
	if visuals==null:
		finish()
		return
	visuals.set_process(false)
	check(visuals.library.spells.size()==27,"all 27 reviewed spells loaded")
	for id: String in visuals.library.spells:
		var definition: Dictionary=visuals.library.spells[id]
		if definition.has("projectile"):
			check(definition.projectile.directions.size()==8,id+" has eight object facings")
	check(root.get_node("GameData").get_spell("water_crashing_tide").name=="Ice Spear","approved water name installed")
	check(root.get_node("GameData").get_spell("earth_falling_monolith").name=="Upheaval","approved earth name installed")
	check(visuals.library.spells.arcane_mending_light.projectile.scale==1.0,"Mending Light reference size retained")
	game.player.set_skill_level("magic",100)
	game.player.current_mana=10000
	game.call("_refresh_player_actor_from_player")
	game.combat.player_auto_attack_enabled=false
	var origin: Vector2=game.player.get_position()
	var target:=CombatActor.new().configure({"entity_id":"spell-review-target","name":"Goblin Scout","x":origin.x+4,"y":origin.y,"hp":10000,"max_hp":10000,"is_monster":true})
	game.combat.add_actor(target)
	var sprite:=ActorSprite.new().configure(Vector2(32,32),game.MONSTER_COLOR,target.entity_id)
	sprite.set_skin("goblin_scout")
	game.add_child(sprite)
	game.actor_sprites[target.entity_id]=sprite
	game.player.current_target=target.entity_id
	game.call("_update_sprite_position",target.entity_id)
	map.get_node("MapCamera").zoom=Vector2(4,4)
	map.get_node("MapCamera").position=game.call("_screen_position",origin.x+2,origin.y)
	for id: String in ["water_crashing_tide","earth_falling_monolith"]:
		visuals.clear()
		game.combat.active_spell_casts.clear()
		game.combat.projectiles.clear()
		var cast: Dictionary=game.combat.cast_spell(game.world,game.player.entity_id,id,target.entity_id)
		check(cast.get("ok",false),id+" uses actual casting")
		if not cast.get("ok",false): continue
		send(cast.events)
		send(game.combat._process_spell_casts(game.world,3.0))
		visuals.advance(0.0)
		check(visuals.projectile_nodes.size()==1,id+" renders a physical projectile")
		check(visuals.impact_count()==0,id+" has no impact before collision")
		send(game.combat._process_projectiles(game.world,0.10))
		visuals.advance(0.12)
		await capture(id+"-projectile")
		var hit_events: Array=game.combat._process_projectiles(game.world,0.20)
		send(hit_events)
		visuals.advance(0.15)
		check(game.combat.projectiles.is_empty() and visuals.projectile_nodes.is_empty(),id+" object removed on physical contact")
		check(visuals.impact_count()==1,id+" independent hit spawned at real collision")
		await capture(id+"-impact")
		visuals.advance(5.0)
		check(visuals.impact_count()==0,id+" one-shot hit cleans up")
	# Read-only network presentation: same projectile state, deduplicated events.
	visuals.clear()
	var snapshot:={"spell_projectiles":[{"projectile_id":"remote","spell_id":"water_crashing_tide","x":origin.x+2,"y":origin.y,"dx":1.0,"dy":0.0,"speed":20.0}],"spell_visual_events":[]}
	visuals.apply_snapshot(snapshot)
	check(visuals.remote_projectiles.size()==1,"online physical projectile projection")
	var event:={"serial":1,"type":"projectile_hit","spell_id":"water_crashing_tide","point":[target.x,target.y],"age":0.0}
	visuals.apply_snapshot({"spell_projectiles":[],"spell_visual_events":[event]})
	visuals.apply_snapshot({"spell_projectiles":[],"spell_visual_events":[event]})
	check(visuals.impact_count()==1,"repeated snapshots do not replay hit effects")
	visuals.clear()
	check(visuals.impact_count()==0 and visuals.remote_projectiles.is_empty(),"area exit clears transient spell art")
	var region=load("res://network/authoritative_region.gd").new()
	region.configure("spell-test",game)
	region._handle_events([{"type":"projectile_hit","spell_id":"water_crashing_tide","point":Vector2(1,2)}])
	check(region.snapshot("").get("spell_visual_events",[]).size()==1,"server publishes cosmetic collision events")
	if not output.is_empty():
		var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scene":"EastOutskirtsLayered","zoom":4},"  "))
	finish()
func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name()=="headless": return
	DirAccess.make_dir_recursive_absolute(output)
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label+"-4x.png"))==OK,"actual map 4x capture "+label)
func send(events: Array) -> void:
	var typed: Array[Dictionary]=[]
	typed.assign(events)
	game.call("_handle_combat_events",typed)
func finish() -> void:
	print("[Spell visuals] ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
