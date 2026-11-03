extends SceneTree
## Focused real-map test: cast follows movement/interpolation, hits stay fixed.
var failures:=0
var checks:=0
var output:=""
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("[Cast follow FAIL] ",label)
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--cast-follow-output="): output=arg.trim_prefix("--cast-follow-output=")
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
	game.spell_visuals.set_process(false)
	game.player.set_skill_level("magic",100)
	game.player.current_mana=10000
	game.call("_refresh_player_actor_from_player")
	var actor: ActorSprite=game.actor_sprites[game.player.entity_id]
	var origin: Vector2=game.player.get_position()
	var target:=CombatActor.new().configure({"entity_id":"cast-follow-target","x":origin.x+4,"y":origin.y,"hp":10000,"max_hp":10000,"is_monster":true})
	game.combat.add_actor(target)
	var cast: Dictionary=game.combat.cast_spell(game.world,game.player.entity_id,"water_crashing_tide",target.entity_id)
	check(cast.get("ok",false),"real spell cast starts")
	var events: Array[Dictionary]=[]
	events.assign(cast.get("events",[]))
	game.call("_handle_combat_events",events)
	var effect: Node2D=game.spell_visuals.effects[0]
	game.spell_visuals.advance(0.65)
	var start:=actor.position
	map.get_node("MapCamera").zoom=Vector2(4,4)
	map.get_node("MapCamera").position=start
	await capture("before-move")
	# Existing movement controls and real grid/physics update the player's sprite.
	game.movement_controller.on_input("d",true)
	for step in range(8): game.call("_move_player",0.03125)
	game.movement_controller.on_input("d",false)
	check(actor.position.distance_to(start)>8.0,"actual game movement moves caster")
	game.spell_visuals.advance(0.1)
	check(effect.position.is_equal_approx(actor.position),"casting effect follows moving player")
	check(effect.age>0.65,"following does not restart the animation")
	await capture("after-move")
	var impact: Node2D=game.spell_visuals.spawn("water_crashing_tide","impact",origin+Vector2(4,0))
	var hit_anchor:=impact.position
	var logical: Vector2=game.player.get_position()
	var view=load("res://network/online_world_view.gd").new()
	view.game=game
	game.add_child(view)
	view._render_actor(game.player.entity_id,logical+Vector2(0.5,0))
	game.spell_visuals.advance(0.1)
	check(effect.position.is_equal_approx(actor.position),"cast follows interpolated sprite rather than stale simulation position")
	check(impact.position==hit_anchor,"hit effects retain their collision position")
	check(game.player.get_position()==logical,"visual following does not move the player simulation")
	game.spell_visuals.handle_event({"type":"spell_cast_completed","spell_id":"water_crashing_tide","caster_id":game.player.entity_id})
	check(not game.spell_visuals.effects.has(effect),"cast completion still cleans up attached effect")
	print("[Cast follow] ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name()=="headless": return
	DirAccess.make_dir_recursive_absolute(output)
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label+"-4x.png"))==OK,"actual in-game 4x capture "+label)
