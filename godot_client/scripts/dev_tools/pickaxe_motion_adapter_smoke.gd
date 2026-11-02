extends SceneTree
## Exercises source-canvas grips and padded-body motion without actor rig state.
const MATERIALS := ["bronze", "iron", "steel", "blacksteel", "mithril", "adamantite", "runite"]
const SUPPORTS := {
	"south": Vector2(20, 22), "south-east": Vector2(20, 22),
	"east": Vector2(20, 22), "north-east": Vector2(19, 22),
	"north": Vector2(20, 22), "north-west": Vector2(19, 22),
	"west": Vector2(18, 22), "south-west": Vector2(19, 22)
}
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var socket := Node2D.new()
	socket.rotation = 0.41
	socket.position = Vector2(31, 39)
	root.add_child(socket)
	for material: String in MATERIALS:
		var item: Node2D = load("res://scenes/equipment/pickaxes/" + material + ".tscn").instantiate()
		socket.add_child(item)
		_check(item.has_method("get_weapon_profile"), material + " exposes source profile")
		_check(item.has_method("set_attachment_pose"), material + " accepts shared motion")
		if not item.has_method("get_weapon_profile") or not item.has_method("set_attachment_pose"):
			item.free()
			continue
		for direction: String in SUPPORTS:
			item.call("set_attachment_facing", direction)
			var profile: Dictionary = item.call("get_weapon_profile", direction)
			var art := item.get_node("Artwork") as Sprite2D
			var pivot: Vector2 = item.get("grip_positions")[direction]
			_check(profile.get("family") == "pickaxe", material + " family")
			_check(profile.get("texture") == art.texture, material + "/" + direction + " texture identity")
			_check(profile.get("pivot") == pivot and profile.get("support_grip") == SUPPORTS[direction], material + "/" + direction + " measured grips")
			_check(profile.get("source_scale") == 1.0 and art.scale == Vector2.ONE, material + " preserves native density")
			_check(art.position == -pivot, material + " pivots around source grip")
			var source := art.texture.get_image()
			if source.is_compressed():
				source.decompress()
			var support: Vector2 = profile.support_grip
			_check(source.get_pixelv(Vector2i(support)).a > 0.0, material + "/" + direction + " support is on shaft")
			var texture_before := art.texture
			var size_before := texture_before.get_size()
			var context := {
				"root_socket": "right_hand", "pose": {"right_hand": [31.0, 39.0]},
				"padding": Vector2(8, 8),
				"weapon_motion": {"active": true, "primary": Vector2(44, 31), "rotation": -0.7}
			}
			item.call("set_attachment_pose", context)
			_check(item.global_position.is_equal_approx(Vector2(36, 23)), material + " maps padded primary correctly through a rotated socket")
			_check(is_equal_approx(item.rotation + socket.rotation, -0.7), material + " cancels legacy socket angle")
			_check(art.position == -pivot and art.texture == texture_before and art.texture.get_size() == size_before, material + " motion retains original texture/pivot")
			context.weapon_motion = {"active": false, "primary": Vector2(99, 99), "rotation": 1.2}
			item.call("set_attachment_pose", context)
			_check(item.position == Vector2.ZERO and is_zero_approx(item.rotation + socket.rotation), material + " inactive motion restores upright ready source")
			item.position = Vector2(9, 7)
			item.call("set_attachment_pose", {})
			_check(item.position == Vector2.ZERO and is_zero_approx(item.rotation + socket.rotation), material + " missing motion clears prior transform")
		item.free()
	# Shields still retain their existing facing/upright behavior.
	var shield := Node2D.new()
	shield.set_script(load("res://scripts/equipment_visual_2d.gd"))
	var shield_art := Sprite2D.new()
	shield_art.name = "Artwork"
	shield.add_child(shield_art)
	var shield_texture := ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGBA8))
	shield.set("directional_textures", {"south": shield_texture})
	shield.set("grip_positions", {"south": Vector2.ONE})
	socket.add_child(shield)
	shield.position = Vector2(3, 4)
	if shield.has_method("set_attachment_pose"):
		shield.call("set_attachment_pose", {})
	_check(shield.position == Vector2(3, 4) and is_zero_approx(shield.rotation + socket.rotation), "shield keeps original upright behavior")
	socket.free()
	print(JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "artwork_approval": false}))
	quit(0 if failures.is_empty() else 1)


func _check(passed: bool, label: String) -> void:
	checks += 1
	if not passed:
		failures.append(label)
