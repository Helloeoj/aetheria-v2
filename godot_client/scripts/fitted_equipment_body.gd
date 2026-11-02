class_name FittedEquipmentBody
extends RefCounted
## Replacement body and foreground limbs are separate from equipped item art.
var visual: AnimatedSprite2D
var base: Sprite2D
var head: Sprite2D
var arms: Dictionary = {}
var motion_body: PlayerArticulatedBody

func configure(source: AnimatedSprite2D) -> void:
	visual = source
	base = _sprite("ArmorUnderbody")
	head = _sprite("ArmorHeadForeground")
	for side: String in ["left", "right"]:
		arms[side] = _sprite("ArmorForearm_" + side)
	motion_body=PlayerArticulatedBody.new()
	motion_body.configure(source)
	reset()

func _sprite(label: String) -> Sprite2D:
	var node := Sprite2D.new()
	node.name = label
	node.centered = false
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.visible = false
	visual.add_child(node)
	return node

func reset() -> void:
	if visual == null:
		return
	visual.self_modulate.a = 1.0
	for node: Sprite2D in [base, head, arms.left, arms.right]:
		node.visible = false
	if motion_body!=null:
		motion_body.hide()

func sync(context: Dictionary, flags: Dictionary) -> void:
	reset()
	if flags.is_empty() or context.get("pose", {}).is_empty():
		return
	var pose := FittedEquipmentLibrary.frame(context)
	if pose.is_empty():
		return
	visual.self_modulate.a = 0.0
	var origin: Vector2 = context.origin - context.padding
	if bool(flags.get("motion",false)):
		# Old source draw stays suppressed; complete native head, torso, legs
		# and moving arm contours are composed from the same clock.
		base.texture=FittedEquipmentLibrary.base_texture(pose,{"replacement_chest":true,"chest":true,"legs":true,"replacement_legs":true},context)
		base.position=origin
		base.visible=true
		var idle: Dictionary=FittedEquipmentLibrary.rig_data.rigs[String(context.direction)].frames[0]
		head.texture=FittedEquipmentLibrary.head_texture(idle)
		head.position=origin+Vector2(context.weapon_motion.head_offset)
		head.visible=not bool(flags.get("head",false))
		motion_body.sync(context,flags)
		return
	base.texture = FittedEquipmentLibrary.base_texture(pose, flags, context)
	base.position = origin
	base.visible = true
	head.texture = FittedEquipmentLibrary.head_texture(pose)
	head.position = origin
	if bool(flags.get("authored_chest", false)):
		# The head is a complete independent section; align its native neck
		# anchor to this armor pose rather than stretching either section.
		head.position += FittedEquipmentLibrary.point(context.body_pose.get("headOffset",[0,0]))
	head.visible = not bool(flags.get("head", false))
	if bool(flags.get("chest", false)) or bool(flags.get("legs", false)):
		for side: String in pose.frontArms:
			# Authored armor already contains the forearm plate. Only the real
			# hand belongs above it; a neutral sleeve would cover the new art.
			arms[side].texture = FittedEquipmentLibrary.hand_texture(context, side) if bool(flags.get("authored_chest", false)) or not bool(flags.get("chest", false)) else FittedEquipmentLibrary.forearm_texture(context, side)
			arms[side].position = origin
			arms[side].visible = true
