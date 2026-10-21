class_name CharacterAttachmentRig
extends Skeleton2D

## A frame-synchronized attachment skeleton. The PixelLab PNG export has no
## bone animation, so authored pixel tracks drive these bones, not the artwork.
const POSE_PATH := "res://data/character_attachments.json"
const EQUIPMENT_PATH := "res://data/equipment_visuals.json"
const SOCKET_NAMES: Array[String] = ["chest", "head", "right_hand", "left_hand", "waist", "back"]
const RIGHT_HAND_ANGLES := {
	"south": -28.0, "south-east": -20.0, "east": 24.0, "north-east": 28.0,
	"north": 28.0, "north-west": 20.0, "west": -24.0, "south-west": -28.0
}

static var _pose_catalog: Dictionary = {}
static var _equipment_catalog: Dictionary = {}
static var _catalogs_loaded := false

var current_pose: Dictionary = {}
var current_frame_path := ""
var _current_facing := "south"
var debug_sockets := false:
	set(value):
		debug_sockets = value
		queue_redraw()

var _skin_id := ""
var _visual: AnimatedSprite2D
var _bones: Dictionary = {}
var _sockets: Dictionary = {}
var _items: Dictionary = {}
var _grip_covers: Dictionary = {}
var _fitted_body: FittedEquipmentBody


static func _load_catalogs() -> void:
	if _catalogs_loaded:
		return
	_catalogs_loaded = true
	for path: String in [POSE_PATH, EQUIPMENT_PATH]:
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			if path == POSE_PATH:
				_pose_catalog = parsed
			else:
				_equipment_catalog = parsed


func bind_to(visual: AnimatedSprite2D) -> void:
	_visual = visual
	_load_catalogs()
	_visual.frame_changed.connect(sync_pose)
	_visual.animation_changed.connect(sync_pose)
	_visual.sprite_frames_changed.connect(sync_pose)
	sync_pose()


func set_skin(skin: String) -> void:
	_skin_id = skin
	sync_pose()


func get_socket(socket_name: String) -> Marker2D:
	return _sockets.get(socket_name) as Marker2D


func get_equipped_visual(equipment_slot: String) -> Node2D:
	return _items.get(equipment_slot, {}).get("node") as Node2D


## Missing visual registrations remove the previous item without changing stats.
## Main calls this every physics tick, so unchanged items must keep their nodes.
func set_equipment(equipment: Dictionary) -> void:
	_load_catalogs()
	var definitions: Dictionary = _equipment_catalog.get("items", {})
	var active_slots: Dictionary = {}
	for slot: String in equipment:
		var item: Dictionary = equipment[slot]
		var item_name := String(item.get("name", ""))
		var definition: Dictionary = definitions.get(item_name, definitions.get(String(item.get("visual_item_name", "")), {}))
		if definition.is_empty() or not bool(definition.get("visible", true)):
			continue
		var socket_name := String(definition.get("socket", ""))
		var scene_path := String(definition.get("scene", ""))
		active_slots[slot] = true
		var signature := item_name + "|" + socket_name + "|" + scene_path
		if String(_items.get(slot, {}).get("signature", "")) == signature:
			continue
		_remove_item(slot)
		_ensure_bones()
		var socket := get_socket(socket_name)
		if socket == null or not ResourceLoader.exists(scene_path, "PackedScene"):
			continue
		var packed := load(scene_path) as PackedScene
		if packed == null:
			continue
		var instance := packed.instantiate() as Node2D
		if instance == null:
			continue
		socket.add_child(instance)
		_items[slot] = {
			"signature": signature, "node": instance, "socket": socket_name,
			"grip_cover": bool(definition.get("grip_cover", true)),
			"fitted": bool(definition.get("fitted", false))
		}
	for slot: String in _items.keys():
		if not active_slots.has(slot):
			_remove_item(slot)
	_update_item_facings()
	_update_grip_covers()
	_update_fitted_body()


func _remove_item(slot: String) -> void:
	var node := get_equipped_visual(slot)
	if is_instance_valid(node):
		node.get_parent().remove_child(node)
		node.queue_free()
	_items.erase(slot)


