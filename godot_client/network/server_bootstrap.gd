extends Node
## Dedicated exports boot the world even when double-clicked without arguments.
func _ready() -> void:
	if OS.has_feature("dedicated_server"):
		Network.mode = Network.Mode.SERVER
		get_tree().call_deferred("change_scene_to_file", "res://scenes/network/WorldServer.tscn")
