extends Node

var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("[Character persistence FAIL] ", label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if not ResourceLoader.exists("res://network/character_codec.gd"):
		check(false, "Character persistence implementation exists")
		get_tree().quit(1)
		return
	var codec = load("res://network/character_codec.gd")
	var p := PlayerState.new("AccountOne")
	p.entity_id = "stable-character"
	p.add_item("Beginner Rod", 2)
	p.add_item("Low Grade Fish Food", 17)
	p.give_and_equip("Bronze Dagger")
	p.add_skill_experience("fishing", 1320)
	p.gold = 987
	p.x = 23.5
	p.y = 27.25
	p.current_hp = 91
	p.current_mana = 3
	p.food_cooldown_seconds = 2.7
	p.food_attack_cooldown_seconds = 1.1
	p.store_fishing_catch("Raw Reedkip")
	var saved: Dictionary = codec.encode(p, "outskirts")
	var restored: Dictionary = codec.decode(JSON.parse_string(JSON.stringify(saved)), "AccountOne", "stable-character")
	check(restored.ok, "Save survives a JSON and process boundary")
	if restored.ok:
		var other: PlayerState = restored.player
		check(other.entity_id == p.entity_id, "Stable character identity")
		check(other.backpack == p.backpack, "Backpack counts survive")
		check(other.get_equipped_names() == p.get_equipped_names(), "Equipment derives approved item definitions")
		check(other.skill_experience == p.skill_experience, "All skill XP survives")
		check(other.gold == 987 and other.get_position() == p.get_position(), "Currency and location survive")
		check(other.current_hp == 91 and other.current_mana == 3, "Reconnecting does not heal or restore mana")
		check(is_equal_approx(other.food_cooldown_seconds, 2.7), "Food restriction survives")
		check(other.fishing_pale == p.fishing_pale, "Individual fishing slots survive")
	var corrupt := saved.duplicate(true)
	corrupt["version"] = 999
	check(not codec.decode(corrupt, "AccountOne", "stable-character").ok, "Unknown schema does not reset character")
	corrupt = saved.duplicate(true)
	corrupt["gold"] = -1
	check(not codec.decode(corrupt, "AccountOne", "stable-character").ok, "Negative currency rejected")
	corrupt = saved.duplicate(true)
	corrupt["inventory"] = [{"item_id": 9999999, "count": 2}]
	check(not codec.decode(corrupt, "AccountOne", "stable-character").ok, "Unknown item rejected rather than granting unapproved stats")
	var initial: Dictionary = codec.initial("AccountTwo", "another-character", "outskirts")
	check(initial.ok and initial.player.get_skill_level("attack") == 1, "New online characters use approved defaults")
	var old := saved.duplicate(true)
	old.version = 1
	old.skill_experience.erase("mining")
	var migrated: Dictionary = codec.decode(old, "AccountOne", "stable-character")
	check(migrated.ok, "Version 1 without Mining migrates")
	if migrated.ok:
		var migrated_player: PlayerState = migrated.player
		check(migrated_player.get_skill_progress("mining").get("level") == 1, "Migration registers Mining at level 1")
		check(migrated_player.backpack == p.backpack and migrated_player.get_equipped_names() == p.get_equipped_names(), "Migration preserves items and equipment")
		for skill: String in old.skill_experience:
			check(migrated_player.get_skill_experience(skill) == int(old.skill_experience[skill]), "Migration preserves " + skill)
	old.skill_experience.mining = "invalid"
	check(not codec.decode(old, "a", "b").ok, "Present malformed v1 Mining is rejected")
	old.skill_experience.erase("mining")
	old.skill_experience.erase("fishing")
	check(not codec.decode(old, "a", "b").ok, "Migration never defaults missing old skills")
	p.add_skill_experience("mining", 121)
	var current: Dictionary = codec.encode(p, "outskirts")
	check(current.version == 3, "New saves use version 3")
	var mined: Dictionary = codec.decode(current, "a", "b")
	check(mined.ok and mined.player.get_skill_experience("mining") == 121, "Mining award survives round trip")
	current.version = 2
	current.skill_experience.erase("mining")
	check(not codec.decode(current, "a", "b").ok, "Version 2 requires Mining")
	var combat_level := p.get_combat_level()
	p.add_skill_experience("mining", SkillProgression.MAX_EXPERIENCE)
	check(p.get_skill_level("mining") == 100 and p.get_skill_experience("mining") == 19450000, "Mining uses existing level and XP cap")
	check(p.get_combat_level() == combat_level, "Mining never changes combat level")
	orders_persistence(codec, p)
	print("[Character persistence] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func orders_persistence(codec: Script, player: PlayerState) -> void:
	var empty := {"version": 1, "generations": {"deckhand": 0, "smuggler": 0, "corsair": 0, "dread_captain": 0}, "orders": {}}
	var saved: Dictionary = codec.encode(player, "outskirts")
	check(saved.get("dead_man_orders") == empty, "New characters persist a bounded empty order book")
	for version: int in [1, 2]:
		var old := saved.duplicate(true)
		old.version = version
		old.erase("dead_man_orders")
		if version == 1:
			old.skill_experience.erase("mining")
		var migrated: Dictionary = codec.decode(old, player.name, player.entity_id)
		check(migrated.ok, "Old version %d without orders migrates" % version)
		if migrated.ok:
			check(codec.encode(migrated.player, "outskirts").get("dead_man_orders") == empty, "Migration creates an empty order book")
		old.dead_man_orders = []
		check(not codec.decode(old, player.name, player.entity_id).ok, "Malformed present order state is never silently reset")
	var corrupt := saved.duplicate(true)
	corrupt.version = 3
	corrupt.erase("dead_man_orders")
	check(not codec.decode(corrupt, player.name, player.entity_id).ok, "Version 3 requires its private order book")
	check(codec.has_method("public_state") and codec.has_method("decode_public"), "Network state has explicit projection and client decoding")
	if not codec.has_method("public_state") or not codec.has_method("decode_public"):
		return
	var projection: Dictionary = codec.public_state(saved)
	check(not projection.has("dead_man_orders") and projection.has("orders_view"), "Client state never contains the private order book")
	check(not codec.decode(projection, player.name, player.entity_id).ok, "A client projection cannot be loaded as an authoritative save")
	var client: Dictionary = codec.decode_public(projection, player.name, player.entity_id)
	check(client.ok, "Projected character can initialize the online client")
	if client.ok:
		check(client.player.backpack == player.backpack, "Projection preserves normal inventory")
	check(codec.apply_to(player, projection), "Acknowledged projection applies to the existing client player")
	check(codec.encode(player, "outskirts").get("dead_man_orders") == empty, "Applying client view preserves private character state")
	var private_book := private_orders_fixture(player.entity_id)
	player.dead_man_orders = private_book.duplicate(true)
	saved = codec.encode(player, "outskirts")
	var round_trip: Dictionary = codec.decode(JSON.parse_string(JSON.stringify(saved)), player.name, player.entity_id)
	check(round_trip.ok, "An individualized private order survives JSON decoding")
	if round_trip.ok:
		# Godot JSON numbers decode as floats; compare the same wire representation.
		check(round_trip.player.dead_man_orders == JSON.parse_string(JSON.stringify(private_book)), "Reconnect preserves directive order, answers, cache, reward and lifecycle identity")
	var wrong_owner: Dictionary = codec.decode(saved, player.name, "different-character")
	check(not wrong_owner.ok, "Orders from another character cannot be loaded")
	projection = codec.public_state(saved)
	var visible: Dictionary = projection.orders_view.orders.deckhand
	check(visible.directives.size() == 1 and visible.sealed == 1, "Only revealed directives enter the client projection")
	check(not visible.has("cache") and not visible.has("rewards"), "Active orders do not expose their future cache or rewards")
	check(not JSON.stringify(projection).contains("SECRET_"), "Private directive answers and sealed content never enter public character state")
	check(codec.apply_to(player, projection) and player.dead_man_orders == private_book, "Applying public orders cannot replace the existing private book")
	projection.orders_view.orders.deckhand.state = "forged-client-state"
	check(player.orders_view.orders.deckhand.state == "active" and player.dead_man_orders == private_book, "Client view and private book do not alias the incoming packet")
	var local := PlayerState.new("Local")
	local.entity_id = player.entity_id
	check(codec.apply_to(local, saved) and local.dead_man_orders == private_book, "Authoritative state application restores the private book")
	local.dead_man_orders.orders.deckhand.state = "abandoned"
	check(saved.dead_man_orders.orders.deckhand.state == "active", "Applied private state does not alias the saved dictionary")
	var malformed := saved.duplicate(true)
	malformed.dead_man_orders.orders.deckhand.directives[1].id = malformed.dead_man_orders.orders.deckhand.directives[0].id
	check(not codec.decode(malformed, player.name, player.entity_id).ok, "Corrupt individualized directive identities are rejected")
	check(not saved.has("orders_view") and not saved.has("public_projection"), "Client projections never enter encoded authoritative saves")
	local.dead_man_orders = {"version": 1}
	check(codec.encode(local, "outskirts").is_empty(), "Malformed live orders cannot be persisted as a reset empty book")

static func private_orders_fixture(owner_id: String) -> Dictionary:
	return {"version": 1, "generations": {"deckhand": 1, "smuggler": 0, "corsair": 0, "dread_captain": 0},
		"orders": {"deckhand": {"id": "11111111111111111111111111111111", "owner": owner_id, "tier": "deckhand",
			"generation": 1, "config_version": 1, "state": "active", "slots": 1,
			"directives": [
				{"id": "22222222222222222222222222222222", "template_id": "fixture_visible", "kind": "cipher",
					"anchor_id": "fixture_anchor", "target_id": "SECRET_TARGET", "skill": "", "level": 0,
					"item_name": "", "text": "Visible framework directive", "answer": "SECRET_ANSWER", "state": "available"},
				{"id": "33333333333333333333333333333333", "template_id": "fixture_sealed", "kind": "search",
					"anchor_id": "fixture_anchor", "target_id": "", "skill": "", "level": 0,
					"item_name": "", "text": "SECRET_SEALED_DIRECTIVE", "answer": "", "state": "sealed"}],
			"cache": "SECRET_CACHE", "cache_info": {"label": "SECRET_CACHE_LABEL", "region_id": "fixture_region", "hint": "SECRET_CACHE_HINT"},
			"rewards": {"gold": 73, "items": [{"item_name": "Beginner Rod", "count": 1}]}}}}
