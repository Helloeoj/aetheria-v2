class_name CookingSession
extends RefCounted
## One fish per timed attempt. The future campfire controller calls advance().
## No ingredients are spent until an attempt finishes; only successes award XP.
enum State { READY, COOKING, FINISHED, CANCELLED }
const BURN_CHANCE_AT_UNLOCK := 0.30

var player: PlayerState
var campfire: CookingCampfire
var engine: CombatEngine
var rng := RandomNumberGenerator.new()
var state := State.READY
var raw_item := ""
var remaining := 0
var elapsed := 0.0
var cooked_count := 0
var burnt_count := 0
var reward_xp := 0
var message := "Choose raw fish to cook at a campfire."
var start_position := Vector2.ZERO
var start_hp := 0

func _init(owner_player: PlayerState, heat_source: CookingCampfire, combat: CombatEngine = null) -> void:
	player = owner_player
	campfire = heat_source
	engine = combat
	rng.randomize()

static func recipe_for_item(item_name: String) -> Dictionary:
	var item := GameData.get_item_by_name(item_name)
	if String(item.get("fish_state", "")) != "raw":
		return {}
	var required := int(item.get("cooking_level", 0))
	var mastery := int(item.get("no_burn_level", 0))
	if required < 1 or required > 100 or mastery <= required or mastery > 100:
		return {}
	if float(item.get("cooking_seconds", 0.0)) <= 0.0 or int(item.get("cooking_xp", 0)) <= 0:
		return {}
	for outcome: String in ["cooked", "burnt"]:
		var result := GameData.get_item_by_name(String(item.get(outcome + "_item", "")))
		if String(result.get("fish_state", "")) != outcome or result.get("fish_species", "") != item.get("fish_species", ""):
			return {}
	return item.duplicate(true)

static func burn_chance(cooking_level: int, recipe: Dictionary) -> float:
	var required := int(recipe.get("cooking_level", 1))
	var mastery := int(recipe.get("no_burn_level", required + 20))
	var progress := clampf(float(cooking_level - required) / float(maxi(1, mastery - required)), 0.0, 1.0)
	return BURN_CHANCE_AT_UNLOCK * (1.0 - progress)

func start(item_name: String, quantity: int = 1) -> String:
	if state == State.COOKING:
		return "You are already cooking."
	if player == null:
		return "There is no cook."
	if player.active_cooking_session != null and player.active_cooking_session.get_ref() != null:
		return "You are already cooking."
	if player.active_smithing_session != null and player.active_smithing_session.get_ref() != null:
		return "Finish Smithing before cooking."
	var error := _conditions_error()
	if not error.is_empty():
		return error
	var recipe := recipe_for_item(item_name)
	if recipe.is_empty():
		return "Choose raw fish; cooked and burnt fish cannot be cooked again."
	if player.get_skill_level("cooking") < int(recipe.cooking_level):
		return "You need Cooking %d to cook %s." % [int(recipe.cooking_level), item_name]
	if quantity <= 0 or int(player.backpack.get(item_name, 0)) < quantity:
		return "You do not have that many raw fish in your backpack."
	raw_item = item_name
	remaining = quantity
	elapsed = 0.0
	cooked_count = 0
	burnt_count = 0
	reward_xp = 0
	start_position = player.get_position()
	start_hp = player.current_hp
	player.active_cooking_session = weakref(self)
	state = State.COOKING
	message = "Cooking %s..." % raw_item
	return ""

func advance(delta: float) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if state != State.COOKING or not is_finite(delta) or delta <= 0.0:
		return results
	var error := _conditions_error()
	if error.is_empty() and not player.get_position().is_equal_approx(start_position):
		error = "You stopped cooking because you moved."
	if error.is_empty() and player.current_hp < start_hp:
		error = "You stopped cooking because you took damage."
	if not error.is_empty():
		close(error)
		return results
	var recipe := recipe_for_item(raw_item)
	if recipe.is_empty() or player.get_skill_level("cooking") < int(recipe.cooking_level):
		close("You can no longer cook this fish.")
		return results
	elapsed += delta
	var seconds := float(recipe.cooking_seconds)
	while state == State.COOKING and elapsed + 0.000001 >= seconds:
		if not player.remove_item(raw_item):
			close("You have no more of that raw fish in your backpack.")
			break
		elapsed = maxf(0.0, elapsed - seconds)
		var level_before := player.get_skill_level("cooking")
		var chance := burn_chance(level_before, recipe)
		var burnt := rng.randf() < chance
		var output := String(recipe.burnt_item if burnt else recipe.cooked_item)
		player.add_item(output)
		var xp_before := player.get_skill_experience("cooking")
		if burnt:
			burnt_count += 1
		else:
			cooked_count += 1
			player.add_skill_experience("cooking", int(recipe.cooking_xp))
		var xp := player.get_skill_experience("cooking") - xp_before
		reward_xp += xp
		remaining -= 1
		message = "You burnt %s. No Cooking XP." % String(recipe.fish_species) if burnt else "You cook %s. +%d Cooking XP" % [String(recipe.fish_species), xp]
		results.append({"input": raw_item, "output": output, "burnt": burnt,
			"burn_chance": chance, "experience": xp, "level_before": level_before,
			"level_after": player.get_skill_level("cooking")})
		if remaining <= 0:
			state = State.FINISHED
			elapsed = 0.0
			_release_player()
	return results

func close(reason: String = "You stopped cooking.") -> void:
	if state == State.COOKING:
		state = State.CANCELLED
		elapsed = 0.0
		message = reason
		_release_player()

func _release_player() -> void:
	if player != null and player.active_cooking_session != null and player.active_cooking_session.get_ref() == self:
		player.active_cooking_session = null

func _conditions_error() -> String:
	if player.current_hp <= 0:
		return "You must be alive to cook."
	if player.in_combat or not player.current_target.is_empty():
		return "You cannot cook during combat."
	if engine != null and engine.active_spell_casts.has(player.entity_id):
		return "Finish casting before cooking."
	if player.food_cooldown_seconds > 0.0:
		return "Finish eating before cooking."
	if campfire == null:
		return "You need a burning campfire to cook."
	return campfire.cooking_error(player)
