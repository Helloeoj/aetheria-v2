extends Node

class Geometry extends Node2D:
	var map_origin := Vector2.ZERO
	var map_height := 640
	var world := WorldState.new()

var checks := 0
var failures := 0
var region: AuthoritativeRegion
var geometry: Node2D

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("[Mining authority FAIL] ", label)

func _ready() -> void:
	_run.call_deferred()

func fixture(tool_fixture: bool = true) -> void:
	if geometry != null:
		geometry.free()
	geometry = Geometry.new()
	add_child(geometry)
	var rock := MiningDeposit.new()
	rock.deposit_id = "bronze"
	rock.position = Vector2(320, 320)
	geometry.add_child(rock)
	region = AuthoritativeRegion.new()
	region.configure("test", geometry)
	if tool_fixture:
		var defs := preload("res://scripts/dev_tools/mining_tool_fixture.gd").new()
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mining.json"))
		data.ores[0].success.p_at_unlock = 1.0
		data.ores[0].success.p_at_mastery = 1.0
		defs.load_records(data)
		region.mining._defs = defs
	for id: String in ["a", "b"]:
		region.add_player(id, PlayerState.new(id))

func begin(id: String = "a", generation: int = 0) -> Dictionary:
	return region.submit(id, {"type": "mine_start", "deposit_id": "bronze", "deposit_generation": generation})

func advance(seconds: float) -> void:
	for _i in roundi(seconds * 30):
		region.advance(1.0 / 30.0)

func _run() -> void:
	if not AuthoritativeRegion.SCHEMA.has("mine_start"):
		check(false, "Region supports authoritative Mining intent")
	else:
		_tests()
	if geometry != null:
		geometry.free()
	print("[Mining authority] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _tests() -> void:
	fixture(false)
	check(not begin().ok, "Production rejects absent pickaxe catalog")
	fixture()
	for field: String in ["xp", "item_id", "probability", "interval", "tool_item_id", "elapsed"]:
		var forged := {"type":"mine_start", "deposit_id":"bronze", "deposit_generation":0}
		forged[field] = 1
		check(not region.submit("a", forged).ok, "Reject client-controlled " + field)
	check(not region.submit("a", {"type":"mine_start", "deposit_id":"bronze", "deposit_generation":0.5}).ok, "Reject fractional generation")
	check(not region.submit("a", {"type":"mine_start", "deposit_id":"other-region", "deposit_generation":0}).ok, "Reject unknown/wrong-region node")
	check(not region.submit("a", {"type":"mine_start", "deposit_id":"bronze"}).ok, "Require explicit generation")
	region.players.a.x = 40
	check(not begin().ok, "Reject distant player")
	region.players.a.x = 10
	region.world.terrain_collision_handler = func(_a: Vector2, _b: Vector2) -> Dictionary: return {"blocked":true}
	check(not begin().ok, "Reject blocked interaction")
	region.world.terrain_collision_handler = Callable()
	check(begin().ok and begin("b").ok, "Both eligible miners start one shared deposit")
	var snapshot := region.snapshot("a")
	check(snapshot.deposits.size() == 1 and snapshot.activity.kind == "mine" and snapshot.actors[0].gathering.kind == "mine", "Public and private authoritative snapshots")
	advance(2.9)
	check(region.players.a.backpack.is_empty() and region.players.b.backpack.is_empty(), "Region advances Mining once, not once per player")
	advance(0.1)
	check(int(region.players.a.backpack.get("Bronze Ore", 0)) + int(region.players.b.backpack.get("Bronze Ore", 0)) == 1, "One shared winner")
	check(region.players.a.get_skill_experience("mining") + region.players.b.get_skill_experience("mining") == 121, "One real XP grant")
	check(region.snapshot("").deposits[0].state == "depleted" and not region.activities.active("a") and not region.activities.active("b"), "Late join sees depletion; all miners stopped")
	advance(4)
	check(begin("a", 2).ok and not begin("b", 0).ok, "Shared respawn rejects old generation")

	for command: Dictionary in [{"type":"move","direction":[1,0]}, {"type":"walk","x":11,"y":10},
		{"type":"target","target_id":""}, {"type":"attack","target_id":""},
		{"type":"cast","spell_id":"missing"}, {"type":"mine_stop"}, {"type":"fish_start"}, {"type":"cook_start"}]:
		fixture()
		begin()
		region.submit("a", command)
		check(not region.activities.active("a"), "New action cancels Mining: " + String(command.type))
	fixture()
	begin()
	region._handle_events([{"type":"entity_hit","target_id":"a","damage":1}])
	check(not region.activities.active("a"), "Damage cancels even if HP was restored in the same step")
	fixture()
	begin()
	region.players.a.add_item("Bronze Dagger")
	region.submit("a", {"type":"equip","item_name":"Bronze Dagger"})
	check(not region.activities.active("a"), "Changing hand equipment cancels immediately")
	fixture()
	begin()
	region.world.combat.actors.a.hp = 0
	region.world.combat.actors.a.is_alive = false
	advance(0.1)
	check(not region.activities.active("a"), "Death cancels")
	fixture()
	begin()
	advance(2.9)
	region.frozen.a = true
	advance(6)
	check(region.mining.active("a") and region.players.a.backpack.is_empty(), "Frozen actors cannot extract")
	region.frozen.erase("a")
	advance(2.9)
	check(region.players.a.backpack.is_empty(), "Thaw does not catch up missed attempts")
	advance(0.2)
	check(region.players.a.backpack.get("Bronze Ore", 0) == 1, "Fresh post-thaw interval can extract")
	fixture()
	begin()
	region.remove_player("a")
	advance(5)
	check(not region.mining.active("a") and region.snapshot("").deposits[0].state == "available", "Logout cancels without consuming deposit")
	fixture()
	var cooking := CookingSession.new(region.players.a, CookingCampfire.new(), region.world.combat)
	region.activities.cooking.a = cooking
	region.activities._cook_meta.a = {"encounter":1, "start_token":"previous", "phase":1, "prompt":0, "action_ack":0}
	check(not cooking.is_active() and begin().ok, "Completed Cooking allows Mining")
	check(region.activities.snapshot("a").get("kind") == "mine", "Old Cooking presentation cannot hide Mining")
	fixture()
	begin()
	region._mining_nodes.bronze.free()
	advance(0.1)
	check(not region.mining.active("a"), "Removed world node cancels safely")
