from dataclasses import dataclass
from typing import Dict, Optional


@dataclass
class Item:
    name: str
    item_type: str
    material: str = ""
    tier: int = 0
    slot: Optional[str] = None  # head, chest, legs, cape, ring, neck, weapon, shield, quiver, or None


ITEMS: Dict[str, Item] = {}


def register_item(name: str, item_type: str, material: str = "", tier: int = 0, slot: Optional[str] = None):
    if name in ITEMS:
        raise ValueError(f"Duplicate item name detected: {name}")
    ITEMS[name] = Item(name=name, item_type=item_type, material=material, tier=tier, slot=slot)


# === Registered Items with Finalized Tiers & Slots ===
# Weapons: slot="weapon"
# Armor pieces: slot based on body location (head/chest/legs/shield/ring/neck/cape)
# Non-equipment items: slot=None

# Bronze tier
register_item("Bronze Shortsword", "Weapon", "Bronze", 1, slot="weapon")
register_item("Bronze Longsword", "Weapon", "Bronze", 1, slot="weapon")
register_item("Bronze Mace", "Weapon", "Bronze", 1, slot="weapon")
register_item("Bronze Dagger", "Weapon", "Bronze", 1, slot="weapon")
register_item("Bronze Warmaul", "Weapon", "Bronze", 1, slot="weapon")  # 2h handled in code
register_item("Bronze Bow", "Weapon", "Bronze", 1, slot="weapon")      # 2h handled in code
register_item("Bronze Crossbow", "Weapon", "Bronze", 1, slot="weapon")
register_item("Bronze Magic Staff", "Weapon", "Bronze", 1, slot="weapon")  # 2h handled in code
register_item("Bronze Magic Wand", "Weapon", "Bronze", 1, slot="weapon")
register_item("Bronze Helmet", "Armor", "Bronze", 1, slot="head")
register_item("Bronze Platebody", "Armor", "Bronze", 1, slot="chest")
register_item("Bronze Platelegs", "Armor", "Bronze", 1, slot="legs")
register_item("Bronze Kiteshield", "Armor", "Bronze", 1, slot="shield")
register_item("Bronze Square Shield", "Armor", "Bronze", 1, slot="shield")
register_item("Bronze Ring", "Armor", "Bronze", 1, slot="ring")
register_item("Bronze Necklace", "Armor", "Bronze", 1, slot="neck")

# Iron tier
register_item("Iron Shortsword", "Weapon", "Iron", 2, slot="weapon")
register_item("Iron Longsword", "Weapon", "Iron", 2, slot="weapon")
register_item("Iron Mace", "Weapon", "Iron", 2, slot="weapon")
register_item("Iron Dagger", "Weapon", "Iron", 2, slot="weapon")
register_item("Iron Warmaul", "Weapon", "Iron", 2, slot="weapon")
register_item("Iron Bow", "Weapon", "Iron", 2, slot="weapon")
register_item("Iron Crossbow", "Weapon", "Iron", 2, slot="weapon")
register_item("Iron Magic Staff", "Weapon", "Iron", 2, slot="weapon")
register_item("Iron Magic Wand", "Weapon", "Iron", 2, slot="weapon")
register_item("Iron Helmet", "Armor", "Iron", 2, slot="head")
register_item("Iron Platebody", "Armor", "Iron", 2, slot="chest")
register_item("Iron Platelegs", "Armor", "Iron", 2, slot="legs")
register_item("Iron Kiteshield", "Armor", "Iron", 2, slot="shield")
register_item("Iron Square Shield", "Armor", "Iron", 2, slot="shield")
register_item("Iron Ring", "Armor", "Iron", 2, slot="ring")
register_item("Iron Necklace", "Armor", "Iron", 2, slot="neck")

