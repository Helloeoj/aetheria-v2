extends Node
## Authored raw-fish PNGs shared by the real backpack, Fishing Pale, and ground drops.
const SPECIES := ["Reedkip", "Marlo", "Bracken", "Kessa", "Veilfin", "Lumara", "Vesper", "Moonfin", "Velora", "Sunfish"]
const ART_FOLDER := "res://Assets/Items/fish_001/inventory/"
var checks := 0
var failures: Array[String] = []
var capture_dir := ""


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_dir = argument.trim_prefix("--capture=")
	get_tree().create_timer(45.0).timeout.connect(func() -> void:
		printerr("[Fish sprites FAIL] Test timed out")
		get_tree().quit(1))
	_run.call_deferred()


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("[Fish sprites FAIL] ", description)


func check_art_assets() -> void:
	var pixel_hashes := {}
	for species: String in SPECIES:
		var raw_name := "Raw " + species
		var path := ART_FOLDER + species.to_lower() + ".png"
		var definition := ItemVisualLibrary.definition(raw_name)
		check(String(definition.get("inventory", "")) == path and not bool(definition.get("placeholder", false)), raw_name + " maps to its authored PNG instead of a placeholder")
		check(String(definition.get("ground", "")) == path and is_equal_approx(float(definition.get("ground_scale", 0.0)), 0.45), raw_name + " uses the same authored PNG on the ground at the agreed scale")
		var exists := FileAccess.file_exists(path)
		check(exists, raw_name + " PNG exists on disk")
		if not exists:
			continue
		var signature := FileAccess.get_file_as_bytes(path).slice(0, 8)
		check(signature == PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]), raw_name + " asset is an actual PNG file")
		var texture := ItemVisualLibrary.texture(raw_name)
		check(texture != null and texture.get_size() == Vector2(64, 64), raw_name + " loads as a 64 by 64 texture")
		if texture == null:
			continue
		check(ItemVisualLibrary.texture(raw_name, "ground") == texture, raw_name + " inventory and ground resolve to the identical Texture2D")
		var pixels := texture.get_image()
		var used := pixels.get_used_rect()
		check(maxi(used.size.x, used.size.y) == 40 and used.size.x > 0 and used.size.y > 0, raw_name + " has the agreed 40 pixel longest visible side")
		check(pixels.get_pixel(0, 0).a == 0.0 and pixels.get_pixel(63, 0).a == 0.0 and pixels.get_pixel(0, 63).a == 0.0 and pixels.get_pixel(63, 63).a == 0.0, raw_name + " preserves a transparent background")
		pixel_hashes[hash(pixels.get_data())] = true
		var raw_item := GameData.get_item_by_name(raw_name)
		var cooked_item := GameData.get_item_by_name(species)
		var burnt_name := "Burnt " + species
		var burnt_item := GameData.get_item_by_name(burnt_name)
		check(raw_item.get("fish_state", "") == "raw" and cooked_item.get("fish_state", "") == "cooked" and burnt_item.get("fish_state", "") == "burnt", species + " retains separate raw, cooked, and burnt catalog states")
		var cooked_texture := ItemVisualLibrary.texture(species)
		var burnt_texture := ItemVisualLibrary.texture(burnt_name)
		check(cooked_texture != null and burnt_texture != null and cooked_texture != texture and burnt_texture != texture, species + " cooked and burnt variants retain their own fallback instead of the new raw artwork")
	check(pixel_hashes.size() == 10, "All ten species have distinct authored pixel content")


func frames(count: int = 3) -> void:
	for _frame in range(count):
		await get_tree().process_frame


func inventory_buttons(menu: InventoryMenu, item_name: String) -> Array[Button]:
	var result: Array[Button] = []
	for node: Node in menu.body.find_children("*", "Button", true, false):
		if node.has_meta("inventory_slot") and String(node.get_meta("item_name", "")) == item_name:
			result.append(node as Button)
	return result


func button_texture(button: Button) -> Texture2D:
	var icons := button.find_children("*", "TextureRect", true, false)
	return icons[0].texture as Texture2D if icons.size() == 1 else null


