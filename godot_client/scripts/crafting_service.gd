class_name CraftingService
extends RefCounted
## Immediate, atomic backpack exchanges. Pending recipes never consume materials.

const RECIPE_PATH := "res://data/recipes.json"
const MAX_BATCH := 2147483647
const MAX_COUNT := 9223372036854775807
const ELEMENTS := ["fire", "ice", "lightning", "hurricane"]

static func list_recipes(station: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not FileAccess.file_exists(RECIPE_PATH):
		return result
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECIPE_PATH))
	if not parsed is Array:
		return result
	for value: Variant in parsed:
		if not value is Dictionary:
			continue
		var recipe: Dictionary = value
		if station.is_empty() or String(recipe.get("station", "")) == station:
			result.append(recipe.duplicate(true))
	return result

static func craft(player: PlayerState, recipe_id: String, station: String, quantity: int = 1) -> Dictionary:
	if player == null:
		return _failure("There is no crafter.")
	if player.current_hp <= 0:
		return _failure("You must be alive to craft.")
	if player.in_combat or not player.current_target.is_empty():
		return _failure("You cannot craft during combat.")
	if player.active_cooking_session != null and player.active_cooking_session.get_ref() != null:
		return _failure("Finish cooking before crafting another item.")
	if quantity <= 0 or quantity > MAX_BATCH:
		return _failure("Choose a positive, supported batch quantity.")
	var recipe := _find_recipe(recipe_id)
	if recipe.is_empty():
		return _failure("Unknown crafting recipe.")
	if not bool(recipe.get("enabled", false)):
		return _failure(String(recipe.get("reason", "This recipe is awaiting approved ingredients and quantities.")))
	if station.is_empty() or String(recipe.get("station", "")) != station:
		return _failure("Use this recipe at the " + String(recipe.get("station", "required station")) + ".")
	var inputs := _quantities(recipe.get("inputs", []), quantity)
	if not bool(inputs.ok):
		return inputs
	var outputs := _quantities(recipe.get("outputs", []), quantity)
	if not bool(outputs.ok):
		return outputs
	for output_name: String in outputs.items:
		if not _output_allowed(recipe_id, output_name):
			return _failure("This item cannot be manufactured by crafting.")
	for item_name: String in inputs.items:
		var available := _available(player.backpack, item_name)
		if available < int(inputs.items[item_name]):
			return _failure("You need %d %s in your backpack." % [int(inputs.items[item_name]), item_name])
	# Prepare a complete replacement before changing the live inventory. Failed
	# validation or a missing second ingredient can never consume the first one.
	var next_backpack := player.backpack.duplicate(true)
	for item_name: String in inputs.items:
		_consume(next_backpack, item_name, int(inputs.items[item_name]))
	for item_name: String in outputs.items:
		var amount := int(outputs.items[item_name])
		var current := _available(next_backpack, item_name)
		if current < 0 or current > MAX_COUNT - amount:
			return _failure("That output would exceed a supported inventory quantity.")
		next_backpack[item_name] = int(next_backpack.get(item_name, 0)) + amount
	player.backpack = next_backpack
	return {"ok": true, "message": "Created %s." % String(recipe.get("name", recipe_id)),
		"outputs": outputs.items.duplicate(true), "quantity": quantity}

static func empower_orb(player: PlayerState, element: String) -> Dictionary:
	var normalized := element.strip_edges().to_lower()
	if normalized not in ELEMENTS:
		return _failure("Choose Fire, Ice, Lightning or Hurricane.")
	return craft(player, "empower_" + normalized + "_orb", "enchanting")

static func _find_recipe(recipe_id: String) -> Dictionary:
	for recipe: Dictionary in list_recipes():
		if String(recipe.get("id", "")) == recipe_id:
			return recipe
	return {}

static func _quantities(entries: Variant, quantity: int) -> Dictionary:
	if not entries is Array or entries.is_empty():
		return _failure("This recipe has no approved ingredients or output.")
	var amounts := {}
	for entry: Variant in entries:
		if not entry is Dictionary:
			return _failure("This recipe has an invalid item definition.")
		var item := GameData.get_item_by_name(String(entry.get("item", "")))
		if item.is_empty():
			return _failure("A recipe item is unavailable: " + String(entry.get("item", "")))
		var raw_count: Variant = entry.get("quantity", 0)
		if not (raw_count is int or raw_count is float):
			return _failure("This recipe has an invalid ingredient quantity.")
		var numeric_count := float(raw_count)
		if not is_finite(numeric_count) or numeric_count < 1.0 or numeric_count > float(MAX_BATCH) or floor(numeric_count) != numeric_count:
			return _failure("This recipe has an invalid ingredient quantity.")
		# Each factor fits a signed 32-bit integer, so multiplication fits int64.
		var amount := int(raw_count) * quantity
		var canonical_name := String(item.get("name", ""))
		if canonical_name.is_empty() or int(amounts.get(canonical_name, 0)) > MAX_COUNT - amount:
			return _failure("This recipe exceeds a supported ingredient quantity.")
		amounts[canonical_name] = int(amounts.get(canonical_name, 0)) + amount
	return {"ok": true, "items": amounts}

static func _available(backpack: Dictionary, canonical_name: String) -> int:
	var total := 0
	for key: Variant in backpack:
		var item := GameData.get_item_by_name(String(key))
		if String(item.get("name", "")) != canonical_name:
			continue
		var raw_count: Variant = backpack[key]
		if not raw_count is int or int(raw_count) < 0 or total > MAX_COUNT - int(raw_count):
			return -1
		total += int(raw_count)
	return total

static func _consume(backpack: Dictionary, canonical_name: String, quantity: int) -> void:
	var remaining := quantity
	for key: Variant in backpack.keys():
		var item := GameData.get_item_by_name(String(key))
		if String(item.get("name", "")) != canonical_name:
			continue
		var amount := mini(remaining, int(backpack[key]))
		backpack[key] = int(backpack[key]) - amount
		remaining -= amount
		if int(backpack[key]) == 0:
			backpack.erase(key)
		if remaining == 0:
			return

static func _output_allowed(recipe_id: String, item_name: String) -> bool:
	var item := GameData.get_item_by_name(item_name)
	var slot: Variant = item.get("slot", null)
	if (slot != null and String(slot) in ["ring", "neck"]) or int(item.get("tier", 0)) > 7:
		return false
	if item_name == "Magic Orb" or item_name.ends_with(" Sigil"):
		return false
	if item_name.ends_with(" Orb"):
		for element: String in ELEMENTS:
			if item_name == element.capitalize() + " Orb":
				return recipe_id == "empower_" + element + "_orb"
		return false
	return true

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
