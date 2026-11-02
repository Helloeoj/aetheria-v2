class_name CraftingPanel
extends Control

const Crafting = preload("res://scripts/crafting_service.gd")
const Shop = preload("res://scripts/shop_service.gd")

var game: Node
var station: Node2D
var content: VBoxContainer
var status: Label
var amount: SpinBox
var smithing: Control
var recipe_scroll: ScrollContainer

func configure(owner_game: Node) -> void:
	game = owner_game
	preload("res://scripts/crafting_menu_layer.gd").mount(self, game.ui_root)
	theme = FantasyUI.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	frame.offset_left = -365
	frame.offset_right = 365
	frame.offset_top = -265
	frame.offset_bottom = 265
	add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	frame.add_child(box)
	var close_button := Button.new()
	close_button.text = "Close [Esc]"
	close_button.pressed.connect(close)
	box.add_child(close_button)
	amount = SpinBox.new()
	amount.min_value = 1
	amount.max_value = 100
	amount.value = 1
	amount.prefix = "Quantity: "
	box.add_child(amount)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	var scroll := ScrollContainer.new()
	recipe_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	smithing = preload("res://scripts/ui_smithing.gd").new()
	box.add_child(smithing)
	smithing.configure(game)
	smithing.recipes_requested.connect(_show_recipes)
	hide()

func show_station(target: Node2D) -> void:
	station = target
	if not _can_use():
		return
	status.text = station.station_name
	amount.max_value = 10 if station.station_id == "furnace" else (1 if station.station_id == "anvil" else 100)
	_rebuild()
	var resume: bool = smithing.session != null and smithing.session.is_active()
	smithing.visible = resume
	recipe_scroll.visible = not resume
	amount.visible = not resume
	show()

func close() -> void:
	if smithing != null: smithing.suspend()
	hide()
	station = null
	if game != null:
		game._reset_held_movement()

func _process(_delta: float) -> void:
	if visible and not _can_use():
		close()

func _can_use() -> bool:
	return is_instance_valid(station) and station.is_available(game.player) and not game.combat.active_spell_casts.has(game.player.entity_id)

func _rebuild() -> void:
	for child: Node in content.get_children():
		content.remove_child(child)
		child.queue_free()
	if station.station_id == "bait_store":
		for item: Dictionary in Shop.stock():
			var price := int(item.get("buy_price", 0))
			var button := Button.new()
			button.text = "%s — %d gold each" % [item.name, price] if price > 0 else "%s — price awaiting decision" % item.name
			button.disabled = price <= 0
			button.pressed.connect(_purchase.bind(String(item.name)))
			content.add_child(button)
		var gold_label := Label.new()
		gold_label.text = "Gold: %d" % game.player.gold
		content.add_child(gold_label)
		return
	for recipe: Dictionary in Crafting.list_recipes(station.station_id):
		var enabled := bool(recipe.get("enabled", false))
		if station.station_id in ["furnace", "anvil"] and not enabled:
			continue
		var button := Button.new()
		button.text = String(recipe.get("name", recipe.id))
		button.set_meta("recipe_id", recipe.id)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(680, 42)
		button.disabled = not enabled
		if enabled:
			var outputs: Array = recipe.get("outputs", [])
			if not outputs.is_empty():
				button.icon = ItemVisualLibrary.texture(String(outputs[0].item))
				if button.icon == null: button.icon = FantasyUI.icon("bag")
				button.expand_icon = true
				button.add_theme_constant_override("icon_max_width", 32)
			var ingredients: Array[String] = []
			for entry: Dictionary in recipe.get("inputs", []):
				ingredients.append("%d %s" % [int(entry.quantity), entry.item])
			button.text += " — " + ", ".join(ingredients)
			if station.station_id in ["furnace", "anvil"]:
				var item := GameData.get_item_by_name(String(outputs[0].item))
				var required := SmithingRules.required_level(int(item.get("tier", 1)))
				button.text += " | Smithing %d" % required
				button.disabled = game.player.get_skill_level("smithing") < required
		else:
			button.text += " — recipe quantities not yet set"
		button.pressed.connect(_craft.bind(String(recipe.id)))
		content.add_child(button)

func _craft(recipe_id: String) -> void:
	if not _can_use():
		close()
		return
	if station.station_id in ["furnace", "anvil"]:
		var error: String = smithing.begin(game.player, station, recipe_id, int(amount.value))
		status.text = error if not error.is_empty() else station.station_name
		if error.is_empty():
			recipe_scroll.hide()
			amount.hide()
		return
	if Network.online():
		Network.send_action({"type": "craft", "station_id": str(game.get_parent().get_path_to(station)), "recipe_id": recipe_id, "quantity": int(amount.value)})
		status.text = "Crafting request sent to the server."
		return
	if not _can_use():
		close()
		return
	var result: Dictionary = Crafting.craft(game.player, recipe_id, station.station_id, int(amount.value))
	status.text = String(result.message)
	_rebuild()

func _show_recipes() -> void:
	smithing.hide()
	recipe_scroll.show()
	amount.show()
	if is_instance_valid(station): _rebuild()

func _purchase(item_name: String) -> void:
	if Network.online():
		Network.send_action({"type": "purchase", "station_id": str(game.get_parent().get_path_to(station)), "item_name": item_name, "quantity": int(amount.value)})
		status.text = "Purchase request sent to the server."
		return
	if not _can_use():
		close()
		return
	var result: Dictionary = Shop.purchase(game.player, item_name, int(amount.value))
	status.text = String(result.message)
	_rebuild()
