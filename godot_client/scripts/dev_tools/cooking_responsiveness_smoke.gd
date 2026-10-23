extends Node
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
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[Cooking responsiveness FAIL] ",text)
func sample(serial: int, phase: int = 1, state_value: int = 1) -> Dictionary:
	return {"kind":"cook","station_id":"stove","encounter_id":1,"sample_id":serial,"phase_id":phase,"prompt_id":1 if phase >= 2 else 0,"sample_time":0.2,"state":state_value,"raw_item":"Raw Reedkip","remaining":2,"elapsed":0.2,"flip_elapsed":0.0,"feedback_elapsed":0.0,"flip_window":0.8,"action_ack":0,"last_result":{}}
func _ready() -> void:
	var owner := PlayerState.new()
	owner.add_item("Raw Reedkip",2)
	var before := owner.backpack.duplicate(true)
	var xp := owner.get_skill_experience("cooking")
	var transport := Transport.new()
	add_child(transport)
	var cook := Remote.Cook.new(owner,CookingCampfire.new(),null,transport,"stove")
	cook.start("Raw Reedkip",2)
	check(cook.state == CookingSession.State.COOKING,"Start displays immediate heating feedback before network response")
	check(owner.backpack == before,"Pending start never reserves raw food locally")
	var view := Remote.Cook.new(owner,CookingCampfire.new(),null,transport,"stove")
	transport.latest_snapshot.activity = sample(1)
	view.advance(0.1)
	view.advance(0.1)
	var previous := view.elapsed
	var delayed := sample(2)
	delayed.sample_time = 0.3
	delayed.elapsed = 0.3
	transport.latest_snapshot.activity = delayed
	view.advance(1.0/60.0)
	check(view.elapsed >= previous,"Delayed 10Hz heating sample cannot rewind the newer display timer")
	delayed = sample(3,2,2)
	delayed.sample_time = 0.5
	transport.latest_snapshot.activity = delayed
	view.advance(0.0)
	var commands := transport.commands.size()
	view.flip()
	check(view.has_method("pending_action") and view.call("pending_action") == "flip","Flip displays neutral pending feedback on input before network response")
	view.flip()
	check(transport.commands.size() == commands+1,"Repeated local flip input sends once while awaiting confirmation")
	view.advance(0.25)
	var stopped := view.flip_elapsed
	view.advance(1.0)
	check(is_equal_approx(view.flip_elapsed,stopped),"Presentation stops after 250ms without a fresh sample")
	check(owner.backpack == before and owner.get_skill_experience("cooking") == xp and view.last_result.is_empty(),"Client prediction never cooks, burns or awards XP")
	for fps: int in [30,60,144]:
		for phase_state: int in [1,2,3]:
			_timer_trial(fps,phase_state,false)
			_timer_trial(fps,phase_state,true)
	_safety_checks()
	_authority_checks()
	_ambiguous_start_checks()
	_finished_start_retry_checks()
	print("[Cooking responsiveness] %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)

func _timer_trial(fps: int, phase_state: int, jitter_loss: bool) -> void:
	var transport := Transport.new()
	add_child(transport)
	var view := Remote.Cook.new(PlayerState.new(),CookingCampfire.new(),null,transport,"stove")
	var field := "elapsed" if phase_state == 1 else ("flip_elapsed" if phase_state == 2 else "feedback_elapsed")
	var initial := sample(1,phase_state,phase_state)
	initial.sample_time = 0.0
	initial[field] = 0.0
	initial.flip_window = 2.5
	transport.latest_snapshot.activity = initial
	view.sync_remote()
	var inbound: Array[Dictionary] = []
	var serial := 1
	var next_sample := 0.1
	var steps := int(fps * (0.5 if phase_state == 3 else 1.6))
	var reverse := 0
	var jumps := 0
	var moved := 0
	var max_step := 0.0
	for frame in range(steps):
		var time := float(frame+1)/fps
		if time + 0.000001 >= next_sample:
			next_sample += 0.1
			serial += 1
			if not jitter_loss or serial % 7 != 0:
				var data := sample(serial,phase_state,phase_state)
				data.sample_time = time
				data[field] = time
				data.flip_window = 2.5
				inbound.append({"at":time+((0.01 if serial%2 == 0 else 0.02) if jitter_loss else 0.1),"data":data})
		for pending: Dictionary in inbound.duplicate():
			if float(pending.at) <= time + 0.000001:
				transport.latest_snapshot.activity = pending.data
				inbound.erase(pending)
		var previous := float(view.get(field))
		view.advance(1.0/fps)
		var delta := float(view.get(field))-previous
		reverse += int(delta < -0.000001)
		jumps += int(absf(delta-1.0/fps) > 0.000001)
		moved += int(delta > 0.000001)
		max_step = maxf(max_step,delta)
	check(reverse == 0 and jumps == 0 and moved == steps,"Cooking phase %d timer remains continuous at %d FPS under delayed 10Hz samples/jitter/loss" % [phase_state,fps])
	var old_id := view._sample
	var stale := sample(old_id-1,phase_state,phase_state)
	stale[field] = 0.0
	transport.latest_snapshot.activity = stale
	view.sync_remote()
	check(view._sample == old_id,"Duplicate/out-of-order cooking samples cannot reset phase clock")
	print("[Cooking timing] %d FPS phase%d jitter/loss=%s: response <= %.2fms, %d/%d moving frames, reversals/jumps %d/%d, max step %.6fs" % [fps,phase_state,jitter_loss,1000.0/fps,moved,steps,reverse,jumps,max_step])
	transport.free()

func _safety_checks() -> void:
	var owner := PlayerState.new()
	owner.add_item("Raw Reedkip",2)
	var before := owner.backpack.duplicate(true)
	var transport := Transport.new()
	add_child(transport)
	var cook := Remote.Cook.new(owner,CookingCampfire.new(),null,transport,"stove")
	cook.start("Raw Reedkip",2)
	cook.advance(1.1)
	check(cook.state == CookingSession.State.READY and cook.pending_action().is_empty(),"Unconfirmed start times out without inventing a prompt")
	cook.start("Raw Reedkip",2)
	transport.status = "Move closer to the stove."
	cook.advance(0.01)
	check(cook.state == CookingSession.State.READY and cook.pending_action().is_empty() and cook.message == transport.status,"Server rejection clears pending start feedback")
	var view := Remote.Cook.new(owner,CookingCampfire.new(),null,transport,"stove")
	var data := sample(1,2,2)
	transport.latest_snapshot.activity = data
	view.sync_remote()
	view.flip()
	data = sample(2,3,3)
	data.sample_time = 0.3
	data.last_result = {"output":"Reedkip","burnt":false,"experience":40}
	transport.latest_snapshot.activity = data
	view.sync_remote()
	check(view.state == CookingSession.State.FEEDBACK and view.pending_action().is_empty(),"Server-confirmed feedback clears pending flip")
	data = sample(3,4,1)
	data.sample_time = 0.4
	transport.latest_snapshot.activity = data
	view.sync_remote()
	var delayed := sample(99,2,2)
	delayed.sample_time = 0.5
	transport.latest_snapshot.activity = delayed
	view.sync_remote()
	check(view.state == CookingSession.State.COOKING and view._phase == 4,"Old prompt with newer sample serial cannot resurrect a prior cooking phase")
	data = sample(4)
	data.encounter_id = 2
	data.sample_time = 0.6
	transport.latest_snapshot.activity = data
	view.sync_remote()
	transport.latest_snapshot.activity = sample(100)
	view.sync_remote()
	check(view._encounter == 2,"Prior cooking batch cannot overwrite a newer batch")
	data = sample(5)
	data.encounter_id = 2
	data.sample_time = 0.7
	data.prediction_enabled = false
	transport.latest_snapshot.activity = data
	view.sync_remote()
	var stopped := view.elapsed
	view.advance(0.1)
	check(is_equal_approx(view.elapsed,stopped),"Authority pause disables cooking extrapolation")
	view.close()
	data.sample_id = 6
	transport.latest_snapshot.activity = data
	view.advance(0.1)
	check(view.state == CookingSession.State.CANCELLED,"Close cannot be undone by delayed cooking samples")
	var disconnected := Remote.Cook.new(owner,CookingCampfire.new(),null,transport,"stove")
	transport.authenticated = false
	disconnected.advance(0.01)
	check(disconnected.state == CookingSession.State.CANCELLED,"Disconnect stops cooking speculation")
	check(owner.backpack == before and owner.get_skill_experience("cooking") == 0,"Confirmed display results and all prediction paths never mutate client inventory or XP")
	transport.free()

class StoveFixture extends Node2D:
	var enabled := true
func _authority_checks() -> void:
	var region := AuthoritativeRegion.new()
	region.configure("cooking-test",null)
	var owner := PlayerState.new()
	owner.add_item("Raw Reedkip",3)
	region.add_player("cook",owner)
	var stove := StoveFixture.new()
	add_child(stove)
	region.stations.stove = {"kind":"cook","station_id":"stove","node":stove,"x":owner.x,"y":owner.y,"range":3.0}
	check(region.submit("cook",{"type":"cook_start","station_id":"stove","item_name":"Raw Reedkip","quantity":3,"start_token":"batch-one","action_id":1}).ok,"Authority starts original cooking rules with batch identity")
	for frame in range(180): region.advance(1.0/60.0)
	var first: Dictionary = region.activities.snapshot("cook")
	check(first.state == CookingSession.State.FLIP_PENDING and first.prompt_id == 1 and first.phase_id == 2,"Only authority creates identified flip prompts at original heat-up time")
	check(int(owner.backpack.get("Raw Reedkip",0)) == 2,"Authority reserves exactly one raw fish on prompt entry")
	var flip := {"type":"cook_flip","encounter_id":first.encounter_id,"prompt_id":first.prompt_id,"action_id":2}
	check(region.submit("cook",flip).ok,"Current authoritative prompt accepts discrete flip")
	var xp := owner.get_skill_experience("cooking")
	region.submit("cook",flip)
	check(int(owner.backpack.get("Reedkip",0)) == 1 and owner.get_skill_experience("cooking") == xp and xp == 40,"Duplicate flip cannot repeat original cooked reward or XP")
	region.advance(0.65)
	for frame in range(180): region.advance(1.0/60.0)
	var second: Dictionary = region.activities.snapshot("cook")
	check(second.state == CookingSession.State.FLIP_PENDING and second.prompt_id == 2 and second.phase_id > first.phase_id,"Next fish receives a new phase and prompt identity")
	check(not region.submit("cook",flip).ok and region.activities.cooking["cook"].state == CookingSession.State.FLIP_PENDING,"Delayed duplicate flip from prior fish cannot cook the next prompt")
	check(not region.submit("cook",{"type":"cook_flip","encounter_id":first.encounter_id,"prompt_id":second.prompt_id,"action_id":3,"elapsed":0.0}).ok,"Clients cannot submit cooking success timing")
	region.advance(0.81)
	check(int(owner.backpack.get("Burnt Reedkip",0)) == 1 and owner.get_skill_experience("cooking") == xp,"Missed original 0.8s window burns on authority with no grace or extra XP")
	region.advance(0.65)
	for frame in range(180): region.advance(1.0/60.0)
	var third: Dictionary = region.activities.snapshot("cook")
	region.submit("cook",{"type":"cook_flip","encounter_id":third.encounter_id,"prompt_id":third.prompt_id,"action_id":4})
	region.advance(0.65)
	owner.add_item("Raw Reedkip",1)
	region.submit("cook",{"type":"cook_start","station_id":"stove","item_name":"Raw Reedkip","quantity":1,"start_token":"batch-two","action_id":5})
	var next: Dictionary = region.activities.snapshot("cook")
	check(next.encounter_id > third.encounter_id and next.start_token == "batch-two","New batch has a separate authority identity and echoed start token")
	check(not region.submit("cook",flip).ok,"Old batch flip cannot affect a new batch")
	stove.free()

func _ambiguous_start_checks() -> void:
	var region := AuthoritativeRegion.new()
	region.configure("ambiguous-cook",null)
	var authority := PlayerState.new()
	authority.add_item("Raw Reedkip",2)
	region.add_player("cook",authority)
	var stove := StoveFixture.new()
	add_child(stove)
	region.stations.stove = {"kind":"cook","station_id":"stove","node":stove,"x":authority.x,"y":authority.y,"range":3.0}
	var owner := PlayerState.new()
	owner.add_item("Raw Reedkip",2)
	var before := owner.backpack.duplicate(true)
	var transport := Transport.new()
	add_child(transport)
	var cook := Remote.Cook.new(owner,CookingCampfire.new(),null,transport,"stove")
	cook.start("Raw Reedkip",1)
	check(region.submit("cook",transport.commands[-1]).ok,"First cooking start is accepted while its snapshots are withheld")
	region.advance(0.6)
	region.advance(0.5)
	cook.advance(1.1)
	check(cook.state == CookingSession.State.READY,"Ambiguous cooking start times out before its first snapshot arrives")
	cook.start("Raw Reedkip",1)
	# A rejected retry must not revoke the already accepted identity.
	region.frozen["cook"] = true
	var retry: Dictionary = region.submit("cook",transport.commands[-1])
	check(not retry.ok,"Authority can reject retry during a pause while the first cooking batch remains accepted")
	region.frozen.erase("cook")
	transport.status = retry.message
	cook.advance(0.01)
	region.advance(1.0)
	region.advance(0.9)
	var accepted: Dictionary = region.activities.snapshot("cook")
	transport.latest_snapshot.activity = accepted
	cook.advance(0.01)
	check(cook.state == CookingSession.State.FLIP_PENDING and cook._encounter == int(accepted.encounter_id) and cook.pending_action().is_empty(),"Late first-batch prompt remains discoverable after timeout, retry and rejection")
	cook.flip()
	if transport.commands[-1].type == "cook_flip":
		region.submit("cook",transport.commands[-1])
	check(int(authority.backpack.get("Raw Reedkip",0)) == 1 and int(authority.backpack.get("Reedkip",0)) == 1 and authority.get_skill_experience("cooking") == 40,"Recovered original prompt resolves one reservation and one authoritative reward")
	check(owner.backpack == before and owner.get_skill_experience("cooking") == 0,"Ambiguous start recovery never changes client food or XP")
	region.advance(0.65)
	var finished: Dictionary = region.activities.snapshot("cook")
	transport.latest_snapshot.activity = finished
	cook.advance(0.0)
	cook.start("Raw Reedkip",1)
	finished.sample_id = 99999
	transport.latest_snapshot.activity = finished
	cook.advance(0.0)
	check(transport.commands[-1].start_token != accepted.start_token and cook.state == CookingSession.State.COOKING and cook.pending_action() == "start","Confirmed cooking completion permits a fresh start identity while rejecting truly prior-batch samples")
	transport.free()
	stove.free()

func _finished_start_retry_checks() -> void:
	var region := AuthoritativeRegion.new()
	region.configure("finished-unseen-cook",null)
	var owner := PlayerState.new()
	owner.add_item("Raw Reedkip",2)
	region.add_player("cook",owner)
	var stove := StoveFixture.new()
	add_child(stove)
	region.stations.stove = {"kind":"cook","station_id":"stove","node":stove,"x":owner.x,"y":owner.y,"range":3.0}
	var command := {"type":"cook_start","station_id":"stove","item_name":"Raw Reedkip","quantity":1,"start_token":"unseen-finished-batch","action_id":1}
	region.submit("cook",command)
	var accepted: Dictionary = region.activities.snapshot("cook")
	for step in range(5): region.advance(1.0)
	command.action_id = 2
	check(region.submit("cook",command).ok,"Retry of an accepted cooking identity remains discoverable after its unseen completion")
	var retry: Dictionary = region.activities.snapshot("cook")
	check(retry.encounter_id == accepted.encounter_id and retry.state == CookingSession.State.FINISHED and retry.action_ack == 2,"Retrying an unseen completed start cannot launch a second batch with the same identity")
	check(int(owner.backpack.get("Raw Reedkip",0)) == 1 and int(owner.backpack.get("Burnt Reedkip",0)) == 1 and owner.get_skill_experience("cooking") == 0,"Unseen completed-start retry neither reserves another fish nor repeats any reward")
	stove.free()