func _ensure_bones() -> void:
	if not _bones.is_empty():
		return
	for socket_name: String in SOCKET_NAMES:
		var bone := Bone2D.new()
		bone.name = socket_name.to_pascal_case()
		bone.set_autocalculate_length_and_angle(false)
		bone.length = 6.0
		if socket_name == "chest":
			add_child(bone)
		else:
			(_bones["chest"] as Bone2D).add_child(bone)
		var socket := Marker2D.new()
		socket.name = socket_name + "_socket"
		socket.visible = not current_pose.is_empty()
		# Draw equipment immediately before or after the body at the same Z.
		# Keeping sockets directly under the sprite makes show_behind_parent
		# apply to the character artwork, while bones retain the authored rig.
		_visual.add_child(socket)
		_bones[socket_name] = bone
		_sockets[socket_name] = socket
	for hand: String in ["right_hand", "left_hand"]:
		var cover := Sprite2D.new()
		cover.name = hand + "_grip_cover"
		cover.region_enabled = true
		cover.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		cover.visible = false
		_visual.add_child(cover)
		_grip_covers[hand] = cover


func sync_pose() -> void:
	if _fitted_body != null:
		_fitted_body.reset()
	current_pose = {}
	current_frame_path = ""
	visible = false
	for socket: Marker2D in _sockets.values():
		socket.visible = false
	for cover: Sprite2D in _grip_covers.values():
		cover.visible = false
	if _visual == null or _visual.sprite_frames == null:
		return
	var frames := _visual.sprite_frames
	if not frames.has_animation(_visual.animation) or frames.get_frame_count(_visual.animation) <= _visual.frame:
		return
	var texture := frames.get_frame_texture(_visual.animation, _visual.frame)
	if texture == null:
		return
	current_frame_path = texture.resource_path
	var skin: Dictionary = _pose_catalog.get("skins", {}).get(_skin_id, {})
	current_pose = skin.get("poses", {}).get(current_frame_path, {})
	if current_pose.is_empty():
		return
	_ensure_bones()
	# Bone coordinates are raw PNG pixels, including that frame's padding.
	position = _visual.offset - texture.get_size() * 0.5
	var chest := _pixel_point("chest")
	for socket_name: String in SOCKET_NAMES:
		var bone: Bone2D = _bones[socket_name]
		bone.position = _pixel_point(socket_name) if socket_name == "chest" else _pixel_point(socket_name) - chest
		bone.rest = bone.transform
		var socket := get_socket(socket_name)
		socket.position = position + _pixel_point(socket_name)
		socket.visible = true
	var direction := String(_visual.animation).get_slice("_", 1)
	_current_facing = direction
	var right_hand := get_socket("right_hand")
	var left_hand := get_socket("left_hand")
	right_hand.rotation_degrees = float(RIGHT_HAND_ANGLES.get(direction, 0.0))
	left_hand.rotation_degrees = -right_hand.rotation_degrees
	right_hand.show_behind_parent = direction in ["north", "north-east", "north-west", "west"]
	left_hand.show_behind_parent = direction in ["north", "north-east", "north-west", "east"]
	get_socket("back").show_behind_parent = not direction.begins_with("north")
	visible = true
	_update_item_facings()
	_update_grip_covers()
	_update_fitted_body()
	queue_redraw()


func _pixel_point(socket_name: String) -> Vector2:
	var point: Array = current_pose.get(socket_name, [0.0, 0.0])
	return Vector2(float(point[0]), float(point[1]))


func _update_item_facings() -> void:
	for entry: Dictionary in _items.values():
		var item: Node2D = entry["node"]
		if item.has_method("set_attachment_facing"):
			item.call("set_attachment_facing", _current_facing)
		if item.has_method("set_attachment_pose"):
			var context := _fitted_context()
			context["root_socket"] = entry.socket
			item.call("set_attachment_pose", context)


