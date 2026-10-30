class_name CharacterSpriteLibrary
extends RefCounted

## Build each skin once; all actors share its frame and texture resources.
## Missing directional actions use their own facing's rotation image.
const CATALOG_PATH := "res://data/character_sprites.json"
const ANIMATION_PACK_PATHS := {
	"goblin_scout": "res://data/goblin_scout_animations.json",
	"goblin_worker": "res://data/goblin_worker_animations.json",
	"goblin_warrior": "res://data/goblin_warrior_animations.json"
}
const DIRECTIONS: Array[String] = [
	"south", "south-east", "east", "north-east",
	"north", "north-west", "west", "south-west"
]

static var _catalog: Dictionary = {}
static var _catalog_loaded := false
static var _frame_cache: Dictionary = {}
static var _texture_cache: Dictionary = {}


static func get_catalog() -> Dictionary:
	if not _catalog_loaded:
		_catalog_loaded = true
		if FileAccess.file_exists(CATALOG_PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
			if parsed is Dictionary:
				_catalog = parsed
				for skin_id: String in ANIMATION_PACK_PATHS:
					_apply_animation_pack(skin_id, String(ANIMATION_PACK_PATHS[skin_id]))
	return _catalog


static func _apply_animation_pack(skin_id: String, pack_path: String) -> void:
	# Keep the original export and its import summary reproducible. These fixed
	# later packs change only their skin's clips, dimensions and action coverage.
	if not FileAccess.file_exists(pack_path):
		return
	var pack: Variant = JSON.parse_string(FileAccess.get_file_as_string(pack_path))
	if not pack is Dictionary or pack.get("skin_id", "") != skin_id:
		return
	var skin: Dictionary = _catalog.get("skins", {}).get(skin_id, {})
	if skin.is_empty():
		return
	var animations: Dictionary = pack.get("animations", {})
	skin["animations"] = animations
	var frame_sizes: Dictionary = skin.get("frame_sizes", {})
	frame_sizes.merge(pack.get("frame_sizes", {}), true)
	skin["frame_sizes"] = frame_sizes
	var coverage: Dictionary = skin.get("coverage", {})
	var animated_directions: Dictionary = {}
	for role: String in ["idle", "walk", "attack"]:
		var authored: Array[String] = []
		var by_direction: Dictionary = animations.get(role, {}).get("directions", {})
		for direction: String in DIRECTIONS:
			if not by_direction.get(direction, []).is_empty():
				authored.append(direction)
		animated_directions[role] = authored
	coverage["animated_directions"] = animated_directions
	skin["coverage"] = coverage


static func get_skin(skin: String) -> Dictionary:
	return get_catalog().get("skins", {}).get(skin, {})


static func default_player_skin() -> String:
	return String(get_catalog().get("defaults", {}).get("player", "peasant"))


static func skin_for_player(_has_sword: bool = false) -> String:
	# Retain this call signature for older callers; items now have independent
	# socket visuals. The supplied peasant_sword art remains in the F7 archive.
	return default_player_skin()


static func skin_for_monster(monster_name: String) -> String:
	return String(get_catalog().get("monster_skins", {}).get(monster_name, ""))


static func has_authored_animation(skin: String, action: String, direction: String) -> bool:
	var definition: Dictionary = get_skin(skin).get("animations", {}).get(action, {})
	var paths: Array = definition.get("directions", {}).get(direction, [])
	return not paths.is_empty()


static func animation_name(action: String, direction: String) -> StringName:
	return StringName("%s_%s" % [action, direction])


static func get_frames(skin: String) -> SpriteFrames:
	if _frame_cache.has(skin):
		return _frame_cache[skin] as SpriteFrames
	var data := get_skin(skin)
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var rotations: Dictionary = data.get("rotations", {})
	var animations: Dictionary = data.get("animations", {})
	for direction: String in DIRECTIONS:
		for action: String in ["idle", "walk", "attack"]:
			var definition: Dictionary = animations.get(action, {})
			var paths: Array = definition.get("directions", {}).get(direction, [])
			# Missing attacks get a short lunge. Idle and walk still need a pose.
			if paths.is_empty():
				if action == "attack":
					continue
				var rotation_path := String(rotations.get(direction, ""))
				if rotation_path.is_empty():
					continue
				paths = [rotation_path]
			var animation := animation_name(action, direction)
			frames.add_animation(animation)
			frames.set_animation_speed(animation, maxf(float(definition.get("fps", 10.0)), 1.0))
			frames.set_animation_loop(animation, action != "attack")
			for path: Variant in paths:
				var texture := _get_texture(String(path))
				if texture != null:
					frames.add_frame(animation, texture)
			if frames.get_frame_count(animation) == 0:
				frames.remove_animation(animation)
	_frame_cache[skin] = frames
	return frames


static func _get_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path] as Texture2D
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var texture := load(path) as Texture2D
	_texture_cache[path] = texture
	return texture
