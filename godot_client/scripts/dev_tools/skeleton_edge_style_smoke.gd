extends SceneTree

const SKELETONS := ["skeleton_footsoldier", "skeleton_knight", "skeleton_acolyte", "skeleton_captain"]
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var actor := ActorSprite.new().configure(Vector2(32,32), Color.GREEN, "edge_style_smoke")
	root.add_child(actor)
	var shape_before := (actor.get_node("BodyCollision") as CollisionShape2D).shape
	var shared_material: Material
	for skin: String in SKELETONS:
		actor.set_skin(skin)
		var data := CharacterSpriteLibrary.get_skin(skin)
		var dimensions: Array = data["size"]
		var foot: Array = data["foot_position"]
		var expected_scale := float(data["display_height"]) / float(dimensions[1])
		_check(actor.animated_sprite.material is ShaderMaterial, skin + " must use approved edge smoothing")
		if actor.animated_sprite.material is ShaderMaterial:
			var material := actor.animated_sprite.material as ShaderMaterial
			_check(material.shader != null, skin + " needs the edge shader")
			if shared_material == null:
				shared_material = material
			_check(material == shared_material, "Skeletons must share one material")
		_check(actor.animated_sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Source sampling must stay nearest")
		_check(actor.animated_sprite.scale.is_equal_approx(Vector2.ONE*expected_scale), skin + " scale changed")
		_check(actor.animated_sprite.offset == Vector2(float(dimensions[0])*0.5-float(foot[0]),float(dimensions[1])*0.5-float(foot[1])), skin + " feet anchor changed")
		_check((actor.get_node("BodyCollision") as CollisionShape2D).shape == shape_before, "Smoothing must not change collision")
		var frames := actor.animated_sprite.sprite_frames
		_check(frames == CharacterSpriteLibrary.get_frames(skin), "Smoothing must retain authored frame resources")
		for next_skin: String in [CharacterSpriteLibrary.default_player_skin(), "goblin_scout", "goblin_worker", "goblin_warrior", "missing_skin"]:
			actor.set_skin(next_skin)
			_check(actor.animated_sprite.material == null, "Skeleton material leaked to " + next_skin)
			actor.set_skin(skin)
			_check(actor.animated_sprite.material == shared_material and shared_material != null, "Skeleton material not restored after skin reuse")
	actor.free()
	for failure in failures:
		printerr("[Skeleton edge style] FAIL: " + failure)
	print("[Skeleton edge style] %s %d checks" % ["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
