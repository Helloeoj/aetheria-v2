class_name CharacterCodec
extends RefCounted
## Versioned server saves contain approved item IDs, never client item statistics.
const VERSION := 4
const OrderBook := preload("res://scripts/orders/order_book.gd")
const MAX_COUNT := 2147483647
const MAX_INVENTORY_ENTRIES := 4096
const TIMERS := ["food_cooldown_seconds", "food_attack_cooldown_seconds", "food_attack_interval_seconds"]

static func initial(username: String, character_id: String, region_id: String) -> Dictionary:
	var p := PlayerState.new(username)
	p.entity_id = character_id
	p.add_item("Beginner Rod")
	p.add_item("Low Grade Fish Food", 30)
	p.cycle_known_spell(1)
	return {"ok": true, "player": p, "region_id": region_id}

static func encode(p: PlayerState, region_id: String) -> Dictionary:
	if not OrderBook.inventory_valid(p):
		return {} # Invalid authoritative state must fail persistence, never erase orders.
	var inventory: Array = []
	var names := p.backpack.keys()
	names.sort()
	for item_name: String in names:
		var item := GameData.get_item_by_name(item_name)
		inventory.append({"item_id": int(item.get("id", 0)), "count": int(p.backpack[item_name])})
	var equipment := {}
	for slot: String in p.equipment:
		equipment[slot] = int(p.equipment[slot].get("id", 0))
	var pale: Array = []
	for item_name: String in p.fishing_pale:
		pale.append(int(GameData.get_item_by_name(item_name).get("id", 0)))
	var state := {
		"version": VERSION, "region_id": region_id, "x": p.x, "y": p.y,
		"skill_experience": p.skill_experience.duplicate(true), "hp": p.current_hp,
		"mana": p.current_mana, "gold": p.gold, "inventory": inventory,
		"equipment": equipment, "fishing_pale": pale,
		"quiver_item_id": int(p.quiver_item.get("id", 0)), "quiver_amount": p.quiver_amount,
		"quick_food_id": int(GameData.get_item_by_name(p.quick_food_name).get("id", 0)),
		"attack_style": p.attack_style, "selected_spell_id": p.selected_spell_id,
		"dead_man_orders": p.dead_man_orders.duplicate(true),
	}
	for timer: String in TIMERS:
		state[timer] = p.get(timer)
	return state

static func decode(state: Dictionary, username: String, character_id: String) -> Dictionary:
	return _decode(state,username,character_id,false)

