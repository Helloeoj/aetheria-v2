extends SceneTree
func _initialize() -> void:
	var folder:String=get_script().resource_path.get_base_dir()+"/"
	var image:=Image.new()
	var error:=image.load_svg_from_string(FileAccess.get_file_as_string(folder+"tile-guide-v3.svg"))
	if error!=OK:
		printerr("Tile guide SVG failed: ",error)
		quit(1)
		return
	image.save_png(folder+"tile-guide-v3.png")
	print("Actual 32px-cell structural guide rendered: ",image.get_size(),". Not a runtime art texture.")
	quit(0)
