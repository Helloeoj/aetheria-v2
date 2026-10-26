extends Node
var checks := 0
var failures := 0
const Definitions := preload("res://scripts/orders/orders_definitions.gd")
const Service := preload("res://scripts/orders/orders_service.gd")
var fixture: Dictionary

func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(15).timeout.connect(func() -> void:
		printerr("[Orders generation FAIL] Test did not finish")
		get_tree().quit(1))

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("[Orders generation FAIL] ",label)

func _run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/dev_tools/fixtures/orders_config.json"))
	var malformed := fixture.duplicate(true)
	malformed.templates[0].skill = "fishing"
	malformed.templates[0].level = {}
	check(not Definitions.new().validate(malformed).is_empty(),"Malformed requirement types are rejected without script errors")
	malformed = fixture.duplicate(true)
	malformed.tiers.deckhand.min_directives = {}
	check(not Definitions.new().validate(malformed).is_empty(),"Malformed tier count types are rejected without script errors")
	var config := fixture.duplicate(true)
	config.templates = config.templates.filter(func(row: Dictionary) -> bool: return int(row.get("level",0)) == 0)
	config.tiers.smuggler.gate_chance = 1.0
	var service := Service.new()
	check(service.configure(config).ok,"A purely ordinary template library remains valid")
	var p := PlayerState.new("Unavailable gate")
	p.entity_id = "part5-owner"
	p.add_item("Sealed Smuggler's Order")
	check(service.open(p,"smuggler",0).ok and p.backpack.get("Smuggler's Order") == 1,"Unavailable gates fall back to ordinary tasks without stranding the owned packet")
	config = fixture.duplicate(true)
	config.templates.append({"id":"future_contact","enabled":false,"kind":"contact"})
	check(Definitions.new().validate(config).is_empty(),"Disabled future task types need no invented NPC or location")
	config.templates[-1].enabled = "false"
	check(not Definitions.new().validate(config).is_empty(),"A string enabled flag cannot accidentally enter generation")
	config = fixture.duplicate(true)
	config.templates[0].skill = "fishing"
	config.templates[0].level = 20
	check(not Definitions.new().validate(config).is_empty(),"A skill-gated riddle cannot bypass the Deckhand no-gate rule")
	config = fixture.duplicate(true)
	config.templates[0].tiers = ["smuggler"]
	config.templates[0].skill = "fishing"
	config.templates[0].level = 90
	check(not Definitions.new().validate(config).is_empty(),"Non-activity requirements still respect their tier's skill range")
	config = fixture.duplicate(true)
	config.tiers.deckhand.slots = 3
	check(not Definitions.new().validate(config).is_empty(),"Revealed slots cannot exceed the smallest generated Order")
	config = fixture.duplicate(true)
	config.family_weights = {"riddle":0,"search":0,"cipher":0,"fishing":0,"cooking":0}
	check(not Definitions.new().validate(config).is_empty(),"A library filtered to zero usable ordinary families fails validation")
	for invalid: Variant in [{"invented_kind":1},{"riddle":-1},{"riddle":INF},[]]:
		config.family_weights = invalid
		check(not Definitions.new().validate(config).is_empty(),"Invalid family weights fail closed: "+str(invalid))
	# Many text variants of one objective must not masquerade as enough content.
	config = fixture.duplicate(true)
	var original: Dictionary = config.templates[0].duplicate(true)
	config.templates.clear()
	for index in range(12):
		var variant := original.duplicate(true)
		variant.id = "alternate_"+str(index)
		variant.text = "Alternate wording "+str(index)
		config.templates.append(variant)
	check(not Definitions.new().validate(config).is_empty(),"Alternative text IDs do not inflate distinct objective counts")
	# A cache is invalid when excluding it leaves fewer than a full ordinary Order.
	config = fixture.duplicate(true)
	config.templates = config.templates.filter(func(row: Dictionary) -> bool: return row.anchor_id == "outskirts_tavern")
	var cache_cipher: Dictionary = config.templates[0].duplicate(true)
	cache_cipher.id = "only_cache_cipher"
	cache_cipher.kind = "cipher"
	cache_cipher.answer = "fixture solution"
	config.templates.append(cache_cipher)
	config.tiers.deckhand.min_directives = 3
	config.tiers.deckhand.max_directives = 3
	for key: String in config.anchors.keys():
		if key != "outskirts_tavern": config.anchors.erase(key)
	for tier: String in config.tiers:
		config.tiers[tier].min_directives = 3
		config.tiers[tier].max_directives = 3
	check(not Definitions.new().validate(config).is_empty(),"An ordinary target cannot double as its required final cache")
	_variety_and_weights()
	_partial_gates()
	print("[Orders generation] %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)

func _variety_and_weights() -> void:
	var config := fixture.duplicate(true)
	config.family_weights = {"cipher":0,"riddle":30,"search":1}
	var service := Service.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 8765
	check(service.configure(config,rng).ok,"Positive family weights with a disabled family validate")
	var leaked := 0
	var repeated := 0
	var duplicated := 0
	for index in range(200):
		var generated := service.generate("deckhand","variety-owner",index+1)
		if not generated.ok:
			check(false,"Weighted fixture always generates")
			return
		var seen := {}
		var kinds := {}
		var previous := ""
		var adjacent := 0
		for row: Dictionary in generated.order.directives:
			leaked += int(row.kind == "cipher")
			var binding := JSON.stringify([row.kind,row.anchor_id,row.target_id,row.skill,row.level,row.item_name,row.answer])
			duplicated += int(seen.has(binding))
			seen[binding] = true
			kinds[row.kind] = int(kinds.get(row.kind,0))+1
			adjacent += int(previous == row.kind)
			previous = row.kind
		var biggest := 0
		for amount: int in kinds.values(): biggest = maxi(biggest,amount)
		repeated += int(adjacent > maxi(0,2*biggest-generated.order.directives.size()-1))
	check(leaked == 0,"A zero-weight family never enters generated directives")
	check(repeated == 0,"Reveal order avoids avoidable adjacent task types")
	check(duplicated == 0,"One Order never contains an identical objective twice")
	# Equal family weights must not give a family extra share for alternative text.
	config = fixture.duplicate(true)
	for template: Dictionary in config.templates:
		if template.kind == "cipher" and "deckhand" not in template.tiers:
			template.tiers.append("deckhand")
	for tier: String in config.tiers:
		config.tiers[tier].min_directives = 2
		config.tiers[tier].max_directives = 2
		config.tiers[tier].slots = 2
	var many: Dictionary = config.templates[0].duplicate(true)
	for index in range(60):
		var row := many.duplicate(true)
		row.id = "text_variant_"+str(index)
		row.text = "Text variant "+str(index)
		config.templates.append(row)
	rng.seed = 12345
	check(service.configure(config,rng).ok,"Alternative authored wording is supported without duplicate objectives")
	var orders_with_riddle := 0
	for index in range(1000):
		var generated := service.generate("deckhand","weights-owner",index+1)
		if not generated.ok:
			check(false,"Variant fixture remains generatable")
			return
		var kinds: Array = generated.order.directives.map(func(row: Dictionary) -> String: return row.kind)
		orders_with_riddle += int("riddle" in kinds)
	check(orders_with_riddle > 560 and orders_with_riddle < 770,"Neutral family share is independent of the number of authored text variants")
	config.family_weights = {"riddle":30,"search":1,"cipher":1}
	rng.seed = 12345
	check(service.configure(config,rng).ok,"A weighted family preference remains author-configurable")
	orders_with_riddle = 0
	for index in range(1000):
		var generated := service.generate("deckhand","preference-owner",index+1)
		if not generated.ok:
			check(false,"Preferred-family fixture remains generatable")
			return
		var kinds: Array = generated.order.directives.map(func(row: Dictionary) -> String: return row.kind)
		orders_with_riddle += int("riddle" in kinds)
	check(orders_with_riddle > 950,"Configured family preference changes selection frequency")
	config.family_weights = {"riddle":1,"search":0,"cipher":0,"fishing":0,"cooking":0}
	check(service.configure(config,rng).ok,"One ordinary family can still supply distinct objectives")
	var same_objective := 0
	for index in range(100):
		var generated := service.generate("deckhand","distinct-owner",index+1)
		if not generated.ok:
			check(false,"Single-family fixture remains generatable")
			return
		same_objective += int(generated.order.directives[0].anchor_id == generated.order.directives[1].anchor_id)
	check(same_objective == 0,"Alternative wording cannot select the same objective twice even with only one family")

func _partial_gates() -> void:
	var config := fixture.duplicate(true)
	config.tiers.dread_captain.gate_chance = 1.0
	config.tiers.dread_captain.max_gates = 3
	var kept := false
	var rows: Array = []
	for row: Dictionary in config.templates:
		if int(row.get("level",0)) > 0:
			if kept or "dread_captain" not in row.tiers: continue
			kept = true
		rows.append(row)
	config.templates = rows
	var service := Service.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4444
	check(service.configure(config,rng).ok,"A library with one eligible gated objective is valid")
	var successes := 0
	for index in range(100):
		var generated := service.generate("dread_captain","partial-gate-owner",index+1)
		if generated.ok:
			var gates: Array = generated.order.directives.filter(func(row: Dictionary) -> bool: return int(row.level) > 0)
			successes += int(gates.size() == 1)
	check(successes == 100,"Rolling up to three gates uses the one available gate and fills remaining tasks safely")
