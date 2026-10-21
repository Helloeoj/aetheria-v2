class_name GroundItemDrop
extends Node2D
## A collectible instance. Quantity is stored once and moved into the backpack
## only on collection; the equipped visual remains an independent resource.
var item_name := ""
var quantity := 1
var collected := false
var sprite: Sprite2D
var selected := false

func configure(drop_name: String, amount: int) -> GroundItemDrop:
	item_name = drop_name
	quantity = maxi(1, amount)
	name = "Drop_" + item_name.validate_node_name()
	sprite = Sprite2D.new()
	sprite.texture = ItemVisualLibrary.texture(item_name, "ground")
	if sprite.texture == null:
		sprite.texture = ItemVisualLibrary.texture(item_name)
	if sprite.texture == null:
		var catalog: Node = (Engine.get_main_loop() as SceneTree).root.get_node("GameData")
		var item: Dictionary = catalog.get_item_by_name(item_name)
		var slot := String(item.get("slot", "")) if item.get("slot", null) != null else ""
		var icon_key := "attack" if slot == "weapon" else ("defense" if slot == "shield" else ("range" if slot == "quiver" else "bag"))
		sprite.texture = FantasyUI.icon(icon_key)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2.ONE * float(ItemVisualLibrary.definition(item_name).get("ground_scale", 0.75))
	add_child(sprite)
	return self

func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()

func _draw() -> void:
	if selected and not collected:
		draw_arc(Vector2.ZERO, 15, 0, TAU, 32, FantasyUI.TEAL, 2.0)

func contains_global_point(point: Vector2) -> bool:
	if collected or sprite == null or sprite.texture == null:
		return false
	var size := sprite.texture.get_size() * sprite.scale
	return Rect2(-size * 0.5, size).has_point(to_local(point))

func take(player: Variant) -> bool:
	if collected:
		return false
	collected = true
	player.add_item(item_name, quantity)
	queue_free()
	return true
