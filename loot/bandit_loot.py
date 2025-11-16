# bandit_loot.py

bandit_loot_table = {
    "Bandit Cutpurse": {
        "tier": 1,
        "gold": {"min": 5, "max": 12},
        "loot": [
            {"item": "Bronze Dagger", "type": "weapon", "chance": 2},
            {"item": "Bronze Shortsword", "type": "weapon", "chance": 2},
            {"item": "Bronze Boots", "type": "armor", "chance": 2},
            {"item": "Bronze Helmet", "type": "armor", "chance": 2},
            {"item": "Stolen Ring", "type": "armor", "chance": 1},
            {"item": "Copper Coins", "type": "treasure", "chance": 60, "quantity": [1, 3]},
            {"item": "Ripped Cloth", "type": "crafting", "chance": 25},
            {"item": "Bronze Arrowheads", "type": "crafting", "chance": 20, "quantity": [2, 5]}
        ]
    },
    "Bandit Footpad": {
        "tier": 2,
        "gold": {"min": 20, "max": 40},
        "loot": [
            {"item": "Iron Dagger", "type": "weapon", "chance": 1},
            {"item": "Iron Shortsword", "type": "weapon", "chance": 1},
            {"item": "Iron Chestplate", "type": "armor", "chance": 1},
            {"item": "Iron Gloves", "type": "armor", "chance": 1},
            {"item": "Bandit Band", "type": "armor", "chance": 1},
            {"item": "Silver Coins", "type": "treasure", "chance": 55, "quantity": [1, 2]},
            {"item": "Torn Map Fragment", "type": "treasure", "chance": 30},
            {"item": "Iron Arrowheads", "type": "crafting", "chance": 25, "quantity": [2, 4]}
        ]
    },
    "Bandit Enforcer": {
        "tier": 3,
        "gold": {"min": 60, "max": 110},
        "loot": [
            {"item": "Steel Sword", "type": "weapon", "chance": 1},
            {"item": "Steel Axe", "type": "weapon", "chance": 1},
            {"item": "Steel Greaves", "type": "armor", "chance": 1},
            {"item": "Steel Helmet", "type": "armor", "chance": 1},
            {"item": "Bandit Cloak", "type": "armor", "chance": 1},
            {"item": "Stolen Silver", "type": "treasure", "chance": 50, "quantity": [1, 2]},
            {"item": "Bandit Orders", "type": "treasure", "chance": 35},
            {"item": "Steel Arrowheads", "type": "crafting", "chance": 20, "quantity": [3, 5]}
        ]
    },
    "Bandit Sharpshooter": {
        "tier": 4,
        "gold": {"min": 140, "max": 240},
        "loot": [
            {"item": "Blacksteel Bow", "type": "weapon", "chance": 1},
            {"item": "Blacksteel Crossbow", "type": "weapon", "chance": 1},
            {"item": "Blacksteel Chestplate", "type": "armor", "chance": 1},
            {"item": "Blacksteel Boots", "type": "armor", "chance": 1},
            {"item": "Onyx Pendant", "type": "armor", "chance": 1},
            {"item": "Stolen Gem", "type": "treasure", "chance": 50},
            {"item": "Battle Plans", "type": "treasure", "chance": 30},
            {"item": "Blacksteel Arrowheads", "type": "crafting", "chance": 20, "quantity": [4, 6]}
        ]
    },
    "Bandit Sorcerer": {
        "tier": 5,
        "gold": {"min": 300, "max": 480},
        "loot": [
            {"item": "Mithril Wand", "type": "weapon", "chance": 1},
            {"item": "Mithril Orb", "type": "weapon", "chance": 1},
            {"item": "Mithril Robe", "type": "armor", "chance": 1},
            {"item": "Mithril Spellbook", "type": "armor", "chance": 1},
            {"item": "Sorcerer Ring", "type": "armor", "chance": 1},
            {"item": "Encrypted Scroll", "type": "treasure", "chance": 45},
            {"item": "Enchanted Cloth", "type": "crafting", "chance": 35},
            {"item": "Mithril Arrowheads", "type": "crafting", "chance": 15, "quantity": [3, 5]}
        ]
    },
    "Bandit Boss": {
        "tier": 5,
        "gold": {"min": 300, "max": 500},
        "loot": [
            {"item": "Mithril War Axe", "type": "weapon", "chance": 1},
            {"item": "Mithril Greatsword", "type": "weapon", "chance": 1},
            {"item": "Mithril Helmet", "type": "armor", "chance": 1},
            {"item": "Mithril Legplates", "type": "armor", "chance": 1},
            {"item": "Ring of Plunder", "type": "armor", "chance": 1},
            {"item": "Warlord's Crest", "type": "treasure", "chance": 45},
            {"item": "Encrypted Orders", "type": "treasure", "chance": 35},
            {"item": "Mithril Arrowheads", "type": "crafting", "chance": 15, "quantity": [3, 5]}
        ]
    }
}
