extends SceneTree
## Real inventory/Main/world actor review. Pickaxes are explicitly art fixtures.
var destination := ""
var families: Array[String] = ["warmaul"]
var directions: Array[String] = ["south-east"]
var loadouts: Array[String] = ["armor"]
var selected_frames: Array[int] = []
var tier := "Bronze"
var game: Node
var actor: ActorSprite
var camera: Camera2D
var failures := 0
var assertions: Array[Dictionary] = []
var cases: Array[Dictionary] = []
var current_case := ""
var review_point := Vector2.ZERO
func _initialize() -> void:
	run.call_deferred()
func check(value: bool, message: String) -> void:
	assertions.append({"case":current_case,"passed":value,"message":message})
	if not value:
		failures+=1
		printerr("[World motion FAIL] ",current_case," ",message)
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--world-motion-output="): destination=arg.trim_prefix("--world-motion-output=")
		elif arg.begins_with("--world-motion-families="): families.assign(arg.trim_prefix("--world-motion-families=").split(",",false))
		elif arg.begins_with("--world-motion-directions="): directions.assign(arg.trim_prefix("--world-motion-directions=").split(",",false))
		elif arg.begins_with("--world-motion-loadouts="): loadouts.assign(arg.trim_prefix("--world-motion-loadouts=").split(",",false))
		elif arg.begins_with("--world-motion-tier="): tier=arg.trim_prefix("--world-motion-tier=").capitalize()
		elif arg.begins_with("--world-motion-frames="):
			for value: String in arg.trim_prefix("--world-motion-frames=").split(",",false): selected_frames.append(int(value))
	if destination.is_empty() or not CharacterWeaponMotion.enabled():
		printerr("Requires --world-motion-output and --player-motion-candidate")
		quit(1)
		return
	for direction: String in directions:
		if not direction in CharacterSpriteLibrary.DIRECTIONS:
			printerr("Unknown direction: ",direction)
			quit(1)
			return
	for loadout: String in loadouts:
		if not loadout in ["armor","bare","chest-only","legs-only","mixed"]:
			printerr("Unknown loadout: ",loadout)
			quit(1)
			return
	DirAccess.make_dir_recursive_absolute(destination)
	root.size=Vector2i(1280,720)
	root.mode=Window.MODE_MINIMIZED
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var scene: Node=load("res://scenes/EastOutskirtsLayered.tscn").instantiate()
	# Use an authored open-world arrival point instead of the combat demo's
	# default coordinates, which are hidden behind foreground trees here.
	scene.get_node("Combat").set("initial_spawn_id","TavernReturn")
	root.get_node("SceneTravel").set("_player",null)
	root.add_child(scene)
	game=scene.get_node("Combat")
	await process_frame
	while game.get("grid_adapter")==null or not game.get("grid_adapter").completed: await physics_frame
	actor=game.get("actor_sprites").get(game.get("player").entity_id)
	camera=scene.get_node("MapCamera")
	camera.zoom=Vector2(4,4)
	for skill: String in ["attack","strength","defense","range","magic"]: game.get("player").set_skill_level(skill,100)
	game.get("sprite_preview").hide_preview()
	game.set_physics_process(false)
	choose_review_point()
	for family: String in families:
		check(not CharacterWeaponMotion.definition(family).is_empty(),"authored family: "+family)
		for loadout: String in loadouts:
			for direction: String in directions:
				current_case="%s-%s-%s/%s" % [tier.to_lower(),family,loadout,direction]
				await review_case(family,loadout,direction)
	var report:={"scene":"res://scenes/EastOutskirtsLayered.tscn","spawn":"TavernReturn","review_simulation_point":[review_point.x,review_point.y],"zoom":4,"candidate":true,"artwork_approval":"pending","failures":failures,"families":families,"directions":directions,"loadouts":loadouts,"tier":tier,"selected_frames":selected_frames,"cases":cases,"assertions":assertions}
	var file:=FileAccess.open(destination.path_join("world-matrix.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("[World player motion] ",failures," failures; ",cases.size()," cases; ",destination)
	scene.free()
	quit(0 if failures==0 else 1)
func choose_review_point() -> void:
	var world: Variant=game.get("world")
	var grid: HiddenGrid=world.grid
	var start: Vector2=game.get("player").get_position()
	review_point=start
	if grid==null:
		check(false,"world scene has its validated hidden grid")
		return
	var base:=grid.cell_at(start)
	var best:=INF
	for y in range(-5,6):
		for x in range(-5,6):
			var cell:=base+Vector2i(x,y)
			var connected:=true
			for step: Vector2i in HiddenGrid.DIRECTIONS:
				connected=connected and grid.connected(cell,cell+step)
			var point:=grid.center(cell)
			if connected and point.distance_squared_to(start)<best:
				best=point.distance_squared_to(start)
				review_point=point
	check(is_finite(best),"review point has eight physics-checked neighboring movement approaches")
func reset_review_position() -> void:
	var player: Variant=game.get("player")
	var world: Variant=game.get("world")
	var body: Variant=game.get("combat").actors.get(player.entity_id)
	body.x=review_point.x
	body.y=review_point.y
	player.x=review_point.x
	player.y=review_point.y
	world.grid_traveller(player.entity_id)
	game.call("_update_sprite_position",player.entity_id)
func configure_equipment(family: String, loadout: String) -> Dictionary:
	var player: Variant=game.get("player")
	for slot: String in player.equipment.keys(): player.unequip_slot(slot)
	var names: Array[String]=[]
	if loadout in ["armor","chest-only","mixed"]: names.append(tier+" Platebody")
	if loadout in ["armor","legs-only","mixed"]:
		var leg_tier: String=("Iron" if tier=="Bronze" else "Bronze") if loadout=="mixed" else tier
		names.append(leg_tier+" Platelegs")
	if loadout in ["armor","mixed"]: names.append(tier+" Cape")
	if family!="pickaxe": names.append(tier+" "+family.replace("-"," ").capitalize())
	for item_name: String in names:
		var item: Dictionary=root.get_node("GameData").get_item_by_name(item_name)
		check(not item.is_empty(),"real inventory catalog contains "+item_name)
		if not item.is_empty(): player.give_and_equip(item_name)
	game.call("_refresh_player_actor_from_player")
	var expected: Dictionary=player.equipment.duplicate(true)
	if family=="pickaxe":
		# Existing held artwork only: no gameplay item or catalog entry invented.
		expected["weapon"]={"name":tier+" Pickaxe"}
		actor.set_equipment(expected)
	check(actor.weapon_animation_family()==family,"world actor selected requested weapon family")
	return expected
func apply_fixture(family: String, gear: Dictionary) -> void:
	if family=="pickaxe": actor.set_equipment(gear)
func direction_vector(direction: String) -> Vector2:
	return Vector2.DOWN.rotated(-CharacterSpriteLibrary.DIRECTIONS.find(direction)*PI/4.0).round()
func movement_keys(direction: String) -> Array[int]:
	var vector:=direction_vector(direction)
	var keys: Array[int]=[]
	if vector.x>0: keys.append(KEY_D)
	if vector.x<0: keys.append(KEY_A)
	if vector.y>0: keys.append(KEY_S)
	if vector.y<0: keys.append(KEY_W)
	return keys
func send_keys(keys: Array[int], pressed: bool) -> void:
	for key: int in keys:
		var event:=InputEventKey.new()
		event.keycode=key
		event.pressed=pressed
		game.call("_unhandled_input",event)
func review_case(family: String, loadout: String, direction: String) -> void:
	game.set_physics_process(false)
	game.call("_reset_held_movement")
	reset_review_position()
	actor.cancel_action()
	actor.set_process(true)
	var gear:=configure_equipment(family,loadout)
	var keys:=movement_keys(direction)
	var before:=actor.global_position
	var observed_walk:=false
	var observed_clips: Array[String]=[]
	send_keys(keys,true)
	game.set_physics_process(true)
	for _step in range(12):
		await physics_frame
		await process_frame
		# Reapply only the explicit art fixture after Main's real refresh.
		apply_fixture(family,gear)
		var observed:=String(actor.animated_sprite.animation)
		if not observed in observed_clips: observed_clips.append(observed)
		observed_walk=observed_walk or observed=="walk_"+direction
	var displacement:=actor.global_position-before
	var walking_clip:=String(actor.animated_sprite.animation)
	send_keys(keys,false)
	game.call("_reset_held_movement")
	game.set_physics_process(false)
	check(displacement.length()>0.01,"real key input and Main physics moved world player")
	check(observed_walk,"real movement selected requested walk direction during held input")
	actor.cancel_action()
	actor.face_direction(direction_vector(direction))
	apply_fixture(family,gear)
	# Exercise Main's actual presentation event route with zero damage.
	var event_type:="projectile_spawned" if family in ["bow","crossbow"] else "entity_hit"
	var events: Array[Dictionary]=[{"type":event_type,"attacker_id":game.get("player").entity_id,"damage":0}]
	game.call("_handle_combat_events",events)
	check(String(actor.animated_sprite.animation)=="attack_"+direction and not actor._fallback_attack,"Main combat event route triggered actual family attack")
	check(actor.weapon_animation_family()==family,"combat route retained requested weapon family")
	actor.set_process(false)
	var folder:=destination.path_join("%s-%s-%s" % [tier.to_lower(),family,loadout])
	DirAccess.make_dir_recursive_absolute(folder)
	var count:=0
	for action: String in ["idle","walk","attack"]:
		var clip:=CharacterSpriteLibrary.animation_name(action,direction)
		check(actor.animated_sprite.sprite_frames.has_animation(clip),"world actor has "+String(clip))
		actor.animated_sprite.play(clip)
		actor.animated_sprite.pause()
		for frame in range(actor.animated_sprite.sprite_frames.get_frame_count(clip)):
			if not selected_frames.is_empty() and not frame in selected_frames: continue
			game.call("_refresh_player_actor_from_player")
			apply_fixture(family,gear)
			actor.animated_sprite.play(clip)
			actor.animated_sprite.pause()
			actor.animated_sprite.frame=frame
			actor.attachment_rig.sync_pose()
			await process_frame
			camera.global_position=actor.global_position+Vector2(0,-20)
			camera.force_update_scroll()
			RenderingServer.force_draw(false)
			var screenshot:=root.get_texture().get_image()
			var stem:="%s-%s-%02d" % [direction,action,frame]
			check(screenshot.save_png(folder.path_join("world-"+stem+".png"))==OK,"saved world "+stem)
			var foot:=actor.get_global_transform_with_canvas().origin
			var area:=Rect2i(Vector2i(foot)-Vector2i(240,280),Vector2i(480,340)).intersection(Rect2i(Vector2i.ZERO,screenshot.get_size()))
			check(screenshot.get_region(area).save_png(folder.path_join("player-"+stem+".png"))==OK,"saved player "+stem)
			var motion:=actor.attachment_rig.get_weapon_motion()
			if bool(motion.get("active",false)):
				var torso:=actor.animated_sprite.get_node_or_null("ArmorMotionTorso") as Sprite2D
				check(torso!=null and torso.is_visible_in_tree() and torso.texture!=null,"active world motion has visible torso")
			count+=1
	cases.append({"family":family,"loadout":loadout,"direction":direction,"equipment_route":"actor_art_fixture_after_real_main_refresh" if family=="pickaxe" else "PlayerState.give_and_equip -> Main._refresh_player_actor_from_player","movement_route":"Main._unhandled_input -> Main._physics_process -> ActorSprite.update_visual_motion","movement_displacement":[displacement.x,displacement.y],"walk_clip":walking_clip,"observed_movement_clips":observed_clips,"combat_route":"Main._handle_combat_events -> Main._show_combat_sprite_event -> ActorSprite.play_attack","combat_event":event_type,"capture_pairs":count,"folder":folder})
	print("[World motion case] ",current_case," captured ",count," frame pairs")
