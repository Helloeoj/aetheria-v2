extends RefCounted
## Regression adapter: drive real sessions where older tests expected instant
## exchanges. The focused UI/authority suites separately test real inputs/time.
static func craft(player: PlayerState, id: String, station: String, quantity: int = 1) -> Dictionary:
	if station not in ["anvil", "furnace"]: return CraftingService.craft(player, id, station, quantity)
	var preview := CraftingService.prepare_exchange(player, id, station, quantity)
	if not preview.ok: return preview
	var fixture := CraftingStation.new()
	fixture.setup(station, station, player.get_position())
	var count := quantity if station == "anvil" else 1
	for index in range(count):
		var session := SmithingSession.new(player, fixture)
		var error := session.start(id, 1 if station == "anvil" else quantity)
		if not error.is_empty():
			fixture.free()
			return {"ok":false, "message":error}
		finish(session)
		if session.state != SmithingSession.State.FINISHED:
			session.cancel()
			fixture.free()
			return {"ok":false, "message":session.message}
	fixture.free()
	return {"ok":true, "message":"Completed Smithing through a session."}

static func finish(session: SmithingSession) -> void:
	if session.state == SmithingSession.State.SMELTING:
		session.config.cooling_per_second = 0.0
		session.temperature = 0.6
		session.advance(session.duration + 0.1)
	while session.state == SmithingSession.State.FORGING: session.strike(session.target_position())
	if session.state == SmithingSession.State.QUENCHING: session.advance(session.quench_duration())

static func finish_server(region: AuthoritativeRegion, player: PlayerState) -> void:
	if not region.activities.smithing.sessions.has(player.entity_id): return
	var session: SmithingSession = region.activities.smithing.sessions[player.entity_id]
	var meta: Dictionary = region.activities.smithing.metadata[player.entity_id]
	var action := int(meta.action)
	while session.state == SmithingSession.State.FORGING:
		action += 1
		var point := session.target_position()
		region.submit(player.entity_id, {"type":"smith_strike", "encounter_id":meta.encounter, "action_id":action, "target_index":session.target_serial, "x":point.x, "y":point.y, "aspect":2.5})
	if session.state == SmithingSession.State.SMELTING:
		session.config.cooling_per_second = 0.0
		session.temperature = 0.6
	for index in range(32):
		if not session.is_active(): break
		region.advance(1.0)