func capture(file_name: String) -> void:
	if capture_dir.is_empty():
		return
	await frames()
	RenderingServer.force_draw(false)
	get_tree().root.get_texture().get_image().save_png(capture_dir.path_join(file_name))


func capture_art_sheet() -> void:
	if capture_dir.is_empty():
		return
	var sheet := Control.new()
	sheet.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sheet.size = Vector2(1280, 720)
	add_child(sheet)
	var background := ColorRect.new()
	background.color = FantasyUI.NAVY
	background.size = sheet.size
	sheet.add_child(background)
	var title := Label.new()
	title.text = "Fish of Aetheria"
	title.position = Vector2(56, 32)
	title.add_theme_font_override("font", FantasyUI.display_font())
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", FantasyUI.GOLD)
	sheet.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "PixelLab sprites / raw catches"
	subtitle.position = Vector2(56, 82)
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", FantasyUI.MUTED)
	sheet.add_child(subtitle)
	for index in range(SPECIES.size()):
		var card := Panel.new()
		card.position = Vector2(56 + (index % 5) * 236, 138 + floori(index / 5.0) * 240)
		card.size = Vector2(224, 220)
		card.add_theme_stylebox_override("panel", FantasyUI.box(FantasyUI.INK, Color("4a5d70")))
		sheet.add_child(card)
		var icon := TextureRect.new()
		icon.position = Vector2(48, 18)
		icon.size = Vector2(128, 128)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = ItemVisualLibrary.texture("Raw " + SPECIES[index])
		card.add_child(icon)
		var label := Label.new()
		label.text = SPECIES[index]
		label.position = Vector2(0, 160)
		label.size = Vector2(224, 32)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", FantasyUI.display_font())
		label.add_theme_font_size_override("font_size", 24)
		label.add_theme_color_override("font_color", FantasyUI.IVORY)
		card.add_child(label)
		var grade := Label.new()
		var bait_grade := int(GameData.get_item_by_name("Raw " + SPECIES[index]).get("required_bait_grade", 1))
		grade.text = ["Low grade", "Medium grade", "High grade"][bait_grade - 1]
		grade.position = Vector2(0, 192)
		grade.size = Vector2(224, 20)
		grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grade.add_theme_font_size_override("font_size", 14)
		grade.add_theme_color_override("font_color", FantasyUI.MUTED)
		card.add_child(grade)
	await capture("fish-sprites-roster.png")
	sheet.free()


