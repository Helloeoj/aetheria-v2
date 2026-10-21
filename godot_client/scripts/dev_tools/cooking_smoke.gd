extends Node
## Headless gameplay regression: actual catches -> timed cooking -> existing food.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("[Cooking FAIL] ", description)

func fire_for(player: PlayerState) -> CookingCampfire:
	var fire := CookingCampfire.new(player.get_position())
	fire.active = true
	return fire

func _ready() -> void:
	check_catalog_and_progression()
	check_transactions()
	check_interruptions()
	check_batch_and_burning()
	print("[Cooking] %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func check_catalog_and_progression() -> void:
	var player := PlayerState.new()
	check(player.get_skill_level("cooking") == 1 and player.get_skill_experience("cooking") == 0,
		"Cooking starts at level 1 with independent XP")
	check(player.get_skills_progress().size() == SkillProgression.SKILL_IDS.size() and player.get_skill_progress("cooking").name == "Cooking",
		"Cooking participates in normal skill progression and journal data")
	var combat_level := player.get_combat_level()
	player.set_skill_level("cooking", 100)
	check(player.get_combat_level() == combat_level, "Cooking never contributes to combat level")
	var ids := {}
	var names := {}
	for item: Dictionary in GameData.list_items():
		check(not ids.has(int(item.id)) and not names.has(String(item.name)), "Catalog ID/name are unique: " + String(item.name))
		ids[int(item.id)] = true
		names[String(item.name)] = true
	var loot := LootSystem.new()
	for index in range(FishingSession.FISH.size()):
		var species: String = FishingSession.FISH[index]
		var raw := "Raw " + species
		var burnt := "Burnt " + species
		var recipe := CookingSession.recipe_for_item(raw)
		check(not recipe.is_empty() and int(recipe.cooking_level) == maxi(1, index * 10), species + " unlock scales with fish tier")
		check(int(recipe.no_burn_level) == mini(100, int(recipe.cooking_level) + 20), species + " mastery is reachable within the level cap")
		var previous_chance := 1.0
		for level in range(int(recipe.cooking_level), 101):
			var chance := CookingSession.burn_chance(level, recipe)
			check(chance >= 0.0 and chance <= previous_chance and chance <= 0.30,
				species + " burn chance stays bounded and decreases at level %d" % level)
			previous_chance = chance
		check(is_equal_approx(CookingSession.burn_chance(int(recipe.cooking_level), recipe), 0.30)
			and is_zero_approx(CookingSession.burn_chance(int(recipe.no_burn_level), recipe)), species + " burns at unlock and never at mastery")
		for fish_name: String in [raw, species, burnt]:
			check(not InventorySystem.is_stackable(fish_name), fish_name + " uses one slot per fish")
			check(not bool(GameData.get_item_by_name(fish_name).get("generic_loot", true)), fish_name + " stays out of generic loot")
			check(fish_name not in loot._tier_pools(index + 1).general.map(func(item: Dictionary) -> String: return String(item.name)), fish_name + " is excluded by the real loot pool")
		var novice := PlayerState.new()
		novice.current_hp -= 10
		for fish_name: String in [raw, burnt]:
			novice.add_item(fish_name)
			var before := novice.current_hp
			check(FishingSession.eat(novice, fish_name) == 0 and novice.current_hp == before
				and int(novice.backpack[fish_name]) == 1 and novice.food_cooldown_seconds == 0.0,
				fish_name + " cannot be eaten and spends nothing")
		check(novice.get_quick_food().is_empty(), "Raw and burnt fish are never quick food")
		novice.add_item(species)
		check(novice.get_quick_food() == species and FishingSession.eat(novice, species) == 10,
			"Cooked " + species + " is edible at Cooking/Fishing 1 with existing capped healing")
		check(CookingSession.recipe_for_item(species).is_empty() and CookingSession.recipe_for_item(burnt).is_empty(), species + " cannot be recooked")
		var cook := CookingSession.new(player, fire_for(player))
		player.add_item(raw, 3)
		player.set_skill_level("cooking", int(recipe.no_burn_level))
		var xp_before := player.get_skill_experience("cooking")
		check(cook.start(raw, 3).is_empty(), "Mastered batch starts for " + raw)
		var results := cook.advance(9.0)
		check(results.size() == 3 and cook.cooked_count == 3 and cook.burnt_count == 0 and not player.backpack.has(raw), species + " three inputs yield three cooked outputs at mastery")
		check(cook.reward_xp == mini(3 * int(recipe.cooking_xp), SkillProgression.MAX_EXPERIENCE - xp_before), species + " success awards recipe XP up to the level cap")
		if int(recipe.cooking_level) > 1:
			var locked := CookingSession.new(novice, fire_for(novice))
			novice.food_cooldown_seconds = 0.0
			check(not locked.start(raw).is_empty() and novice.backpack.has(raw), species + " cannot be cooked below requirement")

func check_transactions() -> void:
	var player := PlayerState.new()
	var fishing := FishingSession.new(player)
	fishing.fish = GameData.get_item_by_name("Raw Reedkip")
	fishing.state = FishingSession.State.FIGHT
	fishing._land()
	var fishing_xp := player.get_skill_experience("fishing")
	check(player.fishing_pale[0] == "Raw Reedkip" and player.get_quick_food().is_empty(), "Real landing yields raw, inedible fish in the pale")
	check(not player.store_fishing_catch("Reedkip") and not player.store_fishing_catch("Burnt Reedkip"), "Cooked and burnt fish cannot masquerade as catches")
	var fire := fire_for(player)
	var cooking := CookingSession.new(player, fire)
	check(not cooking.start("Raw Reedkip").is_empty(), "Pale fish must first be moved into the backpack")
	player.move_fishing_catch_to_inventory(0)
	player.set_skill_level("cooking", 21)
	var before := player.backpack.duplicate(true)
	check(cooking.start("Raw Reedkip").is_empty() and player.backpack == before, "Starting cooking consumes nothing")
	check(cooking.advance(2.9).is_empty() and player.backpack == before, "Partial cooking time consumes nothing")
	var results := cooking.advance(0.1)
	check(results.size() == 1 and String(results[0].output) == "Reedkip" and cooking.state == CookingSession.State.FINISHED, "Three seconds finishes one mastered fish")
	check(not player.backpack.has("Raw Reedkip") and int(player.backpack.get("Reedkip", 0)) == 1, "Cooking atomically exchanges one raw fish for one cooked fish")
	check(player.get_skill_experience("fishing") == fishing_xp, "Cooking does not award Fishing XP")
	var xp := player.get_skill_experience("cooking")
	check(cooking.advance(300.0).is_empty() and player.get_skill_experience("cooking") == xp, "Completed cooking cannot repeat fish or XP")
	for name: String in ["Reedkip", "Burnt Reedkip", "Beginner Rod", "Missing Fish"]:
		check(not cooking.start(name).is_empty(), "Non-recipe cannot start: " + name)
	player.add_item("Raw Reedkip", 2)
	for quantity: int in [0, -1, 3]:
		check(not cooking.start("Raw Reedkip", quantity).is_empty() and int(player.backpack["Raw Reedkip"]) == 2, "Invalid quantity spends nothing: %d" % quantity)
	check(cooking.start("Raw Reedkip", 2).is_empty(), "Batch can start after previous completion")
	var other := CookingSession.new(player, fire)
	check(not other.start("Raw Reedkip").is_empty() and not cooking.start("Raw Reedkip").is_empty(), "One player cannot run overlapping cooking timers")
	cooking.advance(1.5)
	cooking.close()
	check(cooking.advance(5.0).is_empty() and int(player.backpack["Raw Reedkip"]) == 2, "Cancelling preserves the unfinished ingredient")
	check(other.start("Raw Reedkip").is_empty(), "Cancellation releases the player's cooking action")
	other.close()
	var abandoned := CookingSession.new(player, fire)
	abandoned.start("Raw Reedkip")
	abandoned = null
	check(other.start("Raw Reedkip").is_empty(), "An abandoned session does not permanently lock the player")
	other.close()

func check_interruptions() -> void:
	for reason: String in ["fire", "range", "movement", "damage", "death", "combat", "target", "spell", "missing", "level"]:
		var player := PlayerState.new()
		player.set_skill_level("cooking", 21)
		player.add_item("Raw Reedkip", 2)
		var fire := fire_for(player)
		var engine := CombatEngine.new()
		var cooking := CookingSession.new(player, fire, engine)
		cooking.start("Raw Reedkip", 2)
		cooking.advance(2.0)
		var xp := player.get_skill_experience("cooking")
		match reason:
			"fire": fire.active = false
			"range": fire.position += Vector2(10, 0)
			"movement": player.x += 0.25
			"damage": player.current_hp -= 1
			"death": player.current_hp = 0
			"combat": player.in_combat = true
			"target": player.current_target = "enemy"
			"spell": engine.active_spell_casts[player.entity_id] = {}
			"missing": player.remove_item("Raw Reedkip", 2)
			"level": player.set_skill_level("cooking", 1) # Still unlocked; test a locked recipe below instead.
		if reason == "level":
			cooking.close()
			player.add_item("Raw Marlo")
			player.set_skill_level("cooking", 10)
			cooking.start("Raw Marlo")
			cooking.advance(2.0)
			player.set_skill_level("cooking", 9)
			xp = player.get_skill_experience("cooking")
		var results := cooking.advance(1.0)
		check(results.is_empty() and cooking.state == CookingSession.State.CANCELLED and player.get_skill_experience("cooking") == xp, "Interruption cancels before rewards: " + reason)
		check(not player.backpack.has("Reedkip") and not player.backpack.has("Burnt Reedkip"), "Interrupted attempt produces no output: " + reason)
		if reason != "missing":
			check(int(player.backpack["Raw Reedkip"]) == 2, "Interrupted attempt preserves ingredients: " + reason)
	var player := PlayerState.new()
	player.add_item("Raw Reedkip")
	var fire := CookingCampfire.new(player.get_position())
	var cooking := CookingSession.new(player, fire)
	check(not cooking.start("Raw Reedkip").is_empty(), "Unlit campfire cannot cook")
	check(not CookingSession.new(player, null).start("Raw Reedkip").is_empty(), "Cooking requires a campfire")
	check(not CookingSession.new(null, fire).start("Raw Reedkip").is_empty(), "Missing player is safely rejected")
	fire.active = true
	fire.position += Vector2(10, 0)
	check(not cooking.start("Raw Reedkip").is_empty(), "Remote campfire cannot start cooking")

func check_batch_and_burning() -> void:
	var player := PlayerState.new()
	player.add_item("Raw Reedkip", 200)
	var cooking := CookingSession.new(player, fire_for(player))
	cooking.rng.seed = 1729
	cooking.start("Raw Reedkip", 200)
	check(cooking.advance(-3.0).is_empty() and cooking.advance(NAN).is_empty() and cooking.advance(INF).is_empty(), "Invalid time does not cook or consume ingredients")
	var results := cooking.advance(600.0)
	check(results.size() == 200 and cooking.cooked_count > 0 and cooking.burnt_count > 0, "Seeded batch exercises actual successful and burnt rolls")
	check(cooking.cooked_count + cooking.burnt_count == 200 and not player.backpack.has("Raw Reedkip"), "Each completed attempt spends one input and produces exactly one output")
	check(cooking.reward_xp == cooking.cooked_count * 40 and player.get_skill_experience("cooking") == cooking.reward_xp, "Only successfully cooked fish earn XP")
	var previous_chance := 0.30
	for result: Dictionary in results:
		check(float(result.burn_chance) <= previous_chance and int(result.experience) == (0 if bool(result.burnt) else 40), "Each batch roll uses current level; burnt results never grant XP")
		previous_chance = float(result.burn_chance)
	check(previous_chance < 0.30, "Mid-batch level gains reduce burn risk for subsequent fish")
	player = PlayerState.new()
	player.set_skill_level("cooking", 100)
	player.add_item("Raw Sunfish", 2)
	cooking = CookingSession.new(player, fire_for(player))
	cooking.start("Raw Sunfish", 2)
	results = cooking.advance(6.0)
	check(results.size() == 2 and cooking.burnt_count == 0 and cooking.reward_xp == 0
		and player.get_skill_experience("cooking") == SkillProgression.MAX_EXPERIENCE, "Maxed Cooking never burns the highest tier or overflows the XP cap")
	player.add_item("Raw Sunfish", 2)
	var fire := fire_for(player)
	cooking = CookingSession.new(player, fire)
	cooking.start("Raw Sunfish", 2)
	check(cooking.advance(3.0).size() == 1, "Batch completes one fish per three seconds")
	fire.active = false
	check(cooking.advance(3.0).is_empty() and int(player.backpack["Raw Sunfish"]) == 1, "An extinguished fire preserves the next fish after an earlier completion")
