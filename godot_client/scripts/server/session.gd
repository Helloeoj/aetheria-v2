class_name ServerSession
extends RefCounted

var session_id := ""
var player_name := ""
var outgoing: Array[ServerMessage] = []

func _init(id: String = "", name: String = "") -> void:
	session_id = id
	player_name = name
