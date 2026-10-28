extends SceneTree
## Copies whole native objects. No resampling, colour or alpha edits.
func _initialize() -> void:
	var arguments:=OS.get_cmdline_user_args()
	if arguments.size()!=1:
		printerr("Supply an outside-repository export directory after --")
		quit(1)
		return
	var folder:String=arguments[0]
	DirAccess.make_dir_recursive_absolute(folder)
	var directory:String=get_script().resource_path.get_base_dir()
	var source:=Image.load_from_file(directory.path_join("wall-sheet-v2.png"))
	var regions:=[Rect2i(0,0,560,512),Rect2i(560,0,504,512),Rect2i(1064,0,472,512),Rect2i(0,512,632,512),Rect2i(632,512,408,512),Rect2i(1040,512,496,512)]
	for i in range(regions.size()):
		var rectangle:Rect2i=regions[i]
		var result:=source.get_region(rectangle).save_png(folder.path_join("wall-%02d.raw.png"%i))
		if result!=OK:
			quit(result)
			return
	print("Exported six intact native objects for PixelLab alpha cleanup.")
	quit(0)
