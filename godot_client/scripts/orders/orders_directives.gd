extends RefCounted
## Reusable directive capabilities. World content is supplied separately.
const KINDS := ["riddle","search","cipher","fishing","cooking","mining","crafting","equipment","combat"]
const INTERACTIONS := ["riddle","search","cipher","equipment"]
const EVENTS := ["fishing","cooking","mining","crafting","combat"]
const DEFERRED := {"contact":"An implemented NPC dialogue/completion system is required.",
	"cursed":"Approved cursed-pirate encounters, ownership and recovery rules are required."}
const Acquisition := preload("res://scripts/acquisition_rules.gd")

static func is_interaction(kind: String) -> bool:
	return kind in INTERACTIONS

static func is_event(kind: String) -> bool:
	return kind in EVENTS

static func equipment_levels(item: Dictionary) -> Dictionary:
	var result := {}
	for skill: String in EquipmentProgression.requirements(item):
		var level := int(EquipmentProgression.requirements(item)[skill])
		if level > 0 and level <= SkillProgression.MAX_LEVEL: result[skill] = level
	return result

static func meets_requirements(player: Variant, directive: Dictionary) -> bool:
	var skill := String(directive.get("skill",""))
	if not skill.is_empty() and player.get_skill_level(skill) < int(directive.get("level",0)):
		return false
	if directive.kind != "equipment": return true
	var item := GameData.get_item_by_name(String(directive.get("item_name","")))
	if item.is_empty() or equipment_levels(item).is_empty() or not EquipmentProgression.can_equip(player,item):
		return false
	var slot := String(item.get("slot",""))
	return player.equipment.get(slot,{}).get("id",0) == item.get("id",-1)

static func validate_template(row: Dictionary, anchor: Dictionary, tiers: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for field: String in ["kind","skill","target_id","item_name"]:
		if row.has(field) and not row[field] is String:
			errors.append("Directive %s must be text." % field)
	if row.has("level"):
		var level: Variant = row.level
		if not (level is int or level is float):
			errors.append("Directive level must be a whole skill level.")
		elif not is_finite(float(level)) or float(level) != floor(float(level)) or float(level) < 0 or float(level) > SkillProgression.MAX_LEVEL:
			errors.append("Directive level must be a whole skill level.")
	var tier_ids: Variant = row.get("tiers",[])
	if not tier_ids is Array:
		errors.append("Directive tiers must be an array.")
	else:
		for tier_id: Variant in tier_ids:
			if not tier_id is String or not tiers.has(tier_id): errors.append("Directive tier is unknown.")
	if not errors.is_empty(): return errors
	var kind := String(row.get("kind",""))
	if DEFERRED.has(kind):
		errors.append(String(DEFERRED[kind]))
		return errors
	if kind not in KINDS:
		errors.append("Unknown directive handler.")
		return errors
	if kind in ["mining","crafting","combat"] and "deckhand" in row.get("tiers",[]):
		errors.append("This action type is eligible from Smuggler upward.")
	if kind == "equipment":
		var item := GameData.get_item_by_name(String(row.get("item_name","")))
		var levels := equipment_levels(item)
		if item.is_empty() or levels.is_empty() or not _obtainable_item(item):
			errors.append("Equipment needs an obtainable item with a real nonzero equip requirement.")
		if not String(row.get("skill","")).is_empty() or int(row.get("level",0)) > 0:
			errors.append("Equipment requirements come from the actual item, not an artificial directive level.")
		for tier_id: String in row.get("tiers",[]):
			var tier: Dictionary = tiers.get(tier_id,{})
			for level: int in levels.values():
				if int(tier.get("max_gates",0)) == 0 or level < int(tier.get("skill_min",0)) or level > int(tier.get("skill_max",0)):
					errors.append("Actual equipment requirement exceeds this tier's gate rules.")
	if kind == "mining":
		var definitions := MiningDefinitions.new()
		var loaded := definitions.load_data()
		var item := GameData.get_item_by_name(String(row.get("item_name","")))
		var ore := definitions.ore(int(item.get("id",0))) if loaded.ok else {}
		if row.get("skill") != "mining" or anchor.get("interaction_kind") != "mine" or ore.is_empty() or row.get("target_id") != item.get("name") or int(row.get("level",0)) < int(ore.get("required_level",101)):
			errors.append("Mining needs a real eligible ore, Mining level and matching deposit anchor.")
		var metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/mining.json"))
		var tool_available := false
		if loaded.ok and metadata is Dictionary:
			for tool: Dictionary in metadata.get("pickaxes",[]):
				var tool_item := GameData.get_item(int(tool.get("item_id",0)))
				if int(tool.required_level) <= int(row.get("level",0)) and not tool_item.is_empty() and _obtainable_item(tool_item): tool_available = true
		if not tool_available: errors.append("Mining directives await an approved obtainable pickaxe.")
	if kind == "crafting":
		if row.has("skill") or row.has("level"):
			errors.append("Crafting has no trainable skill level; use its actual recipe success.")
		var recipe := CraftingService._find_recipe(String(row.get("target_id","")))
		if recipe.is_empty() or recipe.get("enabled",false) != true or anchor.get("interaction_kind") != "craft" or anchor.get("station") != recipe.get("station"):
			errors.append("Crafting needs an existing enabled recipe and its correct station.")
		else:
			var inputs := CraftingService._quantities(recipe.get("inputs",[]),1)
			var outputs := CraftingService._quantities(recipe.get("outputs",[]),1)
			if not inputs.ok or not outputs.ok:
				errors.append("Crafting recipe inputs or outputs are unavailable.")
			else:
				if not outputs.items.has(String(row.get("item_name",""))): errors.append("Crafting target item is not a recipe output.")
				for name: String in outputs.items:
					if not CraftingService._output_allowed(String(recipe.id),name): errors.append("Crafting recipe output is restricted.")
	if kind == "combat":
		var target := String(row.get("target_id",""))
		var monster := GameData.get_monster_by_name(target)
		var targets: Variant = anchor.get("combat_targets",[])
		if monster.is_empty() or target in Acquisition.policy().get("approved_boss_names",[]) or bool(monster.get("is_boss",false)):
			errors.append("Ordinary combat needs a verified eligible non-boss monster.")
		if not targets is Array or target not in targets: errors.append("Combat target must be explicitly bound to this anchor.")
	return errors

static func _obtainable_item(item: Dictionary) -> bool:
	if item.get("legacy_placeholder",false) == true or item.get("is_artifact",false) == true or item.get("orders_exclusive",false) == true:
		return false
	if Acquisition.can_purchase(item): return true
	for recipe: Dictionary in CraftingService.list_recipes():
		if recipe.get("enabled",false) != true: continue
		for output: Dictionary in recipe.get("outputs",[]):
			if output.get("item") == item.get("name") and CraftingService._output_allowed(String(recipe.id),String(item.name)):
				return true
	if item.get("generic_loot",true) == true:
		var loot := LootSystem.new()
		for monster: Dictionary in GameData.monsters:
			if loot._get_monster_loot_table(monster).is_empty() and int(monster.get("tier",0)) >= int(item.get("tier",1)) and Acquisition.can_drop(item,monster):
				return true
	return false
