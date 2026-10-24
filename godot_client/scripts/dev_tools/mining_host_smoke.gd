extends "res://scripts/dev_tools/world_host_persistence_smoke.gd"
## Use the real host/save queue with scripted HTTP only; never touch live users.

func mining_fixture(peer: int) -> Dictionary:
	var f := fixture(peer)
	var geometry := preload("res://scripts/dev_tools/mining_authority_smoke.gd").Geometry.new()
	f.host.add_child(geometry)
	var rock := MiningDeposit.new()
	rock.deposit_id = "bronze"
	rock.position = Vector2(320, 320)
	geometry.add_child(rock)
	f.region = AuthoritativeRegion.new()
	f.region.configure("outskirts", geometry)
	f.host.regions.outskirts = f.region
	f.region.add_player("stable-character", f.session.player)
	var defs := preload("res://scripts/dev_tools/mining_tool_fixture.gd").new()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mining.json"))
	data.ores[0].success.p_at_unlock = 1.0
	data.ores[0].success.p_at_mastery = 1.0
	defs.load_records(data)
	f.region.mining._defs = defs
	return f

func advance(region: AuthoritativeRegion, seconds: float) -> void:
	for _step in roundi(seconds * 30):
		region.advance(1.0 / 30.0)

func command(generation: int = 0) -> Dictionary:
	return {"type":"mine_start", "deposit_id":"bronze", "deposit_generation":generation}

func _run() -> void:
	var f := mining_fixture(1101)
	check(f.region.submit("stable-character", command()).ok, "Mining starts through region")
	advance(f.region, 3)
	check(f.session.player.backpack.get("Bronze Ore", 0) == 1, "Real grant before save")
	f.http.replies.assign([{"ok":false,"code":"unavailable"}, {"ok":true,"revision":5}, {"ok":false,"code":"stale_lease"}])
	check(not await f.host._persist(f.session), "Lost acknowledgment freezes pending reward")
	var pending: Dictionary = f.session.pending.duplicate(true)
	advance(f.region, 10)
	check(f.session.player.backpack.get("Bronze Ore", 0) == 1 and f.session.player.get_skill_experience("mining") == 121, "Freeze never replays reward")
	check(await f.host._persist(f.session), "Retry confirms original award")
	check(f.http.requests[1].body == pending, "Same operation ID, revision, ore and XP on retry")
	var restored := CharacterCodec.decode(f.session.state, "Recovered", "stable-character")
	check(restored.ok and restored.player.backpack.get("Bronze Ore", 0) == 1 and restored.player.get_skill_experience("mining") == 121, "Committed ore and XP survive reconnect")
	check(f.region.submit("stable-character", command(2)).ok, "New post-respawn session")
	check(not await f.host._persist(f.session), "Expired lease rejected")
	check(not f.region.mining.active("stable-character") and not f.region.players.has("stable-character"), "Lease loss cancels and removes ownership")
	f.host.queue_free()
	await get_tree().process_frame

	f = mining_fixture(1102)
	f.session.busy = true
	var queued := command()
	queued.sequence = 1
	f.host._command(1102, queued)
	f.host._command(1102, {"type":"move","direction":[1,0],"sequence":2})
	f.session.busy = false
	await f.host._process_commands(f.session)
	check(not f.region.mining.active("stable-character") and f.http.requests.is_empty(), "Newer movement defeats delayed Mining start")
	f.host.queue_free()
	await get_tree().process_frame

	f = mining_fixture(1103)
	f.region.submit("stable-character", command())
	f.region.frozen["stable-character"] = true
	f.session.queue.append(command())
	f.host._departed(1103)
	check(not f.region.mining.active("stable-character") and f.session.queue.is_empty(), "Disconnect cancels frozen extraction and queued restart")
	advance(f.region, 10)
	check(f.session.player.backpack.is_empty(), "Disconnect grace never rewards mining")
	f.host.queue_free()
	await get_tree().process_frame
	print("[Mining host] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
