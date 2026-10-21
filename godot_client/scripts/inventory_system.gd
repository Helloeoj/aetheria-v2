class_name InventorySystem
extends RefCounted

static func normalize_backpack(player: Variant) -> void:
	# Merge historical display names without deleting stacks or changing IDs.
	for old_name: Variant in player.backpack.keys():
		var canonical := GameData.canonical_item_name(String(old_name))
		if canonical == String(old_name):
			continue
		var count := int(player.backpack[old_name])
		player.backpack[canonical] = int(player.backpack.get(canonical, 0)) + count
		player.backpack.erase(old_name)

static func is_stackable(item_name: String) -> bool:
	var item := GameData.get_item_by_name(item_name)
	# Backpack quantities remain compatible with saves, shops and item transfer.
	# Raw, cooked and burnt fish each occupy an individual slot.
	return String(item.get("fish_species", "")).is_empty()

static func inventory_slots(player: Variant) -> Array[Dictionary]:
	normalize_backpack(player)
	var names: Array[String] = []
	for item_name: String in player.backpack:
		if int(player.backpack[item_name]) > 0:
			names.append(item_name)
	names.sort()
	var slots: Array[Dictionary] = []
	for item_name: String in names:
		var quantity := int(player.backpack[item_name])
		if is_stackable(item_name):
			slots.append({"name": item_name, "quantity": quantity})
		else:
			for _copy_index in range(quantity):
				slots.append({"name": item_name, "quantity": 1})
	return slots

static func add_to_backpack(player: Variant, item_name: String, amount: int = 1) -> void:
	normalize_backpack(player)
	item_name = GameData.canonical_item_name(item_name)
	AetheriaDiagnostics.event("Inventory", "add item", {"item": item_name, "amount": amount})
	if amount <= 0:
		return
	player.backpack[item_name] = int(player.backpack.get(item_name, 0)) + amount

static func remove_from_backpack(player: Variant, item_name: String, amount: int = 1) -> bool:
	normalize_backpack(player)
	item_name = GameData.canonical_item_name(item_name)
	AetheriaDiagnostics.event("Inventory", "remove item", {"item": item_name, "amount": amount})
	if amount <= 0:
		return true
	var current := int(player.backpack.get(item_name, 0))
	if current < amount:
		return false
	if current == amount:
		player.backpack.erase(item_name)
	else:
		player.backpack[item_name] = current - amount
	return true

static func equip_item(player: Variant, item_name: String) -> String:
	normalize_backpack(player)
	item_name = GameData.canonical_item_name(item_name)
	AetheriaDiagnostics.event("Equipment", "equip item", {"item": item_name})
	var item := GameData.get_item_by_name(item_name)
	if item.is_empty():
		AetheriaDiagnostics.report("Equipment", "Unknown item requested for equipment", {"item": item_name})
		return "Item '%s' does not exist." % item_name
	var stack_count := int(player.backpack.get(item_name, 0))
	if stack_count <= 0:
		return "%s has no %s to equip." % [player.name, item_name]
	var slot_value: Variant = item.get("slot", null)
	if slot_value == null:
		return "%s cannot be equipped." % String(item.get("name", item_name))
	var slot := String(slot_value)
	# Validate before replacing equipment or transferring any backpack/quiver
	# stacks so a failed requirement leaves the entire inventory unchanged.
	var unmet_requirement := EquipmentProgression.unmet_requirement_text(player, item)
	if not unmet_requirement.is_empty():
		return "%s: %s." % [item_name, unmet_requirement]
	if slot == "quiver":
		if not player.quiver_item.is_empty():
			if String(player.quiver_item.get("name", "")) == item_name:
				player.quiver_amount += stack_count
				player.backpack.erase(item_name)
				return "Loaded %d more %s into quiver (total %d)." % [stack_count, item_name, player.quiver_amount]
			add_to_backpack(player, String(player.quiver_item.get("name", "")), player.quiver_amount)
			player.quiver_item = {}
			player.quiver_amount = 0
		player.quiver_item = item
		player.quiver_amount = stack_count
		player.backpack.erase(item_name)
		return "Loaded %dx %s into quiver." % [player.quiver_amount, item_name]
	if slot == "weapon":
		_unequip_and_store(player, "weapon")
		if EquipmentUtils.is_two_handed(item):
			_unequip_and_store(player, "shield")
		if not remove_from_backpack(player, item_name, 1):
			return "%s has no %s to equip." % [player.name, item_name]
		player.equipment["weapon"] = item
		return "%s equipped %s as weapon." % [player.name, item_name]
	if slot == "shield":
		var equipped_weapon: Dictionary = player.equipment.get("weapon", {})
		if EquipmentUtils.is_two_handed(equipped_weapon):
			return "Cannot equip %s because %s is two-handed." % [item_name, String(equipped_weapon.get("name", "weapon"))]
		_unequip_and_store(player, "shield")
		if not remove_from_backpack(player, item_name, 1):
			return "%s has no %s to equip." % [player.name, item_name]
		player.equipment["shield"] = item
		return "%s equipped %s as shield." % [player.name, item_name]
	if slot in ["head", "chest", "legs", "cape", "neck"]:
		_unequip_and_store(player, slot)
		if not remove_from_backpack(player, item_name, 1):
			return "%s has no %s to equip." % [player.name, item_name]
		player.equipment[slot] = item
		return "%s equipped %s on %s." % [player.name, item_name, slot]
	if slot == "ring":
		if not remove_from_backpack(player, item_name, 1):
			return "%s has no %s to equip." % [player.name, item_name]
		var ring_one: Dictionary = player.equipment.get("ring1", {})
		var ring_two: Dictionary = player.equipment.get("ring2", {})
		if ring_one.is_empty():
			player.equipment["ring1"] = item
			return "%s equipped %s in ring slot 1." % [player.name, item_name]
		if ring_two.is_empty():
			player.equipment["ring2"] = item
			return "%s equipped %s in ring slot 2." % [player.name, item_name]
		add_to_backpack(player, String(ring_one.get("name", "")), 1)
		player.equipment["ring1"] = item
		return "%s replaced ring slot 1 with %s." % [player.name, item_name]
	return "%s cannot be equipped." % item_name

static func unequip_slot(player: Variant, slot_name: String) -> String:
	AetheriaDiagnostics.event("Equipment", "unequip slot", {"slot": slot_name})
	if slot_name == "quiver":
		if not player.quiver_item.is_empty() and player.quiver_amount > 0:
			var item_name := String(player.quiver_item.get("name", ""))
			var amount: int = int(player.quiver_amount)
			add_to_backpack(player, item_name, amount)
			player.quiver_item = {}
			player.quiver_amount = 0
			return "Unequipped quiver: returned %dx %s to backpack." % [amount, item_name]
		return "Nothing to unequip from quiver."
	if not player.equipment.has(slot_name):
		return "Unknown slot '%s'." % slot_name
	var current: Dictionary = player.equipment.get(slot_name, {})
	if current.is_empty():
		return "Nothing to unequip from %s." % slot_name
	var item_name := String(current.get("name", ""))
	add_to_backpack(player, item_name, 1)
	player.equipment[slot_name] = {}
	return "Unequipped %s from %s." % [item_name, slot_name]

static func _unequip_and_store(player: Variant, slot_name: String) -> void:
	var current: Dictionary = player.equipment.get(slot_name, {})
	if not current.is_empty():
		add_to_backpack(player, String(current.get("name", "")), 1)
		player.equipment[slot_name] = {}
