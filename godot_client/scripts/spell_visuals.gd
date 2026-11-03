extends Node
## Presentation follows actual combat objects and hit events. Native scale 1.
const Library=preload("res://scripts/spell_visual_library.gd")
class Visual extends Node2D:
	var library: RefCounted
	var definition: Dictionary
	var mode: String
	var direction: String="east"
	var age:=0.0
	var duration:=0.0
	var art_offset:=Vector2.ZERO
	var forward:=Vector2.RIGHT
	var owner_id: String=""
	func _draw() -> void:
		var frame:=floori(age*float(definition.fps))
		if mode=="projectile":
			var clip: Dictionary=definition.projectile.directions[direction]
			library.draw_clip(self,clip,posmod(frame,int(clip.frames)),art_offset)
		else:
			var group: Dictionary=definition[mode]
			if duration>0: frame=mini(library.length_frames(group)-1,floori(age/duration*library.length_frames(group)))
			for clip: Dictionary in group.clips:
				library.draw_clip(self,clip,frame,forward*float(clip.get("anchor_forward",0)))
var library=Library.new()
var game: Node
var projectile_nodes: Dictionary={}
var effects: Array[Visual]=[]
var remote_projectiles: Dictionary={}
var _remote:=false
var _last_serial:=0
var _snapshot_age:=0.0
func configure(owner_game: Node) -> void:
	game=owner_game
	# Follow the rendered caster after online actor interpolation has run.
	process_priority=100
func _process(delta: float) -> void:
	advance(delta)
func clear() -> void:
	for node: Visual in effects:
		if is_instance_valid(node): node.queue_free()
	for node: Visual in projectile_nodes.values():
		if is_instance_valid(node): node.queue_free()
	effects.clear()
	projectile_nodes.clear()
	remote_projectiles.clear()
	_last_serial=0
	_remote=false
func _exit_tree() -> void:
	clear()
func impact_count() -> int:
	var count:=0
	for node: Visual in effects:
		if node.mode=="impact": count+=1
	return count
func point(value: Variant, fallback: Vector2=Vector2.ZERO) -> Vector2:
	if value is Vector2: return value
	if value is Array and value.size()==2: return Vector2(float(value[0]),float(value[1]))
	return fallback
func actor_point(id: String) -> Vector2:
	var actor: CombatActor=game.combat.actors.get(id)
	return Vector2(actor.x,actor.y) if actor!=null else Vector2.ZERO
func screen(value: Vector2) -> Vector2:
	return game.call("_screen_position",value.x,value.y)
func spawn(id: String, mode: String, at: Vector2, owner: String="", duration: float=0.0, direction: Vector2=Vector2.RIGHT, age: float=0.0) -> Visual:
	var definition: Dictionary=library.spells.get(id,{})
	if definition.is_empty(): return null
	var node:=Visual.new()
	node.library=library
	node.definition=definition
	node.mode=mode
	node.owner_id=owner
	node.age=age
	node.forward=direction.normalized()
	node.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	node.position=screen(at)
	node.duration=duration if duration>0 else float(library.length_frames(definition.get(mode,{})))/float(definition.fps)
	game.add_child(node)
	if mode!="projectile": effects.append(node)
	node.queue_redraw()
	return node
func handle_event(event: Dictionary) -> void:
	var id:=String(event.get("spell_id",""))
	if not library.spells.has(id): return
	var kind:=String(event.get("type",""))
	var caster:=String(event.get("caster_id",event.get("attacker_id","")))
	var target:=String(event.get("target_id",""))
	var cast: Dictionary=game.combat.active_spell_casts.get(caster,{})
	if target.is_empty(): target=String(cast.get("target_id",""))
	var source:=point(event.get("caster_point"),actor_point(caster))
	var destination:=point(event.get("target_point",cast.get("target_point")),actor_point(target))
	var age:=float(event.get("age",0.0))
	if kind=="spell_cast_started":
		var direction:=screen(destination)-screen(source)
		var caster_sprite: ActorSprite=game.actor_sprites.get(caster)
		if caster_sprite!=null:
			caster_sprite.play_attack(direction)
		spawn(id,"cast",source,caster,float(event.get("cast_time_seconds",1.8)),direction,age)
	elif kind in ["spell_cast_completed","spell_cast_failed"]:
		for node: Visual in effects.duplicate():
			if node.mode=="cast" and node.owner_id==caster:
				effects.erase(node)
				node.queue_free()
	elif kind in ["projectile_hit","projectile_blocked","spell_healed","spell_knockback","spell_area_resolved","spell_wall_created"]:
		var hit:=point(event.get("point",event.get("center",event.get("from"))),destination)
		var duration:=0.0
		if kind=="spell_wall_created": duration=float(library.spells[id].get("duration_seconds",6.0))
		spawn(id,"impact",hit,"",duration,Vector2.RIGHT,age)
func advance(delta: float) -> void:
	if not is_instance_valid(game) or game.combat==null: return
	_snapshot_age+=delta
	for node: Visual in effects.duplicate():
		if node.mode=="cast":
			var caster_sprite: Node2D=game.actor_sprites.get(node.owner_id)
			if is_instance_valid(caster_sprite):
				node.position=game.to_local(caster_sprite.global_position)
		node.age+=delta
		if node.age>=node.duration:
			effects.erase(node)
			node.queue_free()
		else: node.queue_redraw()
	var active: Dictionary=remote_projectiles if _remote else game.combat.projectiles
	var seen: Dictionary={}
	for key: String in active:
		var projectile: Variant=active[key]
		var id:=String(projectile.spell_id)
		if not library.spells.has(id) or not library.spells[id].has("projectile"): continue
		seen[key]=true
		var node: Visual=projectile_nodes.get(key)
		var pos:=Vector2(float(projectile.x),float(projectile.y))
		var motion:=Vector2(float(projectile.dx),float(projectile.dy))
		if _remote: pos+=motion*float(projectile.speed)*minf(_snapshot_age,0.1)
		if node==null:
			node=spawn(id,"projectile",pos)
			projectile_nodes[key]=node
		node.age+=delta
		node.position=screen(pos)
		node.art_offset=Vector2(0,-24)
		node.direction=library.facing(screen(pos+motion)-screen(pos))
		node.queue_redraw()
	for key: String in projectile_nodes.keys():
		if not seen.has(key):
			projectile_nodes[key].queue_free()
			projectile_nodes.erase(key)
func apply_snapshot(snapshot: Dictionary) -> void:
	_remote=true
	_snapshot_age=0.0
	remote_projectiles.clear()
	for projectile: Dictionary in snapshot.get("spell_projectiles",[]):
		remote_projectiles[String(projectile.projectile_id)]=projectile
	for event: Dictionary in snapshot.get("spell_visual_events",[]):
		var serial:=int(event.get("serial",0))
		if serial<=_last_serial: continue
		_last_serial=serial
		handle_event(event)
	advance(0.0)
