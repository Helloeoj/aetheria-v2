# loot_tables.py

from .goblin_loot import goblin_loot_table
from .skeleton_loot import skeleton_loot_table
from .bandit_loot import bandit_loot_table

# Combine all race-specific loot tables into a master dictionary
master_loot_table = {
    **goblin_loot_table,
    **skeleton_loot_table,
    **bandit_loot_table,
    # Add more tables as you modularize them
}

def roll_loot(monster_name):
    """
    Rolls loot for a given monster after death using the master loot table.
    Returns gold + one item (or stack), or an error if monster is not found.
    """
    import random

    if monster_name not in master_loot_table:
        return {"error": f"Loot table not found for: {monster_name}"}

    monster_data = master_loot_table[monster_name]

    # Roll gold drop
    gold = random.randint(monster_data["gold"]["min"], monster_data["gold"]["max"])

    # Build weighted item pool
    weighted_pool = []
    for item in monster_data["loot"]:
        weighted_pool.extend([item] * item["chance"])

    # Choose a single item
    dropped_item = random.choice(weighted_pool)
    loot_result = {
        "gold": gold,
        "item": {
            "name": dropped_item["item"],
            "type": dropped_item["type"]
        }
    }

    # If item has stackable quantity
    if "quantity" in dropped_item:
        loot_result["item"]["quantity"] = random.randint(*dropped_item["quantity"])

    return loot_result
