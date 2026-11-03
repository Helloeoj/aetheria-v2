extends Node
## Presents the shared encounter state; never chooses tiles, targets or damage.
const MAGIC := preload("res://scenes/Effects/TitanMagicCast.tscn")
const HAYMAKER := preload("res://scenes/Effects/TitanHaymaker.tscn")
const SPIKE := preload("res://scenes/Effects/TitanPhysicalSpike.tscn")
const ERUPTION := preload("res://scenes/Effects/TitanShadowEruption.tscn")
const SLAM := preload("res://scripts/effects/titan_slam_visual.gd")
const ORB := preload("res://Assets/Effects/TitanDarkMagic/void-orb.png")
var game: Node
var packet: Dictionary = {}
var bodies: Dictionary = {}
var tiles: Dictionary = {}
var shots: Dictionary = {}
var elapsed := 0.0
var last_serial := 0

func configure(owner_game: Node) -> void:
	game = owner_game
	process_priority = 10

func clear() -> void:
	for entry: Dictionary in bodies.values():
		if is_instance_valid(entry.actor): entry.actor.animated_sprite.show()
		if is_instance_valid(entry.node): entry.node.queue_free()
	for node: Node in tiles.values():
		if is_instance_valid(node): node.queue_free()
	for node: Node in shots.values():
		if is_instance_valid(node): node.queue_free()
	bodies.clear()
	tiles.clear()
	shots.clear()
	packet.clear()

func apply_snapshot(value: Dictionary) -> void:
	packet = value.duplicate(true)
	elapsed = 0.0
	for event: Dictionary in value.get("spell_visual_events", []):
		if int(event.get("serial", 0)) <= last_serial: continue
		last_serial = int(event.serial)
		if event.get("spell_id", "") == "titan_dark_bolt" and event.get("type", "") == "projectile_hit":
			var point: Array = event.get("point", [])
			if point.size() == 2: _impact(Vector2(float(point[0]), float(point[1])))

func handle_event(event: Dictionary) -> void:
	if event.get("type", "") == "projectile_hit" and event.get("spell_id", "") == "titan_dark_bolt":
		_impact(event.point)

func _impact(point: Vector2) -> void:
	var flash := Sprite2D.new()
	flash.texture = ORB
	flash.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	flash.position = game._screen_position(point.x, point.y) + Vector2(0, -18)
	flash.z_index = 100
	game.add_child(flash)
	var tween := flash.create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.3)
	tween.tween_callback(flash.queue_free)

func _process(delta: float) -> void:
	if not is_instance_valid(game) or game.combat == null: return
	var online := is_instance_valid(game.online_view)
	var state: Dictionary = packet if online else game.combat.titan_encounters.snapshot(game.combat)
	elapsed += delta
	var active_bodies := {}
	var active_actors := {}
	var active_tiles := {}
	for action: Dictionary in state.get("titan_actions", []):
		var id := String(action.attack_id)
		var age := float(action.age) + (elapsed if online else 0.0)
		var duration := 1.8 if action.kind == "haymaker" else 2.4
		var actor: ActorSprite = game.actor_sprites.get(String(action.caster_id))
		if age >= duration or actor == null: continue
		active_bodies[id] = true
		active_actors[actor] = true
		if not bodies.has(id):
			var node: Node2D
			if action.kind == "slam": node = SLAM.new()
			elif action.kind == "haymaker": node = HAYMAKER.instantiate()
			else: node = MAGIC.instantiate()
			actor.add_child(node)
			bodies[id] = {"actor": actor, "node": node}
		bodies[id].node.sample_at_seconds(age)
		actor.animated_sprite.hide()
		var index := 0
		for cell: Array in action.cells:
			var key := "%s_%d" % [id, index]
			index += 1
			active_tiles[key] = true
			if not tiles.has(key):
				var node: Node2D = SPIKE.instantiate() if action.kind == "slam" else ERUPTION.instantiate()
				var center: Vector2 = game.world.cell_grid.center(Vector2i(int(cell[0]), int(cell[1])))
				node.position = game._screen_position(center.x, center.y)
				game.add_child(node)
				# These live cells first appear at release and rise over one tick.
				# Keep their colour cue visible underneath the rising geometry.
				var marker := Sprite2D.new()
				marker.name = "LiveWarning"
				marker.centered = false
				marker.offset = Vector2(-24, -52)
				marker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				if action.kind == "slam":
					marker.texture = node.get_node("Visual").texture
					marker.region_enabled = true
					marker.region_rect = Rect2(144, 0, 48, 64)
				else:
					marker.texture = preload("res://Assets/Effects/TitanDarkMagic/warning-3.png")
				node.add_child(marker)
				node.move_child(marker, 0)
				tiles[key] = node
			tiles[key].sample_at_seconds(age)
			tiles[key].get_node("LiveWarning").visible = age < 1.8
	for id: String in bodies.keys():
		if active_bodies.has(id): continue
		var entry: Dictionary = bodies[id]
		if is_instance_valid(entry.actor) and not active_actors.has(entry.actor): entry.actor.animated_sprite.show()
		if is_instance_valid(entry.node): entry.node.queue_free()
		bodies.erase(id)
	for id: String in tiles.keys():
		if active_tiles.has(id): continue
		tiles[id].queue_free()
		tiles.erase(id)
	var active_shots := {}
	for shot: Dictionary in state.get("titan_projectiles", []):
		var id := String(shot.id)
		active_shots[id] = true
		if not shots.has(id):
			var orb := Sprite2D.new()
			orb.texture = ORB
			orb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			orb.z_index = 100
			game.add_child(orb)
			shots[id] = orb
		var progress := clampf(float(shot.travelled) / maxf(0.01, float(shot.initial_distance)), 0, 1)
		var lead := minf(elapsed, 0.1) if online else 0.0
		shots[id].position = game._screen_position(float(shot.x) + float(shot.dx)*float(shot.speed)*lead, float(shot.y) + float(shot.dy)*float(shot.speed)*lead) + Vector2(0, lerpf(-125, -18, progress))
	for id: String in shots.keys():
		if active_shots.has(id): continue
		shots[id].queue_free()
		shots.erase(id)
