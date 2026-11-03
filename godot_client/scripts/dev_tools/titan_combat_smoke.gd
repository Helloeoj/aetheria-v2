extends Node
var checks := 0
var failures: Array[String]=[]
func _ready() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks+=1
	if not value:
		failures.append(label)
		printerr("[Titan combat FAIL] ",label)
func fixture(distance: float=1.5, seed_: int=719) -> Dictionary:
	var player := PlayerState.new("Titan regression")
	player.entity_id="p"
	player.x=20.5+distance
	player.y=20.5
	var world := WorldState.new(player)
	world.set_movement_bounds(Vector2(0.5,0.5),Vector2(99.5,99.5))
	var target := CombatActor.new().configure({"entity_id":"p","x":player.x,"y":player.y,"max_hp":1000000})
	world.register_player_actor(target)
	var monster := MonsterState.new({"id":1029,"name":"Golem Titan","max_hp":1000000,"attack_range":2},20.5,20.5)
	var boss := CombatActor.new().configure({"entity_id":"titan","name":"Golem Titan","x":20.5,"y":20.5,"is_monster":true,"max_hp":1000000,"attack_range":2,"min_damage":1,"max_damage":1,"accuracy":0.99,"monster_attack_type":"blunt"})
	world.register_monster_actor(monster,boss)
	world.combat.player_auto_attack_enabled=false
	world.combat.random.seed=seed_
	player.current_target="titan"
	boss.aggro_attacker_ids.append("p")
	return {"world":world,"engine":world.combat,"boss":boss,"target":target,"player":player,"monster":monster}
func step(f: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary]=[]
	for i in 36: events.append_array(f.engine.process_realtime(f.world,1.0/60.0))
	events.append_array(f.world.tick())
	return events
func starts(f: Dictionary, ticks: int) -> Array[Dictionary]:
	var out: Array[Dictionary]=[]
	for i in ticks:
		for event: Dictionary in step(f):
			if event.type=="titan_attack_started": out.append(event)
	return out
func main_sequence(events: Array[Dictionary]) -> Array:
	var result: Array=[]
	for event: Dictionary in events:
		if event.kind!="haymaker": result.append([event.kind,event.tick])
	return result
func run() -> void:
	var f:=fixture()
	var anchor: Vector2=f.boss.get_position() if f.boss.has_method("get_position") else Vector2(f.boss.x,f.boss.y)
	check(not f.boss.can_move(),"Titan movement is disabled at registration")
	f.world.move_actor_continuous("titan",Vector2(4,0))
	check(Vector2(f.boss.x,f.boss.y)==anchor,"ordinary movement cannot displace Titan")
	f.world.displace_actor("titan",Vector2(0,4))
	check(Vector2(f.boss.x,f.boss.y)==anchor,"knockback cannot displace Titan")
	f.monster.move_to(40,40)
	check(f.monster.get_position()==anchor,"monster state cannot wander independently")
	if f.engine.get("titan_encounters")==null:
		check(false,"shared Titan encounter controller is installed")
		finish()
		return
	var near_events:=starts(fixture(1.5,719),130)
	var far_fixture:=fixture(9,719)
	var far_events:=starts(far_fixture,130)
	var near_main:=main_sequence(near_events)
	check(near_main.size()>=10,"main attacks continue while target stays in melee")
	check(near_main==main_sequence(far_events),"haymakers never change main attack sequence or deadlines")
	var kinds: Dictionary={}
	var melee_count:=0
	var last: String=""
	for event: Dictionary in near_events:
		if event.kind=="haymaker": melee_count+=1
		else:
			check(String(event.kind)!=last,"identical main attacks do not repeat back-to-back")
			last=event.kind
			kinds[event.kind]=true
	check(kinds.size()==3 and melee_count>0,"all three main attacks and conditional haymakers are used")
	check(far_events.all(func(e: Dictionary) -> bool: return e.kind!="haymaker"),"no haymakers are started out of range")
	check(Vector2(far_fixture.boss.x,far_fixture.boss.y)==Vector2(20.5,20.5),"engaged ranged target cannot make Titan chase")
	check(near_main!=main_sequence(starts(fixture(1.5,977),130)),"different fights have different choices/timing")
	check_tiles_and_dodge()
	check_haymaker_whiff()
	check_homing()
	check_online_snapshot()
	finish()
