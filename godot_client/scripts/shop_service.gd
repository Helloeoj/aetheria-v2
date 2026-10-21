class_name ShopService
extends RefCounted

const Acquisition = preload("res://scripts/acquisition_rules.gd")
const MAX_BATCH := 1000

static func stock() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Dictionary in GameData.items:
		if Acquisition.can_purchase(item) and String(item.get("type", "")) in ["Fishing Pole", "Fishing Bait"]:
			result.append(item.duplicate(true))
	return result

static func purchase(player: PlayerState, item_name: String, quantity: int = 1) -> Dictionary:
	if player == null or player.current_hp <= 0 or player.in_combat:
		return {"ok": false, "message": "Finish combat before shopping."}
	if quantity < 1 or quantity > MAX_BATCH:
		return {"ok": false, "message": "Choose between 1 and %d items." % MAX_BATCH}
	var item: Dictionary = GameData.get_item_by_name(item_name)
	if item.is_empty() or not Acquisition.can_purchase(item) or String(item.get("type", "")) not in ["Fishing Pole", "Fishing Bait"]:
		return {"ok": false, "message": "The bait store does not sell that item."}
	var price := int(item.get("buy_price", 0))
	if price <= 0 or price > 2147483647 / quantity:
		return {"ok": false, "message": "This item's shop price has not been set."}
	var total := price * quantity
	if player.gold < total:
		return {"ok": false, "message": "You need %d gold." % total}
	var canonical := String(item.name)
	if int(player.backpack.get(canonical, 0)) > 2147483647 - quantity:
		return {"ok": false, "message": "There is no room in that item stack."}
	player.gold -= total
	player.add_item(canonical, quantity)
	return {"ok": true, "message": "Bought %d × %s for %d gold." % [quantity, canonical, total]}
