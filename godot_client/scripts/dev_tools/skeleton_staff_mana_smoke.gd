extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var actor := ActorSprite.new().configure(Vector2(32,32), Color.GREEN, "staff_mana_smoke")
	root.add_child(actor)
	actor.set_skin("skeleton_acolyte")
	var effect := actor.animated_sprite.get_node_or_null("StaffCastMana") as Sprite2D
	_check(effect != null, "Acolyte needs the staff-attached mana visual")
	if effect == null:
		actor.free()
		_done()
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/skeleton_acolyte_staff_mana.json"))
	var initial_position := actor.position
	var initial_scale := actor.animated_sprite.scale
	var initial_offset := actor.animated_sprite.offset
	var initial_collision := (actor.get_node("BodyCollision") as CollisionShape2D).shape
	await process_frame
	_check(not effect.visible, "Idle must have no casting glow")
	# First texture loads can span an animation tick. Start timing after warmup.
	for warmup in range(12):
		await process_frame
	for index in CharacterSpriteLibrary.DIRECTIONS.size():
		var direction: String = CharacterSpriteLibrary.DIRECTIONS[index]
		var vector := Vector2.DOWN.rotated(-float(index)*PI/4.0)
		actor.play_attack(vector)
		actor.animated_sprite.frame = 5
		await process_frame
		await process_frame
		_check(effect.visible, direction + " needs mana during staff-aim phase")
		_check(effect.texture != null and effect.region_enabled, "Mana must use its crisp authored atlas")
		var point: Array = data["staff_tip_positions"][direction][5]
		var expected := Vector2(float(point[0])-64,float(point[1])-64) + initial_offset + Vector2(-7,-15)
		_check(effect.position == expected, direction + " mana must follow the authored staff fork, not free hand")
		_check(effect.region_rect == Rect2(14,16,14,16), "Mana must synchronize to cast pose5; observed pose%d atlas%s" % [actor.animated_sprite.frame,str(effect.region_rect)])
		_check(effect.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Mana source pixels must stay crisp")
		actor.play_attack(vector)
		await process_frame
		_check(not effect.visible, "Restart must clear previous cast glow")
		actor.animated_sprite.frame = 5
		await process_frame
		await process_frame
		actor.cancel_action()
		await process_frame
		await process_frame
		_check(not effect.visible, "Cancel must clear casting glow")
		actor.play_attack(vector)
		actor.animated_sprite.frame = 5
		await process_frame
		await process_frame
		actor.set_dead(true)
		await process_frame
		await process_frame
		_check(not effect.visible, "Death must clear a frozen casting pose")
		actor.set_dead(false)
		actor.cancel_action()
	actor.play_attack(Vector2.DOWN)
	await create_timer(1.35).timeout
	await process_frame
	_check(not effect.visible, "Normal attack completion must clear glow")
	_check(actor.position == initial_position and actor.animated_sprite.scale == initial_scale and actor.animated_sprite.offset == initial_offset, "Mana must not change actor movement, scale or feet anchor")
	_check((actor.get_node("BodyCollision") as CollisionShape2D).shape == initial_collision, "Mana must not change collision")
	for skin: String in [CharacterSpriteLibrary.default_player_skin(),"goblin_scout","skeleton_footsoldier","skeleton_captain"]:
		actor.set_skin(skin)
		_check(actor.animated_sprite.get_node_or_null("StaffCastMana") == null, "Staff fire leaked to " + skin)
	actor.free()
	_done()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _done() -> void:
	for failure in failures:
		printerr("[Skeleton staff mana] FAIL: " + failure)
	print("[Skeleton staff mana] %s %d checks" % ["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)
