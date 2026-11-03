extends RefCounted
## Bounded public presentation data. Never changes a combat outcome.
var serial:=0
var events: Array[Dictionary]=[]
const TYPES=["spell_cast_started","spell_cast_completed","spell_cast_failed","projectile_hit","projectile_blocked","spell_healed","spell_knockback","spell_area_resolved","spell_wall_created"]
func record(event: Dictionary, combat: CombatEngine, clock: float) -> void:
	if not String(event.get("type","")) in TYPES or String(event.get("spell_id","")).is_empty(): return
	serial+=1
	var caster:=String(event.get("caster_id",event.get("attacker_id","")))
	var target:=String(event.get("target_id",""))
	if target.is_empty(): target=String(combat.active_spell_casts.get(caster,{}).get("target_id",""))
	var data:={"serial":serial,"type":String(event.type),"spell_id":String(event.spell_id),"caster_id":caster,"target_id":target,"clock":clock}
	if event.has("cast_time_seconds"): data["cast_time_seconds"]=float(event.cast_time_seconds)
	for pair: Array in [["caster_point",caster],["target_point",target]]:
		var actor: CombatActor=combat.actors.get(String(pair[1]))
		if actor!=null: data[String(pair[0])]=[actor.x,actor.y]
	for key: String in ["point","center","from"]:
		if event.get(key) is Vector2:
			var p: Vector2=event[key]
			data[key]=[p.x,p.y]
	events.append(data)
	while events.size()>64: events.pop_front()
func snapshot(combat: CombatEngine, frozen: Dictionary, clock: float) -> Dictionary:
	var projectiles: Array[Dictionary]=[]
	for p: CombatProjectile in combat.projectiles.values():
		if p.spell_id.is_empty() or frozen.has(p.attacker_id) or frozen.has(p.target_id): continue
		projectiles.append({"projectile_id":p.projectile_id,"spell_id":p.spell_id,"x":p.x,"y":p.y,"dx":p.dx,"dy":p.dy,"speed":p.speed})
	var published: Array[Dictionary]=[]
	for event: Dictionary in events:
		var age:=clock-float(event.clock)
		if age>2.0 or frozen.has(String(event.caster_id)) or frozen.has(String(event.target_id)): continue
		var data:=event.duplicate()
		data.erase("clock")
		data["age"]=maxf(0.0,age)
		published.append(data)
	return {"spell_projectiles":projectiles,"spell_visual_events":published}
