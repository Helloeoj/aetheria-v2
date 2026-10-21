class_name FittedEquipmentBody
extends RefCounted
## Replacement body and foreground limbs are separate from equipped item art.
var visual: AnimatedSprite2D
var base: Sprite2D
var head: Sprite2D
var arms: Dictionary = {}

func configure(source: AnimatedSprite2D) -> void:
	visual = source
	base = _sprite("ArmorUnderbody")
	head = _sprite("ArmorHeadForeground")
	for side: String in ["left", "right"]:
		arms[side] = _sprite("ArmorForearm_" + side)
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

func sync(context: Dictionary, flags: Dictionary) -> void:
	reset()
	if flags.is_empty() or context.get("pose", {}).is_empty():
		return
	var pose := FittedEquipmentLibrary.frame(context)
	if pose.is_empty():
		return
	visual.self_modulate.a = 0.0
	var origin: Vector2 = context.origin - context.padding
	base.texture = FittedEquipmentLibrary.base_texture(pose, flags, context)
	base.position = origin
	base.visible = true
	head.texture = FittedEquipmentLibrary.texture(pose.head)
	head.position = origin
	head.visible = not bool(flags.get("head", false))
	if bool(flags.get("chest", false)):
		for side: String in pose.frontArms:
			# Authored armor already contains the forearm plate. Only the real
			# hand belongs above it; a neutral sleeve would cover the new art.
			arms[side].texture = FittedEquipmentLibrary.hand_texture(context, side) if bool(flags.get("authored_chest", false)) else FittedEquipmentLibrary.forearm_texture(context, side)
			arms[side].position = origin
			arms[side].visible = true
