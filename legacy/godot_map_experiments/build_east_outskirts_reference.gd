extends SceneTree

const GRID := Vector2i(32, 32)
const IMAGE_PATH := "res://Assets/Reference/EastOutskirtsLayoutReference.png"
const TILESET_PATH := "res://Assets/Tilesets/EastOutskirtsReferenceTileset.tres"
const SCENE_PATH := "res://scenes/EastOutskirtsBlockout.tscn"
const WORLD_LAYER := 1

var scene_root: Node2D

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	var texture := load(IMAGE_PATH) as Texture2D
	if texture == null:
		push_error("Could not load reference image: " + IMAGE_PATH)
		quit(1)
		return
	if texture.get_width() % GRID.x != 0 or texture.get_height() % GRID.y != 0:
		push_error("Reference image dimensions are not divisible by 32.")
		quit(1)
		return

	var columns := texture.get_width() / GRID.x
	var rows := texture.get_height() / GRID.y
	var atlas := TileSetAtlasSource.new()
	atlas.texture = texture
	atlas.texture_region_size = GRID
	for y in range(rows):
		for x in range(columns):
			atlas.create_tile(Vector2i(x, y))

	var tileset := TileSet.new()
	tileset.tile_size = GRID
	tileset.add_source(atlas, 0)
	var tileset_error := ResourceSaver.save(tileset, TILESET_PATH)
	if tileset_error != OK:
		push_error("Could not save reference TileSet: %s" % error_string(tileset_error))
		quit(1)
		return
	var saved_tileset := load(TILESET_PATH) as TileSet

	scene_root = Node2D.new()
	scene_root.name = "EastOutskirtsBlockout"
	scene_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	var ground := TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = saved_tileset
	scene_root.add_child(ground)
	ground.owner = scene_root
	for y in range(rows):
		for x in range(columns):
			ground.set_cell(Vector2i(x, y), 0, Vector2i(x, y))

	var water := _new_blocker("WaterCollision")
	scene_root.add_child(water)
	water.owner = scene_root
	_add_polygon(water, "RiverWater", [
		Vector2(1262, -16), Vector2(1552, -16), Vector2(1552, 1040),
		Vector2(1434, 1040), Vector2(1418, 985), Vector2(1392, 928),
		Vector2(1370, 860), Vector2(1349, 790), Vector2(1330, 716),
		Vector2(1310, 642), Vector2(1298, 570), Vector2(1288, 500),
		Vector2(1280, 432), Vector2(1271, 360), Vector2(1266, 288),
		Vector2(1262, 215), Vector2(1258, 140), Vector2(1255, 70)
	])

	var walls := _new_blocker("WallCollision")
	scene_root.add_child(walls)
	walls.owner = scene_root
	_add_rect(walls, "NorthVerticalRampart", Vector2(181, 195), Vector2(106, 390))
	_add_rect(walls, "SouthVerticalRampart", Vector2(184, 763), Vector2(112, 522))
	_add_rect(walls, "GatehouseNorthWing", Vector2(62, 405), Vector2(124, 48))
	_add_rect(walls, "GatehouseSouthWing", Vector2(62, 529), Vector2(124, 54))

	var trees := _new_blocker("TreeTrunkCollision")
	scene_root.add_child(trees)
	trees.owner = scene_root
	_add_circle(trees, "WestEdgeTreeTrunk", Vector2(42, 77), 18)
	_add_circle(trees, "NorthwestGroveTrunk", Vector2(535, 191), 20)
	_add_circle(trees, "NortheastTreeTrunk", Vector2(991, 111), 19)
	_add_circle(trees, "SouthwestGroveTrunk", Vector2(414, 913), 21)
	_add_circle(trees, "SoutheastTreeTrunk", Vector2(1382, 911), 20)

	var rocks := _new_blocker("RockCollision")
	scene_root.add_child(rocks)
	rocks.owner = scene_root
	_add_circle(rocks, "LargeFieldBoulder", Vector2(1049, 917), 21)
	_add_circle(rocks, "NorthShoreRock", Vector2(1260, 67), 9)
	_add_circle(rocks, "UpperShoreRock", Vector2(1271, 263), 9)
	_add_circle(rocks, "MiddleShoreRock", Vector2(1299, 449), 9)
	_add_circle(rocks, "LowerShoreRock", Vector2(1340, 683), 10)
	_add_circle(rocks, "SouthShoreRock", Vector2(1406, 930), 10)

	var camera := Camera2D.new()
	camera.name = "ReferenceCamera"
	camera.position = Vector2(texture.get_width(), texture.get_height()) * 0.5
	camera.zoom = Vector2(0.68, 0.68)
	camera.enabled = true
	scene_root.add_child(camera)
	camera.owner = scene_root

	var packed := PackedScene.new()
	var pack_error := packed.pack(scene_root)
	if pack_error != OK:
		push_error("Could not pack scene: %s" % error_string(pack_error))
		quit(1)
		return
	var scene_error := ResourceSaver.save(packed, SCENE_PATH)
	if scene_error != OK:
		push_error("Could not save scene: %s" % error_string(scene_error))
		quit(1)
		return

	print("Saved %d x %d 32px ground cells with separate river, wall, tree-trunk, and rock collision layers." % [columns, rows])
	scene_root.free()
	quit()

func _new_blocker(node_name: String) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = node_name
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	body.add_to_group("world_solid")
	return body

func _add_rect(body: StaticBody2D, node_name: String, center: Vector2, size: Vector2) -> void:
	var collision := CollisionShape2D.new()
	collision.name = node_name
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	collision.shape = rectangle
	collision.position = center
	body.add_child(collision)
	collision.owner = scene_root

func _add_circle(body: StaticBody2D, node_name: String, center: Vector2, radius: float) -> void:
	var collision := CollisionShape2D.new()
	collision.name = node_name
	var circle := CircleShape2D.new()
	circle.radius = radius
	collision.shape = circle
	collision.position = center
	body.add_child(collision)
	collision.owner = scene_root

func _add_polygon(body: StaticBody2D, node_name: String, points: Array[Vector2]) -> void:
	var collision := CollisionPolygon2D.new()
	collision.name = node_name
	collision.polygon = PackedVector2Array(points)
	body.add_child(collision)
	collision.owner = scene_root