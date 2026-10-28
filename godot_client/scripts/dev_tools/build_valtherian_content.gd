extends SceneTree
## Packs the authored native map; never infers walkability from art colours.
const FLOOR=preload("res://scripts/dev_tools/valtherian_native_floor.gd")
const LAYOUT:="res://Assets/Maps/ValtherianMines/layout.json"
const OUTPUT:="res://scenes/ValtherianMinesContent.tscn"
func _initialize() -> void:
	_build.call_deferred()
func _build() -> void:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	if data.is_empty():
		printerr("Missing authored Valtherian layout")
		quit(1)
		return
	var content:=Node2D.new()
	content.name="ValtherianMinesContent"
	content.y_sort_enabled=true
	content.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	content.set_meta("gameplay_grid_origin",Vector2.ZERO)
	var floor_layer:TileMapLayer=FLOOR.build(data["floor_cells"])
	content.add_child(floor_layer)
	floor_layer.owner=content
	var collision:=StaticBody2D.new()
	collision.name="CaveBoundary"
	collision.collision_layer=1
	collision.collision_mask=0
	collision.add_to_group("world_solid",true)
	content.add_child(collision)
	collision.owner=content
	for i in range(data["void_rects"].size()):
		var r:Array=data["void_rects"][i]
		var shape:=RectangleShape2D.new()
		shape.size=Vector2(r[2],r[3])
		var base:=CollisionShape2D.new()
		base.name="RockSolid%04d"%i
		base.position=Vector2(r[0]+r[2]*0.5,r[1]+r[3]*0.5)
		base.shape=shape
		collision.add_child(base)
		base.owner=content
	for section in ["wall_props","decor_props","ores"]:
		var folder:=Node2D.new()
		folder.name={"wall_props":"Walls","decor_props":"Decor","ores":"Ores"}[section]
		folder.y_sort_enabled=true
		content.add_child(folder)
		folder.owner=content
		for record in data[section]:
			var instance:Node2D=(load(record["scene"]) as PackedScene).instantiate()
			instance.name=record["name"]
			instance.position=Vector2(record["position"][0],record["position"][1])
			folder.add_child(instance)
			instance.owner=content
	var packed:=PackedScene.new()
	var result:=packed.pack(content)
	if result==OK:
		result=ResourceSaver.save(packed,OUTPUT)
	print("Valtherian content export: ",data["floor_cells"].size()," floor cells; ",data["wall_props"].size()," whole wall props; ",data["ores"].size()," canonical ores; ",data["void_rects"].size()," solid rectangles; result=",result)
	content.free()
	quit(result)