# Steel tier
register_item("Steel Shortsword", "Weapon", "Steel", 3, slot="weapon")
register_item("Steel Longsword", "Weapon", "Steel", 3, slot="weapon")
register_item("Steel Mace", "Weapon", "Steel", 3, slot="weapon")
register_item("Steel Dagger", "Weapon", "Steel", 3, slot="weapon")
register_item("Steel Warmaul", "Weapon", "Steel", 3, slot="weapon")
register_item("Steel Bow", "Weapon", "Steel", 3, slot="weapon")
register_item("Steel Crossbow", "Weapon", "Steel", 3, slot="weapon")
register_item("Steel Magic Staff", "Weapon", "Steel", 3, slot="weapon")
register_item("Steel Magic Wand", "Weapon", "Steel", 3, slot="weapon")
register_item("Steel Helmet", "Armor", "Steel", 3, slot="head")
register_item("Steel Platebody", "Armor", "Steel", 3, slot="chest")
register_item("Steel Platelegs", "Armor", "Steel", 3, slot="legs")
register_item("Steel Kiteshield", "Armor", "Steel", 3, slot="shield")
register_item("Steel Square Shield", "Armor", "Steel", 3, slot="shield")
register_item("Steel Ring", "Armor", "Steel", 3, slot="ring")
register_item("Steel Necklace", "Armor", "Steel", 3, slot="neck")

# Blacksteel tier
register_item("Blacksteel Shortsword", "Weapon", "Blacksteel", 4, slot="weapon")
register_item("Blacksteel Longsword", "Weapon", "Blacksteel", 4, slot="weapon")
register_item("Blacksteel Mace", "Weapon", "Blacksteel", 4, slot="weapon")
register_item("Blacksteel Dagger", "Weapon", "Blacksteel", 4, slot="weapon")
register_item("Blacksteel Warmaul", "Weapon", "Blacksteel", 4, slot="weapon")
register_item("Blacksteel Bow", "Weapon", "Blacksteel", 4, slot="weapon")
register_item("Blacksteel Crossbow", "Weapon", "Blacksteel", 4, slot="weapon")
register_item("Blacksteel Magic Staff", "Weapon", "Blacksteel", 4, slot="weapon")
register_item("Blacksteel Magic Wand", "Weapon", "Blacksteel", 4, slot="weapon")
register_item("Blacksteel Helmet", "Armor", "Blacksteel", 4, slot="head")
register_item("Blacksteel Platebody", "Armor", "Blacksteel", 4, slot="chest")
register_item("Blacksteel Platelegs", "Armor", "Blacksteel", 4, slot="legs")
register_item("Blacksteel Kiteshield", "Armor", "Blacksteel", 4, slot="shield")
register_item("Blacksteel Square Shield", "Armor", "Blacksteel", 4, slot="shield")
register_item("Blacksteel Ring", "Armor", "Blacksteel", 4, slot="ring")
register_item("Blacksteel Necklace", "Armor", "Blacksteel", 4, slot="neck")

# Mithril tier
register_item("Mithril Shortsword", "Weapon", "Mithril", 5, slot="weapon")
register_item("Mithril Longsword", "Weapon", "Mithril", 5, slot="weapon")
register_item("Mithril Mace", "Weapon", "Mithril", 5, slot="weapon")
register_item("Mithril Dagger", "Weapon", "Mithril", 5, slot="weapon")
register_item("Mithril Warmaul", "Weapon", "Mithril", 5, slot="weapon")
register_item("Mithril Bow", "Weapon", "Mithril", 5, slot="weapon")
register_item("Mithril Crossbow", "Weapon", "Mithril", 5, slot="weapon")
register_item("Mithril Magic Staff", "Weapon", "Mithril", 5, slot="weapon")
register_item("Mithril Magic Wand", "Weapon", "Mithril", 5, slot="weapon")
register_item("Mithril Helmet", "Armor", "Mithril", 5, slot="head")
register_item("Mithril Platebody", "Armor", "Mithril", 5, slot="chest")
register_item("Mithril Platelegs", "Armor", "Mithril", 5, slot="legs")
register_item("Mithril Kiteshield", "Armor", "Mithril", 5, slot="shield")
register_item("Mithril Square Shield", "Armor", "Mithril", 5, slot="shield")
register_item("Mithril Ring", "Armor", "Mithril", 5, slot="ring")
register_item("Mithril Necklace", "Armor", "Mithril", 5, slot="neck")

