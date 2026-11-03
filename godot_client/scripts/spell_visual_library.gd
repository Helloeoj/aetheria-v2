extends RefCounted
## Reviewed native art only; no combat, movement or collision authority.
const MANIFEST := "res://Assets/Effects/Spells/manifest.json"
const DIRECTIONS := ["east","south-east","south","south-west","west","north-west","north","north-east"]
var spells: Dictionary = {}
var textures: Dictionary = {}
func _init() -> void:
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if parsed is Dictionary: spells=parsed.get("spells",{})
func facing(direction: Vector2) -> String:
	return DIRECTIONS[posmod(roundi(direction.angle()/(PI/4.0)),8)]
func texture(file: String) -> Texture2D:
	if not textures.has(file): textures[file]=load(file)
	return textures[file] as Texture2D
func length_frames(group: Dictionary) -> int:
	var last:=0
	for clip: Dictionary in group.get("clips",[]): last=maxi(last,int(clip.start_frame)+int(clip.frames))
	return last
func draw_clip(canvas: Node2D, clip: Dictionary, frame: int, extra: Vector2=Vector2.ZERO) -> void:
	var local:=frame-int(clip.get("start_frame",0))
	if local<0 or local>=int(clip.frames): return
	var size:=Vector2(float(clip.frame_size[0]),float(clip.frame_size[1]))
	var offset_values: Array=clip.get("offset",clip.get("offset_from_object",[0,0]))
	var offset:=Vector2(float(offset_values[0]),float(offset_values[1]))+extra
	var sheets: Array=clip.get("sheets",[clip])
	for sheet: Dictionary in sheets:
		var first:=int(sheet.get("first_frame",0))
		if local<first or local>=first+int(sheet.get("frames",clip.frames)): continue
		var index:=local-first
		var columns:=int(sheet.columns)
		var source:=Rect2(Vector2(index%columns,index/columns)*size,size)
		var image:=texture(String(sheet.file))
		if image!=null: canvas.draw_texture_rect_region(image,Rect2(offset.round(),size),source)
		return