func check_tiles_and_dodge() -> void:
	var f:=fixture(5,39)
	var cast: Dictionary={}
	for i in 50:
		for event: Dictionary in step(f):
			if event.type=="titan_attack_started" and event.kind in ["slam","eruption"]: cast=event
		if not cast.is_empty(): break
	check(not cast.is_empty(),"an area warning is created")
	if cast.is_empty(): return
	var cells: Array=cast.cells
	var unique: Dictionary={}
	for cell: Vector2i in cells: unique[cell]=true
	check(cells.size()==10 and unique.size()==10,"area attack has ten independent unique cells")
	check(unique.has(f.world.occupied_cell("p")),"target's warning-start cell is guaranteed")
	var old: Vector2=f.target.get_position() if f.target.has_method("get_position") else Vector2(f.target.x,f.target.y)
	var safe:=old
	for dx in range(-3,4):
		var candidate:=old+Vector2(dx,2)
		if not unique.has(f.world.cell_grid.cell_at(candidate)):
			safe=candidate
			break
	f.world.move_actor_continuous("p",safe-old)
	var bystander:=CombatActor.new().configure({"entity_id":"bystander","x":old.x,"y":old.y,"max_hp":1000000})
	f.engine.add_actor(bystander)
	var hits: Array[Dictionary]=[]
	for i in 3:
		var events:=step(f)
		for event: Dictionary in events:
			if event.get("titan_attack_id","")==cast.attack_id and event.type=="entity_hit": hits.append(event)
		if i<2: check(hits.is_empty(),"warning/rise does not damage before peak")
	check(hits.all(func(e: Dictionary) -> bool: return e.target_id!="p"),"leaving the captured warning cell avoids damage")
	check(hits.size()==1 and hits[0].target_id=="bystander","one impact roll per player on a warned cell")
	f.boss.is_alive=false
	f.boss.hp=0
	step(f)
	check(f.engine.titan_encounters.snapshot(f.engine).titan_actions.is_empty(),"death removes pending encounter visuals/hits")
func check_haymaker_whiff() -> void:
	var f := fixture(1.5)
	var punch: Dictionary = {}
	for i in 30:
		for event: Dictionary in step(f):
			if event.type == "titan_attack_started" and event.kind == "haymaker": punch = event
		if not punch.is_empty(): break
	check(not punch.is_empty(), "nearby player triggers a haymaker windup")
	if punch.is_empty(): return
	f.world.move_actor_continuous("p", Vector2(5, 0))
	var hits: Array[Dictionary] = []
	for i in 3:
		for event: Dictionary in step(f):
			if event.get("titan_attack_id", "") == punch.attack_id and event.type == "entity_hit": hits.append(event)
	check(hits.is_empty(), "haymaker whiffs when player leaves melee range before contact")
func check_homing() -> void:
	var f:=fixture(10)
	f.target.y+=4
	var p:=CombatProjectile.new().configure({"projectile_id":"curve","attacker_id":"titan","target_id":"p","x":20.5,"y":20.5,"dx":1.0,"dy":0.0,"speed":10.0,"max_range":40,"homing_turn_rate":3.0})
	f.engine.projectiles.curve=p
	f.engine._process_projectiles(f.world,0.1)
	check(p.dy>0.0 and p.dx>0.0,"dark missile steers toward a moving target")
	check(Vector2(p.dx,p.dy).angle()<=0.30001,"steering has a bounded turn rate")
	check(p.travelled>0.99 and p.travelled<1.01,"turning preserves projectile speed")
	f.target.is_alive=false
	f.engine._process_projectiles(f.world,0.1)
	check(not f.engine.projectiles.has("curve"),"lost/dead homing targets clean up the missile")
	var straight:=CombatProjectile.new().configure({"projectile_id":"straight","attacker_id":"titan","target_id":"p","x":20.5,"y":20.5,"dx":1.0,"dy":0.0,"speed":10.0,"max_range":40})
	f.engine.projectiles.straight=straight
	f.engine._process_projectiles(f.world,0.1)
	check(straight.dx==1.0 and straight.dy==0.0,"ordinary projectiles retain their captured straight path")
func check_online_snapshot() -> void:
	var f:=fixture(6)
	step(f)
	var region:=AuthoritativeRegion.new()
	region.configure("test",null)
	region.world=f.world
	region.players.p=f.player
	var packet:=region.snapshot("p")
	check(packet.has("titan_actions") and not packet.titan_actions.is_empty(),"authoritative snapshots publish the active encounter")
	var encoded:=JSON.stringify(packet)
	check(JSON.parse_string(encoded) is Dictionary,"encounter snapshot is JSON serializable")
	var other:=CombatActor.new().configure({"entity_id":"ordinary","is_monster":true})
	check(other.can_move(),"other monsters remain mobile")
func finish() -> void:
	print("[Titan combat] ",checks," checks; ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
