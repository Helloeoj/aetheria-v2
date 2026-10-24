class_name ItemVisualLibrary
extends RefCounted
## Each catalog entry links an inventory image, a separate ground image and
## the existing equipped scene. New approved batches extend this registry.
const CATALOG := "res://data/item_visuals.json"
const Smithing = preload("res://scripts/smithing_catalog.gd")
static var definitions: Dictionary = {}
static var textures: Dictionary = {}
static var loaded := false

static func initialize() -> void:
	if loaded:
		return
	loaded = true
	if FileAccess.file_exists(CATALOG):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
		if data is Dictionary:
			definitions = data.get("items", {})

static func definition(item_name: String) -> Dictionary:
	initialize()
	if definitions.has(item_name):
		return definitions[item_name]
	# Generic placeholders are superseded by any authored catalog art.
	var tree := Engine.get_main_loop() as SceneTree
	var catalog := tree.root.get_node_or_null("GameData") if tree != null else null
	if catalog == null:
		return {}
	var item: Dictionary = catalog.get_item_by_name(item_name)
	var original_name := String(item.get("visual_item_name", ""))
	if definitions.has(original_name):
		return definitions[original_name]
	var icon := ""
	var family := "fishing"
	match String(item.get("type", "")):
		"Fishing Pole": icon = "rod"
		"Fishing Bait": icon = "bait"
		"Food":
			if not String(item.get("fish_species", "")).is_empty():
				icon = "fish"
		"Crafting":
			family = "smithing"
			var canonical_name := String(item.get("name", ""))
			if canonical_name.ends_with(" Ore"):
				icon = "ore"
			elif canonical_name.ends_with(" Ingot"):
				icon = "ingot"
			elif canonical_name == "Coal":
				icon = "coal"
		"Weapon", "Armor":
			icon = Smithing.category(item)
			family = "smithing"
	if icon.is_empty():
		return {}
	var path := "res://Assets/Items/placeholders/%s_%s.svg" % [family, icon]
	return {"inventory": path, "ground": path, "ground_scale": 0.45, "placeholder": true}

static func texture(item_name: String, state: String = "inventory") -> Texture2D:
	var entry := definition(item_name)
	var path := String(entry.get(state, ""))
	if path.is_empty():
		return null
	if not textures.has(path):
		if not ResourceLoader.exists(path):
			return null
		textures[path] = load(path) as Texture2D
	return textures[path] as Texture2D

static func has_ground_visual(item_name: String) -> bool:
	return texture(item_name, "ground") != null
