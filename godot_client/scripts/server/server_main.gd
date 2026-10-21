class_name ServerDemo
extends RefCounted

func run_demo() -> void:
	var session_manager := SessionManager.new()
	var world_manager := ServerWorldManager.new(session_manager)
	var local_session := session_manager.create_local_session("LocalTestPlayer")
	print("Started local session %s for %s" % [local_session.session_id, local_session.player_name])
	for _index in range(3):
		var snapshot := world_manager.tick()
		var emissions := session_manager.flush_outgoing()
		print("Tick %d processed with %d tiles available" % [snapshot.tick, world_manager.world.world_map.size()])
		for session_id: String in emissions:
			print("Session %s outgoing:" % session_id)
			for encoded: String in emissions[session_id]:
				print("[EMIT] %s" % encoded)
		OS.delay_msec(roundi(GameTickConfig.TICK_DURATION_SECONDS * 1000.0))
