extends LootSystem
## Deterministic fixture, loaded after GameData is ready by item_visuals_smoke.
var fixed_items: Array = []
func roll_monster_loot(_monster: Variant) -> Dictionary:
	return {"gold":7,"items":fixed_items}
