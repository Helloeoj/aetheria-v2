# goblin_loot.py

goblin_loot_table = {
    "Goblin Scout": {
        "tier": 1,
        "gold": {"min": 3, "max": 8},
        "loot": [
            {"item": "Goblin Hide", "type": "treasure", "chance": 65, "quantity": [1, 2]},
            {"item": "Raw Meat", "type": "food", "chance": 30},
            {"item": "Bronze Dagger", "type": "weapon", "chance": 2},
            {"item": "Wood Shaft", "type": "crafting", "chance": 25, "quantity": [1, 2]},
        ]
    },
    "Goblin Worker": {
        "tier": 2,
        "gold": {"min": 15, "max": 40},
        "loot": [
            {"item": "Goblin Hide", "type": "treasure", "chance": 70, "quantity": [1, 2]},
            {"item": "Ore Chunk", "type": "crafting", "chance": 40, "quantity": [1, 3]},
            {"item": "Iron Pickaxe", "type": "weapon", "chance": 1},
            {"item": "Raw Meat", "type": "food", "chance": 25},
            {"item": "Goblin Tooth", "type": "treasure", "chance": 35},
        ]
    },
    "Goblin Warrior": {
        "tier": 3,
        "gold": {"min": 50, "max": 120},
        "loot": [
            {"item": "Goblin Hide", "type": "treasure", "chance": 75, "quantity": [1, 2]},
            {"item": "Steel Shortsword", "type": "weapon", "chance": 1},
            {"item": "Goblin Bone", "type": "treasure", "chance": 40},
            {"item": "Iron Chestplate", "type": "armor", "chance": 1},
            {"item": "Poison Gland", "type": "crafting", "chance": 20},
        ]
    },
    "Goblin Ranger": {
        "tier": 4,
        "gold": {"min": 140, "max": 250},
        "loot": [
            {"item": "Goblin Hide", "type": "treasure", "chance": 80, "quantity": [1, 3]},
            {"item": "Blacksteel Bow", "type": "weapon", "chance": 1},
            {"item": "Poisoned Arrows", "type": "ammo", "chance": 50, "quantity": [5, 12]},
            {"item": "Worn Quiver", "type": "armor", "chance": 1},
            {"item": "Venom Sac", "type": "crafting", "chance": 30},
            {"item": "Goblin Bone", "type": "treasure", "chance": 35},
        ]
    },
    "Goblin Mage": {
        "tier": 5,
        "gold": {"min": 300, "max": 500},
        "loot": [
            {"item": "Goblin Hide", "type": "treasure", "chance": 65},
            {"item": "Mithril Wand", "type": "weapon", "chance": 1},
            {"item": "Lesser Fire Essence", "type": "enchantment", "chance": 20},
            {"item": "Enchanted Cloth", "type": "crafting", "chance": 35},
            {"item": "Goblin Tooth", "type": "treasure", "chance": 40},
        ]
    },
    "Goblin Chieftain": {
        "tier": 5,
        "gold": {"min": 300, "max": 500},
        "loot": [
            {"item": "Goblin Hide", "type": "treasure", "chance": 85, "quantity": [2, 4]},
            {"item": "Goblin Crown Fragment", "type": "treasure", "chance": 45},
            {"item": "Mithril War Axe", "type": "weapon", "chance": 1},
            {"item": "Greater Enchantment Orb", "type": "enchantment", "chance": 15},
            {"item": "Goblin Ring", "type": "armor", "chance": 1},
            {"item": "Venom Sac", "type": "crafting", "chance": 30},
        ]
    }
}