# Adamantite tier
register_item("Adamantite Shortsword", "Weapon", "Adamantite", 6, slot="weapon")
register_item("Adamantite Longsword", "Weapon", "Adamantite", 6, slot="weapon")
register_item("Adamantite Mace", "Weapon", "Adamantite", 6, slot="weapon")
register_item("Adamantite Dagger", "Weapon", "Adamantite", 6, slot="weapon")
register_item("Adamantite Warmaul", "Weapon", "Adamantite", 6, slot="weapon")
register_item("Adamantite Bow", "Weapon", "Adamantite", 6, slot="weapon")
register_item("Adamantite Crossbow", "Weapon", "Adamantite", 6, slot="weapon")
register_item("Adamantite Magic Staff", "Weapon", "Adamantite", 6, slot="weapon")
register_item("Adamantite Magic Wand", "Weapon", "Adamantite", 6, slot="weapon")
register_item("Adamantite Helmet", "Armor", "Adamantite", 6, slot="head")
register_item("Adamantite Platebody", "Armor", "Adamantite", 6, slot="chest")
register_item("Adamantite Platelegs", "Armor", "Adamantite", 6, slot="legs")
register_item("Adamantite Kiteshield", "Armor", "Adamantite", 6, slot="shield")
register_item("Adamantite Square Shield", "Armor", "Adamantite", 6, slot="shield")
register_item("Adamantite Ring", "Armor", "Adamantite", 6, slot="ring")
register_item("Adamantite Necklace", "Armor", "Adamantite", 6, slot="neck")

# Starforged tier
register_item("Starforged Shortsword", "Weapon", "Starforged", 7, slot="weapon")
register_item("Starforged Longsword", "Weapon", "Starforged", 7, slot="weapon")
register_item("Starforged Mace", "Weapon", "Starforged", 7, slot="weapon")
register_item("Starforged Dagger", "Weapon", "Starforged", 7, slot="weapon")
register_item("Starforged Warmaul", "Weapon", "Starforged", 7, slot="weapon")
register_item("Starforged Bow", "Weapon", "Starforged", 7, slot="weapon")
register_item("Starforged Crossbow", "Weapon", "Starforged", 7, slot="weapon")
register_item("Starforged Magic Staff", "Weapon", "Starforged", 7, slot="weapon")
register_item("Starforged Magic Wand", "Weapon", "Starforged", 7, slot="weapon")
register_item("Starforged Helmet", "Armor", "Starforged", 7, slot="head")
register_item("Starforged Platebody", "Armor", "Starforged", 7, slot="chest")
register_item("Starforged Platelegs", "Armor", "Starforged", 7, slot="legs")
register_item("Starforged Kiteshield", "Armor", "Starforged", 7, slot="shield")
register_item("Starforged Square Shield", "Armor", "Starforged", 7, slot="shield")
register_item("Starforged Ring", "Armor", "Starforged", 7, slot="ring")
register_item("Starforged Necklace", "Armor", "Starforged", 7, slot="neck")

# Food (not equippable)
register_item("Mystery Meat Scraps", "Food", "nan", 1)
register_item("Cooked Wolf Meat", "Food", "nan", 1)
register_item("Fried Fish Fillet", "Food", "nan", 2)
register_item("Roast Chicken", "Food", "nan", 2)
register_item("Beef Steak", "Food", "nan", 3)
register_item("Glazed Boar Haunch", "Food", "nan", 4)
register_item("Grilled Venison", "Food", "nan", 5)
register_item("Dragon Pepper Soup", "Food", "nan", 5)

# Crafting materials (not equippable)
register_item("Bowstring", "Crafting", "nan", 1)
register_item("Arrow Shafts", "Crafting", "nan", 1)
register_item("Arrow Heads", "Crafting", "nan", 1)
register_item("Feathers", "Crafting", "nan", 1)
register_item("Iron Ingot", "Crafting", "nan", 2)
register_item("Steel Ingot", "Crafting", "nan", 3)
register_item("Blacksteel Ingot", "Crafting", "nan", 4)
register_item("Mithril Ingot", "Crafting", "nan", 5)
register_item("Starforged Ingot", "Crafting", "nan", 7)
register_item("Ripped Cloth", "Crafting", "nan", 2)
register_item("Enchanted Cloth", "Crafting", "nan", 4)
register_item("Dark Essence", "Crafting", "nan", 5)
register_item("Greater Dark Essence", "Crafting", "nan", 6)

# Misc / enchantment items
register_item("Escape Rope", "Enchantment/Misc", "nan", 3)

# Unique accessories – now equippable as armor with slots
register_item("Sniper's Ring", "Armor", "nan", 5, slot="ring")
register_item("Knight's Cape", "Armor", "nan", 5, slot="cape")
register_item("Sorcerer Ring", "Armor", "nan", 5, slot="ring")
register_item("Commander's Ring", "Armor", "nan", 5, slot="ring")
register_item("Acolyte Necklace", "Armor", "nan", 5, slot="neck")
register_item("Cracked Ring", "Armor", "nan", 5, slot="ring")
