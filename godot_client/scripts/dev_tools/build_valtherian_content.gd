extends SceneTree
## Packs the user's exact approved map and separate canonical ore props.
const LAYOUT:="res://Assets/Maps/ValtherianMines/layout.json"
const OUTPUT:="res://scenes/ValtherianMinesContent.tscn"
const FOREGROUND=preload("res://scripts/dev_tools/valtherian_approved_layers.gd")
const DETAIL_FOREGROUND=preload("res://scripts/dev_tools/valtherian_detail_layers.gd")
func _initialize() -> void:
	_build.call_deferred()
func _build() -> void:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var mining_data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/mining.json"))
	var mining_by_prop:Dictionary={}
	for definition:Dictionary in mining_data.ores:
		mining_by_prop[definition.prop_id]=definition
	if data.is_empty():
		printerr("Missing authored Valtherian layout")
		quit(1)
		return
	var content:=Node2D.new()
	content.name="ValtherianMinesContent"
	content.y_sort_enabled=true
	content.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	content.set_meta("gameplay_grid_origin",Vector2.ZERO)
	if data.get("render_mode","")!="approved-image":
		printerr("Only the user-approved image may be installed. The modular rebuild was rejected.")
		content.free()
		quit(1)
		return
	var detail_art:Dictionary=data.get("detail_art",{})
	var art:Dictionary=data["approved_art"] if detail_art.is_empty() else detail_art
	var backdrop:=Sprite2D.new()
	backdrop.name="ApprovedMap"
	backdrop.centered=false
	backdrop.texture=load(art["texture"])
	backdrop.scale=Vector2(float(art["world_size"][0])/float(art["native_size"][0]),float(art["world_size"][1])/float(art["native_size"][1]))
	backdrop.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	backdrop.z_index=-100
	if not detail_art.is_empty():
		backdrop.material=load("res://Assets/Maps/ValtherianMines/Detail/CrispMine.tres")
	content.add_child(backdrop)
	backdrop.owner=content
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
	for section in ["ores"]:
		var folder:=Node2D.new()
		folder.name="Ores"
		folder.y_sort_enabled=true
		content.add_child(folder)
		folder.owner=content
		for record in data[section]:
			var instance:Node2D=(load(record["scene"]) as PackedScene).instantiate()
			instance.name=record["name"]
			instance.position=Vector2(record["position"][0],record["position"][1])
			folder.add_child(instance)
			instance.owner=content
			var definition:Dictionary=mining_by_prop[record.ore]
			var deposit:=MiningDeposit.new()
			deposit.name="Mining"
			deposit.deposit_id="valtherianmines/"+str(record.id)
			deposit.ore_item_id=int(definition.item_id)
			deposit.approach_offset=Vector2(record.approach_world_xy[0],record.approach_world_xy[1])-instance.position
			deposit.interaction_radius=20.0
			deposit.click_rect=Rect2(-48,-72,96,96)
			deposit.visual_path=NodePath("../Footprint/Visual")
			deposit.available_texture=load(definition.visual.available)
			deposit.depleted_texture=load(definition.visual.depleted)
			instance.add_child(deposit)
			deposit.owner=content
	var foreground:Node2D=FOREGROUND.build(data) if detail_art.is_empty() else DETAIL_FOREGROUND.build(data)
	content.add_child(foreground)
	_own(foreground,content)
	var packed:=PackedScene.new()
	var result:=packed.pack(content)
	if result==OK:
		result=ResourceSaver.save(packed,OUTPUT)
	print("Valtherian approved-image export: ",data["ores"].size()," canonical ores; ",data["void_rects"].size()," solid rectangles; result=",result)
	content.free()
	quit(result)
func _own(node:Node,scene:Node) -> void:
	node.owner=scene
	for child:Node in node.get_children():
		_own(child,scene)
