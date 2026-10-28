extends SceneTree
func _initialize() -> void:
	var directory:String=get_script().resource_path.get_base_dir()
	var source:=Image.new()
	var result:=source.load_svg_from_string(FileAccess.get_file_as_string(directory.path_join("native-material-proof-guide-v1.svg")))
	if result!=OK:
		quit(1)
		return
	result=source.save_png(directory.path_join("native-material-proof-guide-v1.png"))
	print("Native material proof guide: ",source.get_size(),"; render result ",result)
	quit(result)
