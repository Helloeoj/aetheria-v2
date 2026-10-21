class_name ServerWorldManager
extends RefCounted

var world := WorldDataWorld.new()
var session_manager: SessionManager

func _init(manager: SessionManager) -> void:
	session_manager = manager

func tick() -> Dictionary:
	var snapshot := world.tick()
	session_manager.broadcast(ServerMessage.new(ServerMessage.WORLD_STATE, snapshot))
	return snapshot