func _fitted_context() -> Dictionary:
	var texture: Texture2D
	if _visual != null and _visual.sprite_frames != null and _visual.sprite_frames.has_animation(_visual.animation):
		texture = _visual.sprite_frames.get_frame_texture(_visual.animation, _visual.frame)
	return {
		"pose": current_pose, "direction": _current_facing,
		"action": String(_visual.animation).get_slice("_", 0) if _visual != null else "idle",
		"frame": _visual.frame if _visual != null else 0,
		"padding": (Vector2(80, 80) - texture.get_size()) * 0.5 if texture != null else Vector2.ZERO,
		"origin": position
	}


func _update_fitted_body() -> void:
	var flags: Dictionary = {}
	for slot: String in ["head", "chest", "legs"]:
		if bool(_items.get(slot, {}).get("fitted", false)):
			flags[slot] = true
			var item_node := get_equipped_visual(slot) as FittedEquipmentVisual
			if slot == "chest" and item_node != null and item_node.authored_pose:
				flags["authored_chest"] = true
	if not flags.is_empty() and _fitted_body == null:
		_fitted_body = FittedEquipmentBody.new()
		_fitted_body.configure(_visual)
	if _fitted_body != null:
		_fitted_body.sync(_fitted_context(), flags)
	# Keep all layers at the actor's existing world Z. Only sibling draw order
	# changes, so map Y-sorting, tint and attack lunge continue to work.
	var ordered: Array = []
	if _fitted_body != null:
		ordered.append(_fitted_body.base)
	ordered.append(get_socket("waist"))
	ordered.append(get_socket("chest"))
	if _fitted_body != null:
		ordered.append_array([_fitted_body.head, _fitted_body.arms.left, _fitted_body.arms.right])
	ordered.append_array([get_socket("back"), get_socket("right_hand"), get_socket("left_hand")])
	ordered.append_array(_grip_covers.values())
	ordered.append(get_socket("head"))
	ordered.append(self)
	for node: Variant in ordered:
		if is_instance_valid(node) and node.get_parent() == _visual:
			_visual.move_child(node, -1)
	# Neck jewelry shares the chest marker but must be above the breastplate.
	var necklace := get_equipped_visual("neck")
	if is_instance_valid(necklace):
		necklace.get_parent().move_child(necklace, -1)


func _update_grip_covers() -> void:
	for hand: String in _grip_covers:
		var cover: Sprite2D = _grip_covers[hand]
		cover.visible = false
		if current_pose.is_empty() or get_socket(hand).show_behind_parent:
			continue
		for entry: Dictionary in _items.values():
			if String(entry.get("socket", "")) == hand and bool(entry.get("grip_cover", true)):
				if bool(_items.get("chest", {}).get("fitted", false)):
					var context := _fitted_context()
					cover.texture = FittedEquipmentLibrary.hand_texture(context, hand.trim_suffix("_hand"))
					cover.region_enabled = false
					cover.centered = false
					cover.position = position - Vector2(context.padding)
					cover.visible = true
					break
				# Redraw the existing five-pixel grip region above the hilt. This
				# preserves fingers without editing or duplicating source artwork.
				cover.texture = _visual.sprite_frames.get_frame_texture(_visual.animation, _visual.frame)
				cover.region_enabled = true
				cover.centered = true
				var grip := _pixel_point(hand).round()
				cover.region_rect = Rect2(grip - Vector2(2, 2), Vector2(5, 5))
				cover.position = position + grip + Vector2(0.5, 0.5)
				cover.visible = true
				break


func _draw() -> void:
	if not debug_sockets or current_pose.is_empty():
		return
	var chest := _pixel_point("chest")
	for socket_name: String in SOCKET_NAMES:
		var point := _pixel_point(socket_name)
		draw_line(chest, point, Color(0.4, 0.9, 1.0, 0.8), 0.6)
		draw_circle(point, 1.4, Color(1.0, 0.72, 0.15))
	var font := ThemeDB.fallback_font
	draw_string(font, _pixel_point("right_hand") + Vector2(-9, 7), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color.WHITE)
	draw_string(font, _pixel_point("left_hand") + Vector2(4, 7), "L", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color.WHITE)
