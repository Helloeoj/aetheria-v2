extends RefCounted
## Shared offline/server mine population. Positions are authored world pixels.
const ROAM_RADIUS := 10.0
const RESPAWN_SECONDS := 15.0
const ENCOUNTERS := [
	[2, 5648,2064], [15,5520,2000], [1049,5744,528], [2,5680,624],
	[15,4976,1808], [1049,4976,1936],
	[29,4080,1616], [1050,4176,1680], [1052,3984,432], [29,4080,528],
	[1050,4176,2832], [1052,4272,2896],
	[56,3056,368], [1053,3152,432], [60,1008,2800], [1053,1104,2864],
	[60,464,720], [56,560,784]
]
var slots: Array[Dictionary] = []
var serial := 0
var rng := RandomNumberGenerator.new()

func advance(game: Node, world: WorldState, delta: float, server: bool = false) -> void:
	if world.grid == null: return
	if slots.is_empty():
		rng.randomize()
		for row: Array in ENCOUNTERS:
			var home := Vector2(float(row[1])/32.0, (3328.0-float(row[2]))/32.0)
			slots.append({"template":int(row[0]),"home":home,"entity":"","remaining":0.0,"goal":home,"pause":0.0})
	for slot: Dictionary in slots:
		var actor: CombatActor = world.combat.actors.get(slot.entity)
		if not String(slot.entity).is_empty() and (actor == null or not actor.is_alive):
			if actor != null: world.remove_monster(slot.entity)
			slot.entity = ""
			slot.remaining = RESPAWN_SECONDS
			continue
		if String(slot.entity).is_empty():
			slot.remaining = maxf(0.0,float(slot.remaining)-delta)
			if float(slot.remaining) <= 0.0: _spawn(game,world,slot,server)
			continue
		if bool(slot.aggressive) and actor.current_target_id.is_empty():
			for player: PlayerState in world.player_states():
				var target: CombatActor = world.combat.actors.get(player.entity_id)
				if target == null or not target.is_alive: continue
				var point := Vector2(target.x,target.y)
				if point.distance_to(slot.home) <= ROAM_RADIUS and Vector2(actor.x,actor.y).distance_to(point) <= ROAM_RADIUS and world.has_line_of_sight(Vector2(actor.x,actor.y),point):
					if target.entity_id not in actor.aggro_attacker_ids: actor.aggro_attacker_ids.append(target.entity_id)
					break
		if not actor.current_target_id.is_empty() or not actor.aggro_attacker_ids.is_empty(): continue
		slot.pause = maxf(0.0,float(slot.pause)-delta)
		if float(slot.pause) > 0.0: continue
		var position := Vector2(actor.x,actor.y)
		if position.distance_to(slot.goal) < 0.01:
			slot.pause = rng.randf_range(0.6,1.2)
			for attempt in 16:
				var goal: Vector2 = slot.home + Vector2(rng.randi_range(-10,10),rng.randi_range(-10,10))
				if goal.distance_to(slot.home) > ROAM_RADIUS: continue
				var route := world.grid.path(position,goal,0.0,func(p:Vector2)->bool:return p.distance_to(slot.home)<=ROAM_RADIUS)
				if not route.is_empty():
					slot.goal=goal
					break
		world.move_grid_toward(actor.entity_id,slot.goal,delta,CombatEngine.MONSTER_MOVE_SPEED_TILES_PER_SECOND,0.0,func(p:Vector2)->bool:return p.distance_to(slot.home)<=ROAM_RADIUS)

func _spawn(game: Node, world: WorldState, slot: Dictionary, server: bool) -> void:
	var template: Dictionary = game._active_monster_database().get(int(slot.template),{})
	if template.is_empty(): return
	var home: Vector2 = slot.home
	if not game.monster_spawn_allowed(home): return
	for other: CombatActor in world.combat.actors.values():
		if other.is_alive and Vector2(other.x,other.y).distance_to(home)<0.75: return
	serial+=1
	var monster:=MonsterState.new(template,home.x,home.y)
	monster.entity_id="mine_%d"%serial
	monster.set_meta("dungeon_loot_table","valtherian_mines")
	var actor: CombatActor=game._create_actor_from_stats(monster.entity_id,monster.name,home.x,home.y,monster.get_combat_stats(),true,monster.damage_type)
	actor.set_meta("mine_roaming",true)
	if not world.register_monster_actor(monster,actor): return
	slot.entity=monster.entity_id
	slot.aggressive=int(template.get("level",1))>=36
	slot.goal=home
	if server:
		return # Region installs its physics body immediately after this call.
	var sprite:=ActorSprite.new().configure(Vector2(32,32),Color(0.09,0.45,0.27),monster.entity_id)
	sprite.set_skin(CharacterSpriteLibrary.skin_for_monster(monster.name))
	game.add_child(sprite)
	game.actor_sprites[monster.entity_id]=sprite
	game._update_sprite_position(monster.entity_id)
	game._register_monster_for_targeting(monster)

func has_loot(template: Dictionary) -> bool:
	var loot := LootSystem.new()
	if not loot._get_monster_loot_table(template).is_empty(): return true
	# Existing generic fallback is a real drop source, not the old unused loot rows.
	var pools := loot._tier_pools(int(template.get("tier",1)),template)
	for pool: Array in pools.values():
		if not pool.is_empty(): return true
	return not loot._tier_pools(1,template).general.is_empty()
