class_name SessionManager
extends RefCounted

var sessions: Dictionary = {} # session_id -> ServerSession

func create_local_session(player_name: String = "LocalHero") -> ServerSession:
	var session_id := "local-%s-%s" % [str(Time.get_ticks_usec()), str(randi())]
	var session := ServerSession.new(session_id, player_name)
	sessions[session_id] = session
	session.outgoing.append(ServerMessage.new(ServerMessage.HELLO, {
		"session_id": session_id, "player_name": player_name
	}))
	return session

func broadcast(message: ServerMessage) -> void:
	for session: ServerSession in sessions.values():
		session.outgoing.append(message)

func flush_outgoing() -> Dictionary:
	var emitted := {}
	for session_id: String in sessions:
		var session: ServerSession = sessions[session_id]
		var messages: Array[String] = []
		for message: ServerMessage in session.outgoing:
			messages.append(message.to_wire())
		emitted[session_id] = messages
		session.outgoing.clear()
	return emitted
