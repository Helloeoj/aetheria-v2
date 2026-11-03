extends SceneTree
## Cast through the real Main event path; no character/save mutation persists.
var failures:=0
var checks:=0
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("[Spell facing FAIL] ",label)
func run() -> void:
	root.size=Vector2i(1280,720)
	var map: Node=load("res://scenes/EastOutskirtsLayered.tscn").instantiate()
	map.get_node("Combat").set("initial_spawn_id","TavernReturn")
	root.get_node("SceneTravel").set("_player",null)
	root.add_child(map)
	current_scene=map
	var game: Node=map.get_node("Combat")
	game.set_physics_process(false)
	for frame in range(180):
		await physics_frame
		if game.grid_adapter!=null and game.grid_adapter.completed: break
	game.player.set_skill_level("magic",100)
	game.player.current_mana=10000
	game.call("_refresh_player_actor_from_player")
	var actor: ActorSprite=game.actor_sprites[game.player.entity_id]
	var origin: Vector2=game.player.get_position()
	var target:=CombatActor.new().configure({"entity_id":"facing-target","name":"Goblin Scout","x":origin.x+2,"y":origin.y,"hp":10000,"max_hp":10000,"is_monster":true})
	game.combat.add_actor(target)
	var sprite:=ActorSprite.new().configure(Vector2(32,32),game.MONSTER_COLOR,target.entity_id)
	sprite.set_skin("goblin_scout")
	game.add_child(sprite)
	game.actor_sprites[target.entity_id]=sprite
	var directions: Array[String]=["east","south-east","south","south-west","west","north-west","north","north-east"]
	for i in directions.size():
		var direction:=Vector2.RIGHT.rotated(float(i)*PI/4.0)
		target.x=origin.x+direction.x*2
		target.y=origin.y-direction.y*2
		game.call("_update_sprite_position",target.entity_id)
		game.combat.active_spell_casts.clear()
		actor.cancel_action()
		actor.face_direction(-direction)
		var cast: Dictionary=game.combat.cast_spell(game.world,game.player.entity_id,"water_crashing_tide",target.entity_id)
		check(cast.get("ok",false),directions[i]+" real cast starts")
		var events: Array[Dictionary]=[]
		events.assign(cast.get("events",[]))
		game.call("_handle_combat_events",events)
		check(actor.facing==directions[i],directions[i]+" caster faces creature at cast start")
	# Ground point must override the unrelated selected creature's position.
	game.combat.active_spell_casts.clear()
	actor.cancel_action()
	actor.face_direction(Vector2.LEFT)
	var ground:=origin+Vector2(2,2)
	var cast: Dictionary=game.combat.cast_spell(game.world,game.player.entity_id,"air_stormring",target.entity_id,ground)
	var events: Array[Dictionary]=[]
	events.assign(cast.get("events",[]))
	game.call("_handle_combat_events",events)
	check(actor.facing=="north-east","ground-target spell faces captured point")
	var protocol=load("res://scripts/spell_visual_events.gd").new()
	protocol.record(events[0],game.combat,0.0)
	check(protocol.events[0].get("target_point")==[ground.x,ground.y],"online event retains exact ground aim")
	actor.cancel_action()
	actor.face_direction(Vector2.DOWN)
	game.spell_visuals.apply_snapshot({"spell_projectiles":[],"spell_visual_events":[{"serial":1,"type":"spell_cast_started","spell_id":"water_crashing_tide","caster_id":game.player.entity_id,"caster_point":[origin.x,origin.y],"target_point":[origin.x-2,origin.y],"cast_time_seconds":2.2}]})
	check(actor.facing=="west","authoritative online cast also turns player")
	var caster: CombatActor=game.combat.actors[game.player.entity_id]
	check(Vector2(caster.x,caster.y)==origin and game.player.get_position()==origin,"turning does not move player")
	# The real map camera at 4x, with the player casting toward the visible target.
	target.x=origin.x-2
	target.y=origin.y
	game.call("_update_sprite_position",target.entity_id)
	map.get_node("MapCamera").zoom=Vector2(4,4)
	map.get_node("MapCamera").position=game.call("_screen_position",origin.x-1,origin.y)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--facing-capture=") and DisplayServer.get_name()!="headless":
			await process_frame
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(arg.trim_prefix("--facing-capture="))==OK,"real in-game facing capture")
	print("[Spell facing] ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