func check_runtime_visuals() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	var scene := (load("res://scenes/EastOutskirtsLayered.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	await frames(6)
	await get_tree().physics_frame
	var game: Node = scene.get_node("Combat")
	var player: PlayerState = game.player
	var panel: FishingPanel = game.fishing_panel
	var menu: InventoryMenu = game.inventory_menu
	player.backpack.clear()
	for species: String in SPECIES:
		player.add_item("Raw " + species)
	player.add_item("Raw Reedkip")
	menu.show()
	menu.select_page(InventoryMenu.Page.INVENTORY)
	await frames()
	var backpack_textures := {}
	for species: String in SPECIES:
		var raw_name := "Raw " + species
		var buttons := inventory_buttons(menu, raw_name)
		var shared_texture := ItemVisualLibrary.texture(raw_name)
		var all_match := not buttons.is_empty() and shared_texture != null
		for button: Button in buttons:
			all_match = all_match and button_texture(button) == shared_texture
		check(all_match, raw_name + " backpack cards display the authored texture")
		backpack_textures[raw_name] = shared_texture
	var duplicates := inventory_buttons(menu, "Raw Reedkip")
	check(duplicates.size() == 2 and duplicates[0] != duplicates[1] and int(duplicates[0].get_meta("inventory_slot")) != int(duplicates[1].get_meta("inventory_slot")), "Duplicate raw fish retain separate backpack cards and slot identities")
	var no_stack_labels := true
	for button: Button in duplicates:
		for label: Label in button.find_children("*", "Label", true, false):
			no_stack_labels = no_stack_labels and not label.text.begins_with("×")
	check(no_stack_labels, "Authored fish cards do not gain a stack count")
	await capture("fish-sprites-backpack.png")
	menu.hide()
	game.start_fishing_test()
	for index in range(9):
		player.store_fishing_catch("Raw " + SPECIES[index])
	await frames()
	check(panel.visible and panel.pale_slots.size() == 9 and player.fishing_pale_count() == 9, "The real fishing panel renders nine occupied pale slots")
	for slot in range(9):
		var raw_name: String = "Raw " + SPECIES[slot]
		check(panel.pale_slots[slot].icon == backpack_textures[raw_name] and panel.pale_slots[slot].icon != null, "Pale slot %d shares the exact backpack Texture2D for %s" % [slot, raw_name])
	await capture("fish-sprites-pale.png")
	var xp_before := player.get_skill_experience("fishing")
	panel.move_pale_catch(0, "Raw Reedkip")
	check(int(player.backpack.get("Raw Reedkip", 0)) == 3 and player.fishing_pale[0].is_empty(), "Moving an authored fish transfers one item without replacing its species")
	player.store_fishing_catch("Raw Sunfish")
	await frames()
	check(panel.pale_slots[0].icon == backpack_textures["Raw Sunfish"] and panel.pale_slots[0].icon != null, "The tenth species also shares its exact backpack texture in the pale")
	player.remove_fishing_catch(1, "Raw Marlo")
	player.store_fishing_catch("Raw Sunfish")
	await frames()
	check(player.fishing_pale[0] == "Raw Sunfish" and player.fishing_pale[1] == "Raw Sunfish" and panel.pale_slots[0] != panel.pale_slots[1] and panel.pale_slots[0].icon == panel.pale_slots[1].icon, "Duplicate species use separate pale buttons while sharing the image resource")
	var drops_before: int = game.ground_drops.size()
	var sunfish_before := int(player.backpack.get("Raw Sunfish", 0))
	check(game.drop_fishing_pale_item(0, "Raw Sunfish"), "An authored raw fish can be dropped from the pale")
	check(player.fishing_pale[0].is_empty() and player.fishing_pale[1] == "Raw Sunfish" and game.ground_drops.size() == drops_before + 1, "Dropping a duplicate removes exactly its selected pale slot")
	if game.ground_drops.size() > drops_before:
		var drop: GroundItemDrop = game.ground_drops.back()
		check(drop.item_name == "Raw Sunfish" and drop.quantity == 1 and drop.sprite.texture == backpack_textures["Raw Sunfish"], "The real ground drop keeps the raw item and its exact inventory texture")
		check(drop.sprite.scale.is_equal_approx(Vector2.ONE * 0.45) and drop.sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Ground fish use the agreed scale and preserve pixel filtering")
		check(int(player.backpack.get("Raw Sunfish", 0)) == sunfish_before, "Dropping does not create an extra backpack copy")
		check(game._collect_ground_drop(drop) and int(player.backpack.get("Raw Sunfish", 0)) == sunfish_before + 1, "Picking up the authored fish restores exactly one raw item")
		check(not game._collect_ground_drop(drop), "The same authored drop cannot be collected twice")
	check(int(player.backpack.get("Sunfish", 0)) == 0 and int(player.backpack.get("Burnt Sunfish", 0)) == 0, "Art, pale transfers, and pickup do not convert raw fish into cooked or burnt items")
	check(player.get_skill_experience("fishing") == xp_before, "Visual integration and transfers do not award fishing XP")
	panel.close()
	menu.show()
	menu.select_page(InventoryMenu.Page.INVENTORY)
	await frames()
	var sunfish_cards := inventory_buttons(menu, "Raw Sunfish")
	var textures_preserved := sunfish_cards.size() == sunfish_before + 1
	for button: Button in sunfish_cards:
		textures_preserved = textures_preserved and button_texture(button) == backpack_textures["Raw Sunfish"]
	check(textures_preserved, "Pickup rebuilds individual backpack cards with the same authored texture")
	check(game.is_physics_processing() and panel.is_processing(), "Visual UI checks retain normal runtime processing")
	scene.free()


func _run() -> void:
	check_art_assets()
	await check_runtime_visuals()
	await capture_art_sheet()
	print("[Fish sprites] %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
