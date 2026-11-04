extends RefCounted
## Visual-only detail bands: original alpha geometry and sort feet, new master RGB.
static func build(layout:Dictionary)->Node2D:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://Assets/Maps/ValtherianMines/Detail/foreground-bands.json"))
	assert(not data.is_empty(),"Missing registered Valtherian detail bands")
	var folder:=Node2D.new()
	folder.name="ApprovedForeground"
	folder.y_sort_enabled=true
	folder.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var texture:Texture2D=load("res://Assets/Maps/ValtherianMines/Detail/foreground.png")
	var material:Material=load("res://Assets/Maps/ValtherianMines/Detail/CrispMine.tres")
	var world:Array=layout.get("world_size",[6144,3328])
	var density:=Vector2(float(world[0])/8192,float(world[1])/4438)
	for record:Dictionary in data.bands:
		var original_rect:Array=record.source_rect
		var rect:Array=record.detail_source_rect
		var atlas:Array=record.atlas_rect
		var foot:=float(record.foot_source_y)
		var band:=Node2D.new()
		band.name=record.name
		band.position=Vector2(0,foot*float(world[1])/924)
		band.set_meta("approved_source_rect",original_rect)
		band.set_meta("approved_foot_source_y",foot)
		var sprite:=Sprite2D.new()
		sprite.name="ExactPixels"
		sprite.centered=false
		sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.texture=texture
		sprite.material=material
		sprite.scale=density
		sprite.position=Vector2(0,-band.position.y)
		sprite.offset=Vector2(rect[0],rect[1])
		sprite.region_enabled=true
		sprite.region_filter_clip_enabled=true
		sprite.region_rect=Rect2(atlas[0],atlas[1],atlas[2],atlas[3])
		band.add_child(sprite)
		folder.add_child(band)
	return folder
