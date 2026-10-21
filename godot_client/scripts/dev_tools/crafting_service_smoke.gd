extends SceneTree
## Real inventory transactions: approved costs, atomic rejection and one-way empowerment.

var checks := 0
var failures: Array[String] = []
var service: Script
var data: Node
var player_script: Script

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("[Crafting FAIL] ", description)

func _run() -> void:
	check(ResourceLoader.exists("res://scripts/crafting_service.gd"), "Crafting service exists for approved recipes")
	if not failures.is_empty():
		_finish()
		return
	service = load("res://scripts/crafting_service.gd")
	data = root.get_node("GameData")
	player_script = load("res://scripts/player_state.gd")
	check_catalog()
	check_starter_transactions()
	check_rejections()
	check_empowerment()
	check_staff_assembly()
	check_conditions()
	_finish()

func _finish() -> void:
	print("[Crafting] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func check_catalog() -> void:
	var recipes: Array[Dictionary] = service.list_recipes()
	check(recipes.size() > 10, "Recipes describe both usable starter costs and pending progression")
	var ids := {}
	for recipe: Dictionary in recipes:
		var recipe_id := String(recipe.get("id", ""))
		check(not recipe_id.is_empty() and not ids.has(recipe_id), "Recipe IDs are present and unique: " + recipe_id)
		ids[recipe_id] = true
		check(not recipe.has("experience") and not recipe.has("seconds"), "XP and time are deferred: " + recipe_id)
		if not bool(recipe.get("enabled", false)):
			check(not String(recipe.get("reason", "")).is_empty() and Array(recipe.get("inputs", [])).is_empty(), "Pending recipe has explanation and no fabricated quantities: " + recipe_id)
			continue
		for entry: Dictionary in Array(recipe.inputs) + Array(recipe.outputs):
			check(not data.get_item_by_name(String(entry.item)).is_empty() and int(entry.quantity) > 0, "Usable recipe references real positive-count items: " + String(entry.item))
	for station: String in ["leatherworking", "anvil", "enchanting", "furnace", "fletching", "tailoring"]:
		var station_recipes: Array[Dictionary] = service.list_recipes(station)
		check(not station_recipes.is_empty(), "Station has recipe or pending routes: " + station)
		for recipe: Dictionary in station_recipes:
			check(String(recipe.station) == station, "Station filter excludes unrelated recipes")
	var exposed: Array[Dictionary] = service.list_recipes("anvil")
	for recipe: Dictionary in exposed:
		recipe["enabled"] = true
		recipe["inputs"] = []
		recipe["outputs"] = [{"item": "Bronze Dagger", "quantity": 100}]
	var player: RefCounted = player_script.new()
	check(not bool(service.craft(player, "bronze_dagger", "anvil").ok) and player.backpack.is_empty(), "Mutating listed recipes cannot inject free equipment")

func check_starter_transactions() -> void:
	var player: RefCounted = player_script.new()
	player.add_item("Starter Hide", 12)
	var xp: Dictionary = player.skill_experience.duplicate(true)
	var result: Dictionary = service.craft(player, "tan_starter_hide", "leatherworking", 10)
	check(bool(result.ok) and player.backpack == {"Starter Hide": 2, "Tanned Leather": 10}, "Ten hides tan into ten leather without consuming extra hides")
	for recipe_id: String in ["tanned_leather_coif", "tanned_leather_tunic", "tanned_leather_chaps"]:
		check(bool(service.craft(player, recipe_id, "leatherworking").ok), "Approved leather armor crafts: " + recipe_id)
	check(not player.backpack.has("Tanned Leather") and player.backpack.get("Tanned Leather Coif", 0) == 1 and player.backpack.get("Tanned Leather Tunic", 0) == 1 and player.backpack.get("Tanned Leather Chaps", 0) == 1, "Coif, tunic and chaps consume exactly ten leather total")
	player.add_item("Bronze Ingot", 5)
	check(forge(player, "bronze_dagger") and forge(player, "bronze_dagger"), "Two guided daggers cost two bronze ingots")
	check(forge(player, "bronze_longsword"), "Guided longsword uses remaining three bronze ingots")
	check(not player.backpack.has("Bronze Ingot") and player.backpack.get("Bronze Dagger", 0) == 2 and player.backpack.get("Bronze Longsword", 0) == 1, "Approved bronze costs and batch yields are exact")
	check(player.get_skill_experience("smithing") > 0, "Guided smithing awards its configured XP")
	xp.erase("smithing")
	var other_xp: Dictionary = player.skill_experience.duplicate(true)
	other_xp.erase("smithing")
	check(other_xp == xp, "Crafting preserves all other skill XP")

func forge(player: RefCounted, recipe_id: String) -> bool:
	var station: Node2D = load("res://scripts/crafting_station.gd").new()
	station.setup("anvil", "Anvil", player.get_position())
	var session: RefCounted = load("res://scripts/smithing_session.gd").new(player, station)
	var error: String = session.start(recipe_id)
	if error.is_empty():
		for index in range(session.total_hits()):
			session.strike(session.target_position())
		session.advance(10.0)
	station.free()
	return error.is_empty() and session.state == session.State.FINISHED

func check_rejections() -> void:
	var player: RefCounted = player_script.new()
	player.add_item("Bronze Ingot", 2)
	for invalid: Dictionary in [
		{"id": "bronze_longsword", "station": "anvil", "quantity": 1},
		{"id": "bronze_dagger", "station": "furnace", "quantity": 1},
		{"id": "bronze_dagger", "station": "anvil", "quantity": 0},
		{"id": "bronze_dagger", "station": "anvil", "quantity": -1},
		{"id": "bronze_longsword", "station": "anvil", "quantity": 9223372036854775807},
		{"id": "invented_recipe", "station": "anvil", "quantity": 1}
	]:
		var before: Dictionary = player.backpack.duplicate(true)
		var result: Dictionary = service.craft(player, invalid.id, invalid.station, invalid.quantity)
		check(not bool(result.ok) and not String(result.message).is_empty() and player.backpack == before, "Invalid request preserves all inventory: " + String(invalid.id) + " x" + str(invalid.quantity))
	check(not bool(service.craft(null, "bronze_dagger", "anvil").ok), "Missing player is safely rejected")
	for recipe: Dictionary in service.list_recipes():
		if not bool(recipe.get("enabled", false)):
			var before: Dictionary = player.backpack.duplicate(true)
			check(not bool(service.craft(player, recipe.id, recipe.station).ok) and player.backpack == before, "Unapproved quantities cannot be used: " + String(recipe.id))
	# A missing output definition must be checked before an ingredient is consumed.
	var dagger: Dictionary = data.items_by_name.get("Bronze Dagger", {})
	data.items_by_name.erase("Bronze Dagger")
	check(not bool(service.craft(player, "bronze_dagger", "anvil").ok) and player.backpack == {"Bronze Ingot": 2}, "Missing output definition spends no ingredients")
	data.items_by_name["Bronze Dagger"] = dagger
	player.backpack["Bronze Dagger"] = 9223372036854775807
	var before_overflow: Dictionary = player.backpack.duplicate(true)
	check(not bool(service.craft(player, "bronze_dagger", "anvil").ok) and player.backpack == before_overflow, "Output stack overflow cannot consume ingredients or wrap counts")

func check_empowerment() -> void:
	for element: String in ["fire", "ice", "lightning", "hurricane"]:
		var player: RefCounted = player_script.new()
		var prefix := element.capitalize()
		player.add_item("Magic Orb", 2)
		player.add_item(prefix + " Sigil", 1)
		check(bool(service.empower_orb(player, element).ok), prefix + " sigil permanently empowers one plain orb")
		check(player.backpack == {"Magic Orb": 1, prefix + " Orb": 1}, "Empowerment consumes one matching sigil and one plain orb: " + element)
		var before: Dictionary = player.backpack.duplicate(true)
		check(not bool(service.empower_orb(player, element).ok) and player.backpack == before, "Missing sigil cannot consume another plain orb: " + element)
		player.backpack.erase("Magic Orb")
		player.add_item(prefix + " Sigil")
		before = player.backpack.duplicate(true)
		check(not bool(service.empower_orb(player, element).ok) and player.backpack == before, "Empowered orb cannot be rerolled, stacked or re-empowered: " + element)
	var player: RefCounted = player_script.new()
	player.add_item("Magic Orb")
	player.add_item("Fire Sigil")
	check(not bool(service.empower_orb(player, "ice").ok) and player.backpack == {"Magic Orb": 1, "Fire Sigil": 1}, "Different elemental sigil is not interchangeable")
	check(not bool(service.empower_orb(player, "unknown").ok), "Unknown enchantment cannot create items")
	player.equipment["weapon"] = data.get_item_by_name("Apprentice Magic Staff (Ice)")
	var equipped_before: Dictionary = player.equipment.duplicate(true)
	check(bool(service.empower_orb(player, "fire").ok) and player.equipment == equipped_before and player.backpack == {"Fire Orb": 1}, "Empowerment changes only a backpack orb and leaves an equipped staff untouched")
	player.backpack.clear()
	player.add_item("Fire Sigil")
	check(not bool(service.empower_orb(player, "fire").ok) and player.equipment == equipped_before and player.backpack == {"Fire Sigil": 1}, "An equipped staff cannot substitute for the required plain orb")

func check_staff_assembly() -> void:
	for element: String in ["", "fire", "ice", "lightning", "hurricane"]:
		var player: RefCounted = player_script.new()
		var orb := "Magic Orb" if element.is_empty() else element.capitalize() + " Orb"
		var recipe_id := "apprentice_magic_staff" + ("" if element.is_empty() else "_" + element)
		var output := "Apprentice Magic Staff" + ("" if element.is_empty() else " (" + element.capitalize() + ")")
		player.add_item("Wooden Staff Body")
		var before: Dictionary = player.backpack.duplicate(true)
		check(not bool(service.craft(player, recipe_id, "fletching").ok) and player.backpack == before, "Staff without an orb cannot consume its wooden body: " + element)
		player.add_item(orb)
		check(bool(service.craft(player, recipe_id, "fletching").ok) and player.backpack == {output: 1}, "Staff permanently consumes its body and matching orb: " + element)
		var staff: Dictionary = data.get_item_by_name(output)
		check(String(staff.get("orb_element", "")) == element, "Finished staff preserves only its selected orb effect: " + element)

func check_conditions() -> void:
	# Rejecting dead/combat/cooking states belongs to the service, so inventory
	# empowerment cannot bypass the station caller's safety checks.
	for condition: String in ["dead", "combat", "target", "cooking"]:
		var player: RefCounted = player_script.new()
		player.add_item("Bronze Ingot", 3)
		player.add_item("Magic Orb")
		player.add_item("Fire Sigil")
		var session := RefCounted.new()
		match condition:
			"dead": player.current_hp = 0
			"combat": player.in_combat = true
			"target": player.current_target = "monster"
			"cooking": player.active_cooking_session = weakref(session)
		var before: Dictionary = player.backpack.duplicate(true)
		check(not bool(service.craft(player, "bronze_longsword", "anvil").ok) and player.backpack == before, "Crafting preserves materials during prohibited state: " + condition)
		check(not bool(service.empower_orb(player, "fire").ok) and player.backpack == before, "Inventory empowerment preserves materials during prohibited state: " + condition)


