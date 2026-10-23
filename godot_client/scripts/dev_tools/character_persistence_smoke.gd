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
	print("[Character persistence] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
