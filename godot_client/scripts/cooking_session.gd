class_name CookingSession
extends RefCounted
## Local authoritative cooking state. One prompt and one transaction per fish.
## Reserve raw food at prompt entry; resolve rewards before visual feedback.
enum State { READY, COOKING, FLIP_PENDING, FEEDBACK, FINISHED, CANCELLED }
const MIN_FLIP_WINDOW := 0.8
const MAX_FINITE_FLIP_WINDOW := 2.5
const FEEDBACK_SECONDS := 0.65

var player: PlayerState
var campfire: CookingCampfire
var engine: CombatEngine
var state := State.READY
var raw_item := ""
var remaining := 0
var elapsed := 0.0
var flip_elapsed := 0.0
var flip_window := MIN_FLIP_WINDOW
var feedback_elapsed := 0.0
var last_result: Dictionary = {}
var _reserved_recipe: Dictionary = {}
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

static func reaction_window(cooking_level: int, recipe: Dictionary) -> float:
	var required := int(recipe.get("cooking_level", 0))
	var mastery := int(recipe.get("no_burn_level", 0))
	# Invalid/missing data never invents a mastery level or grants untimed cooking.
	if required < 1 or mastery <= required or mastery > 100:
		return MIN_FLIP_WINDOW
	if cooking_level >= mastery:
		return INF
	var progress := clampf(float(cooking_level - required) / float(maxi(1, mastery - required - 1)), 0.0, 1.0)
	return lerpf(MIN_FLIP_WINDOW, MAX_FINITE_FLIP_WINDOW, progress)

func is_active() -> bool:
	return state in [State.COOKING, State.FLIP_PENDING, State.FEEDBACK]

func start(item_name: String, quantity: int = 1) -> String:
	if is_active():
		return "You are already cooking."
	if player == null:
		return "There is no cook."
	if player.active_cooking_session != null and player.active_cooking_session.get_ref() != null:
		return "You are already cooking."
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
	flip_elapsed = 0.0
	feedback_elapsed = 0.0
	last_result = {}
	_reserved_recipe = {}
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
	if not is_active() or not is_finite(delta) or delta <= 0.0:
		return []
	if not _validate_attempt():
		return []
	match state:
		State.COOKING:
			elapsed += delta
			var recipe := recipe_for_item(raw_item)
			if elapsed + 0.000001 >= float(recipe.cooking_seconds):
				if not player.remove_item(raw_item):
					close("You have no more of that raw fish in your backpack.")
					return []
				_reserved_recipe = recipe
				flip_window = reaction_window(player.get_skill_level("cooking"), recipe)
				flip_elapsed = 0.0
				state = State.FLIP_PENDING
				message = "FLIP! Press Space / Enter or click the button."
				# Start a full window on the next frame: never charge unseen prompt time.
		State.FLIP_PENDING:
			if not is_inf(flip_window):
				flip_elapsed += delta
				if flip_elapsed + 0.000001 >= flip_window:
					return _resolve(true)
		State.FEEDBACK:
			feedback_elapsed += delta
			if feedback_elapsed + 0.000001 >= FEEDBACK_SECONDS:
				if remaining <= 0:
					state = State.FINISHED
					_release_player()
				else:
					state = State.COOKING
					elapsed = 0.0
	return []

func flip() -> Array[Dictionary]:
	if state != State.FLIP_PENDING or not _validate_attempt():
		return []
	return _resolve(false)

func _validate_attempt() -> bool:
	var error := _conditions_error()
	if error.is_empty() and not player.get_position().is_equal_approx(start_position):
		error = "You stopped cooking because you moved."
	if error.is_empty() and player.current_hp < start_hp:
		error = "You stopped cooking because you took damage."
	var recipe := recipe_for_item(raw_item)
	if error.is_empty() and (recipe.is_empty() or player.get_skill_level("cooking") < int(recipe.cooking_level)):
		error = "You can no longer cook this fish."
	if not error.is_empty():
		close(error)
		return false
	return true

func _resolve(burnt: bool) -> Array[Dictionary]:
	if state != State.FLIP_PENDING:
		return []
	# Change state before any side effects; callbacks and repeated inputs cannot replay.
	state = State.FEEDBACK
	feedback_elapsed = 0.0
	var recipe := _reserved_recipe
	_reserved_recipe = {}
	var level_before := player.get_skill_level("cooking")
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
	message = "You burnt %s. No Cooking XP." % String(recipe.fish_species) if burnt else "Perfect flip! %s cooked. +%d Cooking XP" % [String(recipe.fish_species), xp]
	last_result = {"input": raw_item, "output": output, "burnt": burnt,
		"flip_window": flip_window, "experience": xp, "level_before": level_before,
		"level_after": player.get_skill_level("cooking")}
	return [last_result.duplicate()]

func close(reason: String = "You stopped cooking.") -> void:
	if not is_active():
		return
	# A live prompt has already reserved its ingredient. Closing cannot reset risk.
	if state == State.FLIP_PENDING:
		_resolve(true)
	state = State.CANCELLED
	elapsed = 0.0
	message = reason
	_release_player()

func _release_player() -> void:
	if player != null and player.active_cooking_session != null and player.active_cooking_session.get_ref() == self:
		player.active_cooking_session = null

func _conditions_error() -> String:
	if player == null:
		return "There is no cook."
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
