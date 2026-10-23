extends Node
## Real presentation adapter with a controlled delayed transport boundary.
const Remote := preload("res://network/remote_minigame_sessions.gd")
class Transport extends Node:
	var latest_snapshot: Dictionary = {}
	var status := ""
	var authenticated := true
	var commands: Array[Dictionary] = []
	func send_action(command: Dictionary) -> bool:
		commands.append(command.duplicate(true))
		return true
var checks := 0
var failures := 0
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Fishing responsiveness FAIL] ", description)
func _ready() -> void:
	var player := PlayerState.new()
	var transport := Transport.new()
	add_child(transport)
	var session := Remote.Fish.new(player, transport, "lake")
	transport.latest_snapshot = {"activity":{"kind":"fish","station_id":"lake","state":5,
		"encounter_id":1,"sample_id":1,"input_ack":0,"action_ack":0,"elapsed":0.0,
		"fight_time":0.0,"fish_pull":0.6,"distance":40.0,"remaining":40.0,
		"lateral":0.0,"velocity":0.0,"strain":0.0,"rod":"Beginner Rod",
		"fish_id":GameData.get_item_by_name("Raw Reedkip").id,
		"fight_plan":[[60.0,0.6]],"motion":{"boundary":0.24,"limit":0.48,"reel":5.5,"control":1.2,"tolerance":1.0}}}
	session.advance(1.0 / 60.0, -1.0)
	check(session.lateral < 0.0 and session.velocity < 0.0, "Steering moves the displayed fight on the next frame before another snapshot")
	check(transport.commands.filter(func(c: Dictionary) -> bool: return c.has("steering")).size() == 1, "Changed steering sends immediately without waiting 50 ms")
	var previous := session.lateral
	session.advance(1.0 / 60.0, -1.0)
	check(session.lateral < previous, "Fight continues between 100 ms authoritative samples")
	var backpack := player.backpack.duplicate(true)
	session.advance(90.0, 1.0)
	check(session.state == FishingSession.State.FIGHT and player.backpack == backpack and session.reward_xp == 0, "Speculation never resolves terminal outcomes or rewards")
	_plan_checks()
	_authority_checks()
	for fps: int in [30,60,144]:
		_delayed_fight(fps)
		_transport_trial(fps)
		_held_input_trial(fps,false)
		_held_input_trial(fps,true)
	_action_checks()
	_recast_checks()
	_acknowledged_time_case()
	_ambiguous_start_checks()
	_persistence_checks()
	_baseline_checks()
	print("[Fishing responsiveness] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _plan_checks() -> void:
	var patterns := {}
	var authored := GameData.get_item_by_name("Raw Reedkip")
	for seed_value in range(128):
		var session := FishingSession.new(PlayerState.new())
		session.fish = authored
		session.rng.seed = seed_value
		session.prepare_fight()
		patterns[JSON.stringify(session.fight_plan)] = true
		var previous_end := 0.0
		for dart: Array in session.fight_plan:
			check(absf(float(dart[1])) >= 0.6 * float(authored.fish_strength) - 0.000001 and absf(float(dart[1])) <= float(authored.fish_strength) + 0.000001, "Prepared pulls keep original fish magnitude range")
			check(float(dart[0]) > previous_end and float(dart[0]) <= 60.0, "Plan covers bounded increasing encounter time")
			previous_end = float(dart[0])
		check(is_equal_approx(previous_end,60.0), "Complete plan covers maximum fight duration")
		var rng_state := session.rng.state
		session.state = FishingSession.State.FIGHT
		session.distance = 100.0
		session.remaining = 100.0
		session.advance(0.2)
		check(session.rng.state == rng_state, "Fight stepping does not draw RNG")
	check(patterns.size() == 128, "128 server seeds prepare 128 distinct encounters")

func _region_fixture() -> AuthoritativeRegion:
	var region := AuthoritativeRegion.new()
	region.configure("test",null)
	var owner := PlayerState.new()
	owner.add_item("Beginner Rod",1)
	owner.add_item("Low Grade Fish Food",10)
	region.add_player("fish-player",owner)
	region.stations.lake = {"node":self,"kind":"fish","station_id":"lake","x":owner.x,"y":owner.y,"range":3.0}
	return region

func _authority_checks() -> void:
	var region := _region_fixture()
	var owner: PlayerState = region.players["fish-player"]
	check(region.submit("fish-player",{"type":"fish_start","station_id":"lake","action_id":1}).ok,"Server starts owned fishing encounter")
	var first: Dictionary = region.activities.snapshot("fish-player")
	region.advance(0.2)
	check(not region.submit("fish-player",{"type":"fish_input","steering":1.0}).ok,"Input without encounter identity cannot affect any cast")
	var action := {"type":"fish_input","encounter_id":first.encounter_id,"action":"act","expected_state":1,"phase_elapsed":0.15,"action_id":2}
	check(region.submit("fish-player",action).ok,"Server validates bounded displayed meter phase")
	var session: FishingSession = region.activities.fishing["fish-player"]
	check(is_equal_approx(session.cast_power, 1.0/6.0),"Committed power equals clicked displayed phase, not later receive time")
	check(not session.fight_plan.is_empty() and session.state == FishingSession.State.CASTING,"Full encounter plan exists before cast animation")
	var food := int(owner.backpack["Low Grade Fish Food"])
	region.submit("fish-player",action)
	check(int(owner.backpack["Low Grade Fish Food"]) == food,"Duplicate release cannot spend another bait")
	var sample: Dictionary = region.activities.snapshot("fish-player")
	check(not sample.fight_plan.is_empty(),"Prepared plan is sent before hook")
	region.submit("fish-player",{"type":"fish_input","encounter_id":first.encounter_id,"plan_ack":first.encounter_id})
	check(region.activities.snapshot("fish-player").fight_plan.is_empty(),"Acknowledged full plans are not repeated at snapshot frequency")
	var xp := owner.get_skill_experience("fishing")
	session.state = FishingSession.State.FIGHT
	session.remaining = 0.0
	session.advance(1.0/60.0)
	var caught := owner.fishing_pale_count()
	var awarded := owner.get_skill_experience("fishing")
	session.advance(1.0)
	check(caught == 1 and awarded > xp and owner.fishing_pale_count() == 1 and owner.get_skill_experience("fishing") == awarded,"Authority catches and awards XP exactly once")
	region.submit("fish-player",{"type":"fish_start","station_id":"lake","action_id":3})
	check(not region.submit("fish-player",action).ok and region.activities.fishing["fish-player"].state == FishingSession.State.POWER,"Delayed prior-encounter release cannot commit newer cast")
	region.advance(0.1)
	var next: Dictionary = region.activities.snapshot("fish-player")
	check(not region.submit("fish-player",{"type":"fish_input","encounter_id":next.encounter_id,"action":"act","expected_state":1,"action_id":4,"phase_elapsed":100.0}).ok,"Forged phase far beyond authoritative clock is rejected")
	check(int(owner.backpack["Low Grade Fish Food"]) == food,"Rejected phase spends no bait")

func _fight_sample(sample: int = 1, encounter: int = 1) -> Dictionary:
	return {"kind":"fish","station_id":"lake","state":5,"encounter_id":encounter,
		"sample_id":sample,"input_ack":0,"action_ack":0,"elapsed":0.0,"fight_time":0.0,
		"fish_pull":0.6,"distance":200.0,"remaining":200.0,"lateral":0.0,"velocity":0.0,
		"strain":0.0,"rod":"Beginner Rod","fight_plan":[[60.0,0.6]],
		"motion":{"boundary":0.24,"limit":0.48,"reel":5.5,"control":1.2,"tolerance":1.0}}

func _delayed_fight(fps: int) -> void:
	var transport := Transport.new()
	add_child(transport)
	var session := Remote.Fish.new(PlayerState.new(),transport,"lake")
	transport.latest_snapshot.activity = _fight_sample()
	var changed := 0
	var between := 0
	var maximum_jump := 0.0
	var sample := 1
	# Controlled 10 Hz authoritative samples, jitter, dropped packets and duplicates.
	for frame in range(fps * 2):
		if frame > 0 and frame % maxi(1,int(fps / 10.0)) == 0 and frame % 5 != 0:
			sample += 1
			var data := _fight_sample(sample)
			data.fight_time = float(frame) / fps
			data.sample_time = data.fight_time
			data.lateral = 0.03 * sin(float(frame) / fps)
			transport.latest_snapshot.activity = data
		var previous := session.lateral
		session.advance(1.0/fps,-0.4 if frame % (fps / 2) < fps / 4 else -0.6)
		maximum_jump = maxf(maximum_jump,absf(session.lateral-previous))
		if frame % maxi(1,int(fps / 10.0)) != 0:
			between += 1
			changed += int(not is_equal_approx(session.lateral,previous))
	check(changed >= int(between * 0.80),"Fight remains continuous between snapshots at %d FPS" % fps)
	check(maximum_jump < 0.14 and session._history.size() <= 64,"Jitter/loss reconciliation remains bounded at %d FPS" % fps)
	var before_sample := session._sample
	var old := _fight_sample(before_sample-1)
	old.lateral = 0.48
	transport.latest_snapshot.activity = old
	session.sync_remote()
	check(session._sample == before_sample,"Out-of-order snapshot is rejected")
	transport.latest_snapshot.activity = _fight_sample(999,0)
	session.sync_remote()
	check(session._encounter == 1,"Prior encounter cannot resurrect its motion")
	for _frame in range(fps):
		session.advance(1.0/fps,-1.0)
	var stopped := session.lateral
	session.advance(0.1,1.0)
	check(is_equal_approx(session.lateral,stopped),"Prediction freezes after 250 ms without new authoritative samples")
	transport.latest_snapshot.activity = _fight_sample(1000)
	transport.latest_snapshot.activity.state = 6
	transport.latest_snapshot.activity.sample_time = 3.0
	transport.latest_snapshot.activity.reward_xp = 100
	session.advance(1.0/fps)
	check(session.state == FishingSession.State.CAUGHT,"Authoritative terminal state stops speculation")
	session.close()
	transport.latest_snapshot.activity = _fight_sample(1001)
	session.advance(1.0/fps)
	check(session.state == FishingSession.State.CLOSED,"Closed session cannot resurrect from delayed snapshot")
	print("[Fishing timing] %d FPS response <= %.2f ms; moving between samples %d/%d; max correction frame %.5f" % [fps,1000.0/fps,changed,between,maximum_jump])
	transport.free()

func _action_checks() -> void:
	var transport := Transport.new()
	add_child(transport)
	var session := Remote.Fish.new(PlayerState.new(),transport,"lake")
	session.act()
	check(session.state == FishingSession.State.POWER,"Cast control displays immediate local meter before server reply")
	session.advance(0.1)
	var clicked := session.power
	session.act()
	check(session.state == FishingSession.State.CASTING and is_equal_approx(session.cast_power,clicked),"Release immediately displays clicked power")
	check(transport.commands.size() == 1,"Rapid release waits for its own start identity")
	var data := _fight_sample()
	data.state = 1
	data.start_token = session._start_token
	data.action_ack = 1
	data.elapsed = 0.1
	transport.latest_snapshot.activity = data
	session.advance(0.01)
	check(transport.commands.any(func(c: Dictionary) -> bool: return c.get("action") == "act" and c.get("encounter_id") == 1),"Pending release uses server-confirmed encounter")
	data = _fight_sample(2)
	data.state = 4
	data.start_token = session._start_token
	data.action_ack = 2
	transport.latest_snapshot.activity = data
	session.advance(0.01)
	session.act()
	check(session.state == FishingSession.State.FIGHT,"Hook feedback starts on input before network acknowledgement")
	transport.authenticated = false
	session.advance(0.01)
	check(session.state == FishingSession.State.CLOSED,"Disconnect cancels speculation")
	transport.free()

class PendingHost extends "res://network/world_host.gd":
	func _ready() -> void:
		set_physics_process(false)
func _persistence_checks() -> void:
	var host := PendingHost.new()
	add_child(host)
	var region := _region_fixture()
	host.regions.test = region
	region.submit("fish-player",{"type":"fish_start","station_id":"lake","action_id":1})
	var encounter := int(region.activities.snapshot("fish-player").encounter_id)
	var session := {"character_id":"fish-player","region_id":"test","closing":false,"saving":true,"busy":true,"pending":{"save":"in flight"},"queue":[],"last_sequence":-1}
	host.sessions[1001] = session
	host._command(1001,{"type":"fish_input","sequence":1,"encounter_id":encounter,"input_id":1,"steering":-1.0})
	check(region.activities.steering.get("fish-player",{}).get("value") == -1.0 and session.queue.is_empty(),"Steering applies while simulated persistence is pending")
	host._command(1001,{"type":"fish_input","sequence":2,"encounter_id":encounter,"action":"act","expected_state":1,"action_id":2})
	check(session.queue.size() == 1 and region.activities.fishing["fish-player"].state == FishingSession.State.POWER,"Discrete release remains queued behind durable processing")
	host.free()

func _transport_trial(fps: int) -> void:
	var region := _region_fixture()
	region.submit("fish-player",{"type":"fish_start","station_id":"lake","action_id":1})
	var authority: FishingSession = region.activities.fishing["fish-player"]
	authority.fish = GameData.get_item_by_name("Raw Reedkip")
	authority.rng.seed = 98371
	authority.prepare_fight()
	authority.state = FishingSession.State.FIGHT
	authority.distance = 200.0
	authority.remaining = 200.0
	var transport := Transport.new()
	add_child(transport)
	var session := Remote.Fish.new(PlayerState.new(),transport,"lake")
	transport.latest_snapshot.activity = region.activities.snapshot("fish-player")
	var outbound: Array[Dictionary] = []
	var inbound: Array[Dictionary] = []
	var dispatched := 0
	var time := 0.0
	var next_sample := 0.1
	var snapshots := 0
	var maximum_error := 0.0
	var maximum_frame := 0.0
	var immediate_responses := 0
	for frame in range(fps * 4):
		time += 1.0/fps
		for pending: Dictionary in outbound.duplicate():
			if float(pending.at) <= time:
				region.submit("fish-player",pending.command)
				outbound.erase(pending)
		region.advance(1.0/fps)
		if time >= next_sample:
			next_sample += 0.1
			snapshots += 1
			if snapshots % 7 != 0:
				# 40-90 ms one-way jitter, one in seven samples dropped.
				inbound.append({"at":time + (0.04 if snapshots % 2 == 0 else 0.09),"data":region.activities.snapshot("fish-player")})
		for pending: Dictionary in inbound.duplicate():
			if float(pending.at) <= time:
				transport.latest_snapshot.activity = pending.data
				inbound.erase(pending)
		var input := clampf((-session.lateral * 3.0 - session.velocity * 0.7) / 1.2,-1.0,1.0)
		var previous := session.lateral
		var previous_velocity := session.velocity
		session.advance(1.0/fps,input)
		if frame == 0:
			immediate_responses = int(session.velocity != previous_velocity and session.lateral != previous)
		maximum_error = maxf(maximum_error,absf(session.lateral-authority.lateral))
		maximum_frame = maxf(maximum_frame,absf(session.lateral-previous))
		while dispatched < transport.commands.size():
			outbound.append({"at":time + 0.06,"command":transport.commands[dispatched]})
			dispatched += 1
	check(immediate_responses == 1,"Real authority trial responds on first frame with 60 ms steering transit at %d FPS" % fps)
	check(maximum_error < 0.18 and maximum_frame < 0.14,"Real authority trial bounds correction under jitter/loss at %d FPS" % fps)
	check(session._history.size() <= 64 and transport.commands.size() <= 90,"Replay and packet counts are bounded independently of render rate")
	print("[Fishing transport] %d FPS: max authority error %.5f, max frame %.5f, %d commands over 4s" % [fps,maximum_error,maximum_frame,transport.commands.size()])
	transport.free()

func _baseline_checks() -> void:
	var path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--baseline="):
			path = arg.trim_prefix("--baseline=")
	if path.is_empty():
		return
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string(path).replace("class_name FishingSession", "")
	check(script.reload() == OK,"Archived original fishing rules load for independent balance parity")
	var compared := 0
	var mismatches := 0
	for species: String in FishingSession.FISH:
		for seed_value in range(16):
			var original: RefCounted = script.new(PlayerState.new())
			var prepared := FishingSession.new(PlayerState.new())
			for session: RefCounted in [original,prepared]:
				session.fish = GameData.get_item_by_name("Raw " + species)
				session.rod = "Beginner Rod"
				session.state = 5
				session.distance = 200.0
				session.remaining = 200.0
				session.rng.seed = seed_value
			prepared.prepare_fight()
			for frame in range(3600):
				if original.state != 5 or prepared.state != 5:
					break
				var input := clampf((-original.lateral * 3.0 - original.velocity * 0.7)/1.2,-1.0,1.0)
				original.advance(1.0/60.0,input)
				prepared.advance(1.0/60.0,input)
				compared += 1
				if absf(original.lateral-prepared.lateral) > 0.000001 or absf(original.remaining-prepared.remaining) > 0.000001 or absf(original.strain-prepared.strain) > 0.000001:
					mismatches += 1
					break
			check(original.state == prepared.state and original.player.fishing_pale == prepared.player.fishing_pale and original.player.get_skill_experience("fishing") == prepared.player.get_skill_experience("fishing"),"Prepared encounter preserves original terminal outcome and reward: " + species)
	check(mismatches == 0,"Prepared encounters match archived original motion, reel and strain at server step across all fish")
	print("[Fishing baseline] %d original/prepared frame comparisons, %d mismatches" % [compared,mismatches])

func _recast_checks() -> void:
	var transport := Transport.new()
	add_child(transport)
	var session := Remote.Fish.new(PlayerState.new(),transport,"lake")
	var old := _fight_sample()
	old.state = 6
	old.action_ack = 100
	old.start_token = "previous-panel"
	transport.latest_snapshot.activity = old
	session.sync_remote()
	session.act()
	old = old.duplicate(true)
	old.sample_id = 2
	transport.latest_snapshot.activity = old
	session.advance(0.01)
	check(session.state == FishingSession.State.POWER and session._pending.size() == 1,"Previous terminal sample cannot interrupt or acknowledge a pending recast")
	transport.free()

func _held_input_trial(fps: int, outside: bool) -> void:
	var region := _region_fixture()
	region.submit("fish-player",{"type":"fish_start","station_id":"lake","action_id":1})
	var authority: FishingSession = region.activities.fishing["fish-player"]
	authority.state = FishingSession.State.FIGHT
	authority.distance = 200.0
	authority.remaining = 200.0
	authority.fight_plan = [[60.0,0.1 if outside else 0.0]]
	authority.velocity = 0.6 if outside else 0.0
	authority.lateral = 0.3 if outside else 0.0
	var transport := Transport.new()
	add_child(transport)
	var session := Remote.Fish.new(PlayerState.new(),transport,"lake")
	transport.latest_snapshot.activity = region.activities.snapshot("fish-player")
	session.sync_remote()
	var samples: Array[Dictionary] = []
	var cursor := 0
	var next_sample := 0.1
	var backwards_reel := 0
	var backwards_time := 0
	var discontinuous_strain := 0
	var discontinuous_velocity := 0
	var frames := int(fps * (0.9 if outside else 2.0))
	for frame in range(frames):
		var time := float(frame+1)/fps
		region.advance(1.0/fps)
		if time + 0.000001 >= next_sample:
			next_sample += 0.1
			samples.append({"at":time+0.1,"data":region.activities.snapshot("fish-player")})
		for sample: Dictionary in samples.duplicate():
			if float(sample.at) <= time + 0.000001:
				transport.latest_snapshot.activity = sample.data
				samples.erase(sample)
		var previous := [session.remaining,session.fight_time,session.strain,session.velocity]
		session.advance(1.0/fps,0.0)
		backwards_reel += int(session.remaining > float(previous[0]) + 0.000001 or (not outside and absf(session.remaining - float(previous[0]) + authority.reel_speed()/fps) > 0.000001))
		backwards_time += int(absf(session.fight_time-float(previous[1])-1.0/fps) > 0.000001)
		discontinuous_strain += int(absf(session.strain-float(previous[2])) > 0.8/fps+0.000001)
		discontinuous_velocity += int(absf(session.velocity-float(previous[3])) > 2.8/fps+0.000001)
		while cursor < transport.commands.size():
			region.submit("fish-player",transport.commands[cursor])
			cursor += 1
	check(backwards_reel == 0,"Held steering acknowledgements never reverse or jump displayed reeling under 100ms snapshot delay at %d FPS" % fps)
	check(backwards_time == 0,"Held steering acknowledgements preserve continuous prepared-plan fight time at %d FPS" % fps)
	check(discontinuous_strain == 0,"Delayed held-input snapshots preserve strain continuity at %d FPS" % fps)
	check(discontinuous_velocity == 0,"Delayed held-input snapshots preserve velocity continuity at %d FPS" % fps)
	print("[Fishing held input] %d FPS outside=%s: reel/time/strain/velocity discontinuities %d/%d/%d/%d" % [fps,outside,backwards_reel,backwards_time,discontinuous_strain,discontinuous_velocity])
	transport.free()

func _acknowledged_time_case() -> void:
	var transport := Transport.new()
	add_child(transport)
	var session := Remote.Fish.new(PlayerState.new(),transport,"lake")
	var data := _fight_sample()
	data.sample_time = 0.0
	data.fight_plan = [[60.0,0.0]]
	transport.latest_snapshot.activity = data
	session.advance(0.1,0.0)
	session.advance(0.1,0.0)
	data = data.duplicate(true)
	data.sample_id = 2
	data.sample_time = 0.1
	data.fight_time = 0.1
	data.remaining = 199.45
	data.input_ack = session._input_id
	transport.latest_snapshot.activity = data
	session.advance(1.0/60.0,0.0)
	check(absf(session.remaining - 198.8083333333333) < 0.000001,"Acknowledged held input still replays the 100ms after a delayed authoritative sample")
	check(absf(session.fight_time - 0.2166666666667) < 0.000001,"Prepared-plan clock includes acknowledged input intervals after sample time")
	transport.free()

func _ambiguous_start_checks() -> void:
	var region := _region_fixture()
	var authority: PlayerState = region.players["fish-player"]
	var owner := PlayerState.new()
	owner.add_item("Beginner Rod",1)
	owner.add_item("Low Grade Fish Food",5)
	var before := owner.backpack.duplicate(true)
	var transport := Transport.new()
	add_child(transport)
	var session := Remote.Fish.new(owner,transport,"lake")
	session.act()
	check(region.submit("fish-player",transport.commands[-1]).ok,"First fishing start is accepted while its snapshots are withheld")
	region.advance(0.6)
	region.advance(0.5)
	session.advance(1.1)
	check(session.state == FishingSession.State.READY,"Ambiguous fishing start times out before its first snapshot arrives")
	session.act()
	var retry: Dictionary = region.submit("fish-player",transport.commands[-1])
	check(not retry.ok,"Authority rejects fishing retry while first power phase remains active")
	transport.status = retry.message
	var accepted: Dictionary = region.activities.snapshot("fish-player")
	transport.latest_snapshot.activity = accepted
	session.advance(0.01)
	check(session._encounter == int(accepted.encounter_id) and session._pending.is_empty(),"Late first fishing encounter is discovered and confirms pending start after timeout/retry")
	session.act()
	var committed := false
	if transport.commands[-1].type == "fish_input":
		var result: Dictionary = region.submit("fish-player",JSON.parse_string(JSON.stringify(transport.commands[-1])))
		committed = result.ok
		if not committed: printerr("[Fishing ambiguous start evidence] ",result," command=",transport.commands[-1]," authority_elapsed=",region.activities.fishing["fish-player"].elapsed)
	check(committed and region.activities.fishing["fish-player"].state == FishingSession.State.CASTING and int(authority.backpack["Low Grade Fish Food"]) == 9,"Recovered original fishing phase can commit exactly one authoritative bait")
	check(owner.backpack == before and owner.get_skill_experience("fishing") == 0,"Ambiguous fishing recovery never spends bait or grants XP locally")
	region.activities.fishing["fish-player"].lose("Authority fixture ended cast.")
	var finished: Dictionary = region.activities.snapshot("fish-player")
	transport.latest_snapshot.activity = finished
	session.advance(0.0)
	session.act()
	finished.sample_id = 99999
	transport.latest_snapshot.activity = finished
	session.advance(0.0)
	check(transport.commands[-1].start_token != accepted.start_token and session.state == FishingSession.State.POWER and not session._pending.is_empty(),"Confirmed fishing completion permits a fresh start identity while rejecting truly prior-encounter samples")
	transport.free()
