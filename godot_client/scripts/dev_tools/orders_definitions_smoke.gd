extends SceneTree
## Validate authored Orders content without instantiating or changing game maps.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("[Orders definitions FAIL] ", message)

func _run() -> void:
	check(ResourceLoader.exists("res://scripts/orders/orders_definitions.gd"), "Authored Orders definitions loader exists")
	if not failures.is_empty():
		_finish()
		return
	var definitions = load("res://scripts/orders/orders_definitions.gd").new()
	var loaded: Dictionary = definitions.load_data()
	check(bool(loaded.get("ok", false)), "Disabled production framework validates: " + str(loaded.get("errors", [])))
	var production: Dictionary = loaded.get("config", {})
	check(production.get("enabled") == false, "Production Orders remain intentionally disabled until user supplies content")
	check(production.get("anchors", {}).is_empty() and production.get("templates", []).is_empty() and production.get("base_rewards", []).is_empty(), "Framework ships no authored locations, directives or invented rewards")
	check(production.get("acquisition", {}).get("fishing_chance", -1) == 0 and production.get("acquisition", {}).get("monster_chance", -1) == 0, "Disabled framework cannot acquire sealed orders")
	loaded = definitions.load_data("res://scripts/dev_tools/fixtures/orders_config.json")
	check(bool(loaded.get("ok", false)), "Synthetic enabled test fixture validates: " + str(loaded.get("errors", [])))
	var config: Dictionary = loaded.get("config", {})
	if config.is_empty():
		_finish()
		return
	for tier: String in ["deckhand", "smuggler", "corsair", "dread_captain"]:
		var count := 0
		for template: Dictionary in config.templates:
			if tier in template.tiers and String(template.kind) in ["riddle", "search", "cipher"]:
				count += 1
		var minimum := int(config.tiers[tier].max_directives)
		check(count >= minimum, tier + " has enough ordinary authored directives to avoid forced gates")
	var malformed := config.duplicate(true)
	malformed.templates[0].anchor_id = "unverified_new_place"
	check(not definitions.validate(malformed).is_empty(), "Unknown map anchors fail closed")
	malformed = config.duplicate(true)
	malformed.templates[0].tiers = ["imaginary_tier"]
	check(not definitions.validate(malformed).is_empty(), "Unknown tier references fail closed")
	malformed = config.duplicate(true)
	malformed.templates[0].skill = "smithing"
	check(not definitions.validate(malformed).is_empty(), "Invented skill requirements fail closed")
	malformed = config.duplicate(true)
	malformed.base_rewards.append({"item_name": "Starforged Ore", "min": 1, "max": 1, "weight": 1})
	check(not definitions.validate(malformed).is_empty(), "Orders cannot bypass boss-only materials")
	malformed = config.duplicate(true)
	malformed.base_rewards[0].max = 2147483648
	check(not definitions.validate(malformed).is_empty(), "Reward quantities respect persistent inventory bounds")
	malformed = config.duplicate(true)
	malformed.templates.append(config.templates[0].duplicate(true))
	check(not definitions.validate(malformed).is_empty(), "Duplicate template IDs fail closed")
	malformed = config.duplicate(true)
	var anchor_id: String = malformed.anchors.keys()[0]
	malformed.anchors[anchor_id].node_path = "MissingAnchor"
	check(not definitions.validate(malformed).is_empty(), "Missing authored scene nodes fail closed without instantiation")
	malformed = config.duplicate(true)
	malformed.anchors.outskirts_tavern.node_path = "Combat"
	check(not definitions.validate(malformed).is_empty(), "An existing generic scene node cannot impersonate a portal anchor")
	malformed = config.duplicate(true)
	malformed.anchors.outskirts_tavern.node_path = "Combat/RiverFishingSpot"
	check(not definitions.validate(malformed).is_empty(), "A real FishingSpot cannot impersonate a portal anchor")
	malformed = config.duplicate(true)
	malformed.anchors.tavern_stove.node_path = "Combat/TavernExit"
	check(not definitions.validate(malformed).is_empty(), "A real CavePortal cannot impersonate a cooking anchor")
	var inherited_portal := GDScript.new()
	inherited_portal.source_code = "extends \"res://scripts/cave_portal.gd\"\n"
	check(inherited_portal.reload() == OK and definitions._script_matches_kind(inherited_portal,"portal") and not definitions._script_matches_kind(inherited_portal,"fish"), "Inherited CavePortal scripts retain only compatible interaction kinds")
	malformed = config.duplicate(true)
	malformed.tiers.deckhand.gate_chance = -0.01
	check(not definitions.validate(malformed).is_empty(), "Invalid gate probabilities fail closed")
	malformed = config.duplicate(true)
	malformed.deferred[0].enabled = true
	check(not definitions.validate(malformed).is_empty(), "Unimplemented rewards cannot be enabled as working content")
	_finish()

func _finish() -> void:
	print("[Orders definitions] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