static func _decode(state: Dictionary, username: String, character_id: String, projection: bool) -> Dictionary:
	if state.has("public_projection") or state.has("orders_view"):
		return _bad("save_projection")
	var version := _integer(state.get("version", -1), VERSION)
	if version not in [1, 2, 3, VERSION]:
		return _bad("save_version")
	var book: Variant = state.get("dead_man_orders", OrderBook.empty_book() if version < 3 else null)
	var legacy_orders: bool = version < 4 and book is Dictionary and book.get("version") == 1
	if legacy_orders:
		book = OrderBook.migrate_legacy(book,character_id)
	if not OrderBook.validate_book(book, character_id):
		return _bad("save_orders")
	if not state.get("region_id") is String or String(state.region_id).length() > 64:
		return _bad("save_location")
	if not _finite(state.get("x")) or not _finite(state.get("y")):
		return _bad("save_location")
	var p := PlayerState.new(username)
	p.entity_id = character_id
	p.dead_man_orders = book.duplicate(true)
	p.x = float(state.x)
	p.y = float(state.y)
	var experience: Variant = state.get("skill_experience")
	if not experience is Dictionary:
		return _bad("save_skills")
	for skill: String in SkillProgression.SKILL_IDS:
		# Only the new, absent field migrates. Never repair corrupt old fields.
		var fallback := 0 if version == 1 and skill == "mining" else -1
		var amount := _integer(experience.get(skill, fallback), SkillProgression.MAX_EXPERIENCE)
		if amount < 0:
			return _bad("save_skills")
		p.skill_experience[skill] = amount
		p.levels[skill] = SkillProgression.level_for_experience(amount)
	p.magic_level = int(p.levels.magic)
	p.magic_experience = int(p.skill_experience.magic)
	p.gold = _integer(state.get("gold", -1), MAX_COUNT)
	p.current_hp = _integer(state.get("hp", -1), p.get_max_hp())
	p.current_mana = _integer(state.get("mana", -1), p.get_max_mana())
	if p.gold < 0 or p.current_hp < 0 or p.current_mana < 0:
		return _bad("save_vitals")
	var inventory: Variant = state.get("inventory")
	if not inventory is Array or inventory.size() > MAX_INVENTORY_ENTRIES:
		return _bad("save_inventory")
	p.backpack.clear()
	for entry: Variant in inventory:
		if not entry is Dictionary:
			return _bad("save_inventory")
		var item := _item(entry.get("item_id"))
		var count := _integer(entry.get("count"), MAX_COUNT)
		if item.is_empty() or count <= 0 or p.backpack.has(String(item.name)):
			return _bad("save_inventory")
		p.backpack[String(item.name)] = count
	if legacy_orders and not projection:
		for tier: String in OrderBook.TIERS:
			var name := OrderBook.opened_name(tier)
			if p.backpack.has(name):
				return _bad("save_orders_inventory")
			if book.orders.get(tier,{}).get("state","") in OrderBook.LIVE_STATES:
				if not InventorySystem.can_add_to_backpack(p,name,1):
					return _bad("save_orders_inventory")
				p.backpack[name] = 1
	if not projection and not OrderBook.inventory_valid(p):
		return _bad("save_orders_inventory")
	var equipment: Variant = state.get("equipment")
	if not equipment is Dictionary:
		return _bad("save_equipment")
	for slot: String in p.equipment:
		var id := _integer(equipment.get(slot, -1), MAX_COUNT)
		if id < 0:
			return _bad("save_equipment")
		if id == 0:
			p.equipment[slot] = {}
			continue
		var item := _item(id)
		var expected_slot := "ring" if slot.begins_with("ring") else slot
		if item.is_empty() or item.get("slot") != expected_slot:
			return _bad("save_equipment")
		p.equipment[slot] = item.duplicate(true)
	var pale: Variant = state.get("fishing_pale")
	if not pale is Array or pale.size() != PlayerState.FISHING_PALE_SIZE:
		return _bad("save_pale")
	for index in pale.size():
		var id := _integer(pale[index], MAX_COUNT)
		if id < 0:
			return _bad("save_pale")
		if id == 0:
			p.fishing_pale[index] = ""
			continue
		var item := _item(id)
		if item.is_empty() or item.get("fish_state", "") != "raw":
			return _bad("save_pale")
		p.fishing_pale[index] = String(item.name)
	var quiver_id := _integer(state.get("quiver_item_id", -1), MAX_COUNT)
	p.quiver_amount = _integer(state.get("quiver_amount", -1), MAX_COUNT)
	if quiver_id < 0 or p.quiver_amount < 0 or (quiver_id == 0 and p.quiver_amount != 0):
		return _bad("save_quiver")
	if quiver_id > 0:
		p.quiver_item = _item(quiver_id).duplicate(true)
		if p.quiver_item.is_empty() or p.quiver_item.get("slot") != "quiver":
			return _bad("save_quiver")
	var food_id := _integer(state.get("quick_food_id", -1), MAX_COUNT)
	if food_id < 0:
		return _bad("save_food")
	if food_id > 0:
		var food := _item(food_id)
		if food.is_empty() or int(food.get("food_healing", 0)) <= 0:
			return _bad("save_food")
		p.quick_food_name = String(food.name)
	var style: Variant = state.get("attack_style")
	if not style is String or style not in PlayerStats.ALL_STYLES:
		return _bad("save_style")
	p.attack_style = style
	var spell: Variant = state.get("selected_spell_id")
	if not spell is String or (not spell.is_empty() and not GameData.is_spell_unlocked(spell, p.magic_level)):
		return _bad("save_spell")
	p.selected_spell_id = spell
	for timer: String in TIMERS:
		if not _finite(state.get(timer)) or float(state[timer]) < 0.0 or float(state[timer]) > 3600.0:
			return _bad("save_timer")
		p.set(timer, float(state[timer]))
	return {"ok": true, "player": p, "region_id": String(state.region_id)}

static func public_state(full_saved: Dictionary) -> Dictionary:
	var projected := full_saved.duplicate(true)
	projected.erase("dead_man_orders")
	projected["public_projection"] = true
	projected["orders_view"] = OrderBook.public_book(full_saved.get("dead_man_orders", OrderBook.empty_book()))
	return projected

static func decode_public(state: Dictionary, username: String, character_id: String) -> Dictionary:
	if state.get("public_projection") != true or state.has("dead_man_orders") or not state.get("orders_view") is Dictionary:
		return _bad("save_projection")
	var base := state.duplicate(true)
	base.erase("public_projection")
	base.erase("orders_view")
	base["dead_man_orders"] = OrderBook.empty_book()
	var decoded := _decode(base, username, character_id, true)
	if decoded.ok:
		decoded.player.orders_view = state.orders_view.duplicate(true)
	return decoded

static func apply_to(p: PlayerState, saved: Dictionary) -> bool:
	var projected: bool = saved.get("public_projection") == true
	var decoded := decode_public(saved, p.name, p.entity_id) if projected else decode(saved, p.name, p.entity_id)
	if not decoded.ok:
		return false
	var other: PlayerState = decoded.player
	for field: String in ["levels", "skill_experience", "current_hp", "current_mana", "gold", "backpack", "equipment", "fishing_pale", "quiver_item", "quiver_amount", "quick_food_name", "attack_style", "selected_spell_id", "magic_level", "magic_experience", "x", "y"]:
		p.set(field, other.get(field))
	for field: String in TIMERS:
		p.set(field, other.get(field))
	if projected:
		p.orders_view = other.orders_view.duplicate(true)
	else:
		p.dead_man_orders = other.dead_man_orders.duplicate(true)
	return true

static func _item(value: Variant) -> Dictionary:
	var id := _integer(value, MAX_COUNT)
	return {} if id <= 0 else GameData.get_item(id)

static func _integer(value: Variant, maximum: int) -> int:
	if not _finite(value) or float(value) < 0.0 or float(value) > float(maximum) or floor(float(value)) != float(value):
		return -1
	return int(value)

static func _finite(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) <= 2147483647.0

static func _bad(code: String) -> Dictionary:
	return {"ok": false, "code": code, "message": "The saved character needs recovery. It has not been replaced."}
