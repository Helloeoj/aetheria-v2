extends MiningDefinitions
## Catalog prerequisite double: no item is created or inserted into GameData.
## ID 0 is an unbound tool handle, never a reward or inventory entry.
var owned := true
var tool_level := 1
var interval := 3.0

func pickaxe(_item_id: int) -> Dictionary:
	return {"item_id": 0, "required_level": tool_level, "attempt_interval_seconds": interval}

func owns_pickaxe(_player: PlayerState, _tool: Dictionary) -> bool:
	return owned

func best_pickaxe(player: PlayerState) -> Dictionary:
	return pickaxe(0) if owned and player.get_skill_level("mining") >= tool_level else {}
