# ============================================================
# AETHERIA ITEM DATABASE  —  MASTER VERSION (FULL MIGRATION)
# Replaces: Aetheria/items/items.py
#
# Exports:
#   Item
#   ITEMS
#   register_item
#   get_item_by_name
#
# This file contains:
#   * Tier 1–7 Weapons, Armor, Accessories
#   * Crafting, Food, Utility items
#   * Artifact Weapons (15)
#   * Artifact Armor Sets (45)
#   * Weapon Speeds
#   * Attack/Defense bonuses
#   * Rarity fields
#   * Set bonuses (loaded externally)
# ============================================================

from __future__ import annotations


# ------------------------------------------------------------
# GLOBAL ITEM REGISTRY
# ------------------------------------------------------------

ITEMS = {}         # name → Item instance
ITEM_ID_COUNTER = 1


# ------------------------------------------------------------
# ITEM CLASS
# ------------------------------------------------------------

class Item:
    def __init__(
        self,
        name: str,
        item_type: str,
        material: str,
        tier: int,
        slot: str = None,
        attack_bonuses: dict | None = None,
        defence_bonuses: dict | None = None,
        accuracy_bonus: float = 0.0,
        speed: int | None = None,
        rarity: str = "common",
        set_name: str | None = None,
        special_effect: dict | None = None,
        **kwargs
    ):
        global ITEM_ID_COUNTER

        self.item_id = ITEM_ID_COUNTER
        ITEM_ID_COUNTER += 1

        self.name = name
        self.item_type = item_type
        self.material = material
        self.tier = tier
        self.slot = slot

        # Offense/Defense
        self.attack_bonuses = attack_bonuses or {}
        self.defence_bonuses = defence_bonuses or {}
        self.accuracy_bonus = accuracy_bonus

        # Weapon speed
        self.speed = speed

        # Rarity (normal, rare, artifact)
        self.rarity = rarity

        # Artifact set linkage
        self.set_name = set_name
        self.special_effect = special_effect

    def __repr__(self):
        return f"<Item {self.name} (ID {self.item_id})>"


# ------------------------------------------------------------
# WEAPON SPEED RULES (YOUR CHOSEN ROOT-LEVEL SPEED SYSTEM)
# ------------------------------------------------------------

DEFAULT_SPEEDS = {
    "Dagger": 3,
    "Shortsword": 4,
    "Longsword": 5,
    "Mace": 6,
    "Warmaul": 8,
    "Bow": 4,
    "Crossbow": 6,
    "Magic Staff": 5,
    "Magic Wand": 3,
}

def infer_speed_from_name(name: str) -> int | None:
    for key, spd in DEFAULT_SPEEDS.items():
        if key.lower() in name.lower():
            return spd
    return None


# ------------------------------------------------------------
# REGISTER ITEM FUNCTION
# ------------------------------------------------------------

def register_item(name: str, item_type: str, material: str, tier: int, **kwargs):
    # Auto-fill weapon speed if not provided
    if item_type == "Weapon" and "speed" not in kwargs:
        inferred = infer_speed_from_name(name)
        if inferred is not None:
            kwargs["speed"] = inferred

    item = Item(name=name, item_type=item_type, material=material, tier=tier, **kwargs)
    ITEMS[name] = item
    return item


# ------------------------------------------------------------
# LOOKUP
# ------------------------------------------------------------

def get_item_by_name(name: str) -> Item | None:
    return ITEMS.get(name)


# ============================================================
#                    TIER 1 ITEMS (BRONZE)
# ============================================================

# --------------------
# WEAPONS (Tier 1)
# --------------------

register_item(
    name="Bronze Dagger",
    item_type="Weapon",
    material="Bronze",
    tier=1,
    slot="weapon",
    attack_bonuses={"slash": 4, "stab": 10, "blunt": 0, "magic": 0, "ranged": 0},
)

register_item(
    name="Bronze Shortsword",
    item_type="Weapon",
    material="Bronze",
    tier=1,
    slot="weapon",
    attack_bonuses={"slash": 12, "stab": 6, "blunt": 0, "magic": 0, "ranged": 0},
)

register_item(
    name="Bronze Longsword",
    item_type="Weapon",
    material="Bronze",
    tier=1,
    slot="weapon",
    attack_bonuses={"slash": 16, "stab": 8, "blunt": 0, "magic": 0, "ranged": 0},
)

register_item(
    name="Bronze Mace",
    item_type="Weapon",
    material="Bronze",
    tier=1,
    slot="weapon",
    attack_bonuses={"slash": 4, "stab": 3, "blunt": 18, "magic": 0, "ranged": 0},
)

register_item(
    name="Bronze Warmaul",
    item_type="Weapon",
    material="Bronze",
    tier=1,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 30, "magic": 0, "ranged": 0},
)

register_item(
    name="Bronze Bow",
    item_type="Weapon",
    material="Bronze",
    tier=1,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 0, "magic": 0, "ranged": 12},
)

register_item(
    name="Bronze Crossbow",
    item_type="Weapon",
    material="Bronze",
    tier=1,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 0, "magic": 0, "ranged": 16},
)

register_item(
    name="Bronze Magic Staff",
    item_type="Weapon",
    material="Bronze",
    tier=1,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 0, "magic": 10, "ranged": 0},
)

register_item(
    name="Bronze Magic Wand",
    item_type="Weapon",
    material="Bronze",
    tier=1,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 0, "magic": 14, "ranged": 0},
)


# --------------------
# ARMOR (Tier 1)
# --------------------

register_item(
    name="Bronze Helmet",
    item_type="Armor",
    material="Bronze",
    tier=1,
    slot="head",
    defence_bonuses={"slash": 0.07, "stab": 0.05, "blunt": 0.06, "magic": -0.05, "ranged": 0.04},
)

register_item(
    name="Bronze Platebody",
    item_type="Armor",
    material="Bronze",
    tier=1,
    slot="chest",
    defence_bonuses={"slash": 0.10, "stab": 0.07, "blunt": 0.09, "magic": -0.08, "ranged": 0.06},
)

register_item(
    name="Bronze Platelegs",
    item_type="Armor",
    material="Bronze",
    tier=1,
    slot="legs",
    defence_bonuses={"slash": 0.08, "stab": 0.06, "blunt": 0.07, "magic": -0.06, "ranged": 0.05},
)

register_item(
    name="Bronze Kiteshield",
    item_type="Armor",
    material="Bronze",
    tier=1,
    slot="shield",
    defence_bonuses={"slash": 0.10, "stab": 0.08, "blunt": 0.12, "magic": -0.10, "ranged": 0.06},
)

register_item(
    name="Bronze Square Shield",
    item_type="Armor",
    material="Bronze",
    tier=1,
    slot="shield",
    defence_bonuses={"slash": 0.09, "stab": 0.07, "blunt": 0.11, "magic": -0.09, "ranged": 0.05},
)

register_item(
    name="Bronze Cape",
    item_type="Armor",
    material="Bronze",
    tier=1,
    slot="cape",
    defence_bonuses={"slash": 0.02, "stab": 0.02, "blunt": 0.02, "magic": 0.0, "ranged": 0.02},
)


# --------------------
# ACCESSORIES (Tier 1)
# --------------------

register_item(
    name="Bronze Ring",
    item_type="Armor",
    material="Bronze",
    tier=1,
    slot="ring",
    attack_bonuses={"slash": 4, "stab": 4, "blunt": 4, "magic": 4, "ranged": 4},
    accuracy_bonus=0.02,
)

register_item(
    name="Bronze Necklace",
    item_type="Armor",
    material="Bronze",
    tier=1,
    slot="neck",
    attack_bonuses={"slash": 4, "stab": 4, "blunt": 4, "magic": 4, "ranged": 4},
    accuracy_bonus=0.02,
)


# --------------------
# CRAFTING (Tier 1)
# --------------------

register_item("Arrow Shafts", item_type="Crafting", material="Wood", tier=1)
register_item("Bowstring", item_type="Crafting", material="Fiber", tier=1)
register_item("Feathers", item_type="Crafting", material="Organic", tier=1)


# --------------------
# FOOD (Tier 1)
# --------------------

register_item("Cooked Wolf Meat", item_type="Food", material="Meat", tier=1)
register_item("Mystery Meat Scraps", item_type="Food", material="Meat", tier=1)


# ============================================================
#                    TIER 2 ITEMS (IRON)
# ============================================================

# --------------------
# WEAPONS (Tier 2)
# --------------------

register_item(
    name="Iron Dagger",
    item_type="Weapon",
    material="Iron",
    tier=2,
    slot="weapon",
    attack_bonuses={"slash": 6, "stab": 14, "blunt": 0, "magic": 0, "ranged": 0},
)

register_item(
    name="Iron Shortsword",
    item_type="Weapon",
    material="Iron",
    tier=2,
    slot="weapon",
    attack_bonuses={"slash": 17, "stab": 9, "blunt": 0, "magic": 0, "ranged": 0},
)

register_item(
    name="Iron Longsword",
    item_type="Weapon",
    material="Iron",
    tier=2,
    slot="weapon",
    attack_bonuses={"slash": 22, "stab": 11, "blunt": 0, "magic": 0, "ranged": 0},
)

register_item(
    name="Iron Mace",
    item_type="Weapon",
    material="Iron",
    tier=2,
    slot="weapon",
    attack_bonuses={"slash": 6, "stab": 5, "blunt": 25, "magic": 0, "ranged": 0},
)

register_item(
    name="Iron Warmaul",
    item_type="Weapon",
    material="Iron",
    tier=2,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 44, "magic": 0, "ranged": 0},
)

register_item(
    name="Iron Bow",
    item_type="Weapon",
    material="Iron",
    tier=2,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 0, "magic": 0, "ranged": 16},
)

register_item(
    name="Iron Crossbow",
    item_type="Weapon",
    material="Iron",
    tier=2,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 0, "magic": 0, "ranged": 22},
)

register_item(
    name="Iron Magic Staff",
    item_type="Weapon",
    material="Iron",
    tier=2,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 0, "magic": 14, "ranged": 0},
)

register_item(
    name="Iron Magic Wand",
    item_type="Weapon",
    material="Iron",
    tier=2,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 0, "magic": 19, "ranged": 0},
)


# --------------------
# ARMOR (Tier 2)
# --------------------

register_item(
    name="Iron Helmet",
    item_type="Armor",
    material="Iron",
    tier=2,
    slot="head",
    defence_bonuses={"slash": 0.13, "stab": 0.11, "blunt": 0.12, "magic": -0.036, "ranged": 0.10},
)

register_item(
    name="Iron Platebody",
    item_type="Armor",
    material="Iron",
    tier=2,
    slot="chest",
    defence_bonuses={"slash": 0.17, "stab": 0.14, "blunt": 0.16, "magic": -0.068, "ranged": 0.13},
)

register_item(
    name="Iron Platelegs",
    item_type="Armor",
    material="Iron",
    tier=2,
    slot="legs",
    defence_bonuses={"slash": 0.145, "stab": 0.125, "blunt": 0.135, "magic": -0.051, "ranged": 0.115},
)

register_item(
    name="Iron Kiteshield",
    item_type="Armor",
    material="Iron",
    tier=2,
    slot="shield",
    defence_bonuses={"slash": 0.17, "stab": 0.15, "blunt": 0.19, "magic": -0.079, "ranged": 0.13},
)

register_item(
    name="Iron Square Shield",
    item_type="Armor",
    material="Iron",
    tier=2,
    slot="shield",
    defence_bonuses={"slash": 0.16, "stab": 0.14, "blunt": 0.18, "magic": -0.072, "ranged": 0.12},
)

register_item(
    name="Iron Cape",
    item_type="Armor",
    material="Iron",
    tier=2,
    slot="cape",
    defence_bonuses={"slash": 0.05, "stab": 0.05, "blunt": 0.05, "magic": 0.0, "ranged": 0.05},
)


# --------------------
# ACCESSORIES (Tier 2)
# --------------------

register_item(
    name="Iron Ring",
    item_type="Armor",
    material="Iron",
    tier=2,
    slot="ring",
    attack_bonuses={"slash": 8, "stab": 8, "blunt": 8, "magic": 8, "ranged": 8},
    accuracy_bonus=0.04,
)

register_item(
    name="Iron Necklace",
    item_type="Armor",
    material="Iron",
    tier=2,
    slot="neck",
    attack_bonuses={"slash": 8, "stab": 8, "blunt": 8, "magic": 8, "ranged": 8},
    accuracy_bonus=0.04,
)


# --------------------
# CRAFTING (Tier 2)
# --------------------

register_item("Iron Ingot", item_type="Crafting", material="Iron", tier=2)
register_item("Ripped Cloth", item_type="Crafting", material="Cloth", tier=2)


# --------------------
# FOOD (Tier 2)
# --------------------

register_item("Fried Fish Fillet", item_type="Food", material="Fish", tier=2)
register_item("Roast Chicken", item_type="Food", material="Meat", tier=2)


# ============================================================
#                    TIER 3 ITEMS (STEEL)
# ============================================================

# --------------------
# WEAPONS (Tier 3)
# --------------------

register_item(
    name="Steel Dagger",
    item_type="Weapon",
    material="Steel",
    tier=3,
    slot="weapon",
    attack_bonuses={"slash": 8, "stab": 19, "blunt": 0, "magic": 0, "ranged": 0},
)

register_item(
    name="Steel Shortsword",
    item_type="Weapon",
    material="Steel",
    tier=3,
    slot="weapon",
    attack_bonuses={"slash": 23, "stab": 12, "blunt": 0, "magic": 0, "ranged": 0},
)

register_item(
    name="Steel Longsword",
    item_type="Weapon",
    material="Steel",
    tier=3,
    slot="weapon",
    attack_bonuses={"slash": 30, "stab": 15, "blunt": 0, "magic": 0, "ranged": 0},
)

register_item(
    name="Steel Mace",
    item_type="Weapon",
    material="Steel",
    tier=3,
    socket="weapon",
    attack_bonuses={"slash": 8, "stab": 6, "blunt": 34, "magic": 0, "ranged": 0},
)

register_item(
    name="Steel Warmaul",
    item_type="Weapon",
    material="Steel",
    tier=3,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 67, "magic": 0, "ranged": 0},
)

register_item(
    name="Steel Bow",
    item_type="Weapon",
    material="Steel",
    tier=3,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 0, "magic": 0, "ranged": 23},
)

register_item(
    name="Steel Crossbow",
    item_type="Weapon",
    material="Steel",
    tier=3,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 0, "magic": 0, "ranged": 30},
)

register_item(
    name="Steel Magic Staff",
    item_type="Weapon",
    material="Steel",
    tier=3,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 0, "magic": 19, "ranged": 0},
)

register_item(
    name="Steel Magic Wand",
    item_type="Weapon",
    material="Steel",
    tier=3,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 0, "magic": 26, "ranged": 0},
)
# ============================================================
#                    TIER 4 ITEMS (BLACKSTEEL)
# ============================================================

# --------------------
# WEAPONS (Tier 4)
# --------------------

register_item(
    name="Blacksteel Dagger",
    item_type="Weapon",
    material="Blacksteel",
    tier=4,
    slot="weapon",
    attack_bonuses={"slash": 11, "stab": 24, "blunt": 0, "magic": 0, "ranged": 0},
)

register_item(
    name="Blacksteel Shortsword",
    item_type="Weapon",
    material="Blacksteel",
    tier=4,
    slot="weapon",
    attack_bonuses={"slash": 29, "stab": 15, "blunt": 0, "magic": 0, "ranged": 0},
)

register_item(
    name="Blacksteel Longsword",
    item_type="Weapon",
    material="Blacksteel",
    tier=4,
    slot="weapon",
    attack_bonuses={"slash": 38, "stab": 19, "blunt": 0, "magic": 0, "ranged": 0},
)

register_item(
    name="Blacksteel Mace",
    item_type="Weapon",
    material="Blacksteel",
    tier=4,
    slot="weapon",
    attack_bonuses={"slash": 11, "stab": 9, "blunt": 42, "magic": 0, "ranged": 0},
)

register_item(
    name="Blacksteel Warmaul",
    item_type="Weapon",
    material="Blacksteel",
    tier=4,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 83, "magic": 0, "ranged": 0},
)

register_item(
    name="Blacksteel Bow",
    item_type="Weapon",
    material="Blacksteel",
    tier=4,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 0, "magic": 0, "ranged": 30},
)

register_item(
    name="Blacksteel Crossbow",
    item_type="Weapon",
    material="Blacksteel",
    tier=4,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 0, "magic": 0, "ranged": 38},
)

register_item(
    name="Blacksteel Magic Staff",
    item_type="Weapon",
    material="Blacksteel",
    tier=4,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 0, "magic": 25, "ranged": 0},
)

register_item(
    name="Blacksteel Magic Wand",
    item_type="Weapon",
    material="Blacksteel",
    tier=4,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 0, "magic": 34, "ranged": 0},
)


# --------------------
# ARMOR (Tier 4)
# --------------------

register_item(
    name="Blacksteel Helmet",
    item_type="Armor",
    material="Blacksteel",
    tier=4,
    slot="head",
    defence_bonuses={"slash": 0.19, "stab": 0.17, "blunt": 0.18, "magic": -0.028, "ranged": 0.16},
)

register_item(
    name="Blacksteel Platebody",
    item_type="Armor",
    material="Blacksteel",
    tier=4,
    slot="chest",
    defence_bonuses={"slash": 0.24, "stab": 0.20, "blunt": 0.23, "magic": -0.050, "ranged": 0.19},
)

register_item(
    name="Blacksteel Platelegs",
    item_type="Armor",
    material="Blacksteel",
    tier=4,
    slot="legs",
    defence_bonuses={"slash": 0.205, "stab": 0.18, "blunt": 0.195, "magic": -0.036, "ranged": 0.17},
)

register_item(
    name="Blacksteel Kiteshield",
    item_type="Armor",
    material="Blacksteel",
    tier=4,
    slot="shield",
    defence_bonuses={"slash": 0.24, "stab": 0.21, "blunt": 0.27, "magic": -0.058, "ranged": 0.19},
)

register_item(
    name="Blacksteel Square Shield",
    item_type="Armor",
    material="Blacksteel",
    tier=4,
    slot="shield",
    defence_bonuses={"slash": 0.22, "stab": 0.20, "blunt": 0.25, "magic": -0.052, "ranged": 0.18},
)

register_item(
    name="Blacksteel Cape",
    item_type="Armor",
    material="Blacksteel",
    tier=4,
    slot="cape",
    defence_bonuses={"slash": 0.07, "stab": 0.07, "blunt": 0.07, "magic": 0.0, "ranged": 0.07},
)


# --------------------
# ACCESSORIES (Tier 4)
# --------------------

register_item(
    name="Blacksteel Ring",
    item_type="Armor",
    material="Blacksteel",
    tier=4,
    slot="ring",
    attack_bonuses={"slash": 12, "stab": 12, "blunt": 12, "magic": 12, "ranged": 12},
    accuracy_bonus=0.06,
)

register_item(
    name="Blacksteel Necklace",
    item_type="Armor",
    material="Blacksteel",
    tier=4,
    slot="neck",
    attack_bonuses={"slash": 12, "stab": 12, "blunt": 12, "magic": 12, "ranged": 12},
    accuracy_bonus=0.06,
)


# --------------------
# CRAFTING (Tier 4)
# --------------------

register_item("Blacksteel Ingot", item_type="Crafting", material="Blacksteel", tier=4)
register_item("Enchanted Cloth", item_type="Crafting", material="Cloth", tier=4)


# --------------------
# FOOD (Tier 4)
# --------------------

register_item("Glazed Boar Haunch", item_type="Food", material="Meat", tier=4)


# ============================================================
#                    TIER 5 ITEMS (MITHRIL)
# ============================================================

# --------------------
# WEAPONS (Tier 5)
# --------------------

register_item(
    name="Mithril Dagger",
    item_type="Weapon",
    material="Mithril",
    tier=5,
    slot="weapon",
    attack_bonuses={"slash": 15, "stab": 30, "blunt": 0, "magic": 0, "ranged": 0},
)

register_item(
    name="Mithril Shortsword",
    item_type="Weapon",
    material="Mithril",
    tier=5,
    slot="weapon",
    attack_bonuses={"slash": 36, "stab": 18, "blunt": 0, "magic": 0, "ranged": 0},
)

register_item(
    name="Mithril Longsword",
    item_type="Weapon",
    material="Mithril",
    tier=5,
    slot="weapon",
    attack_bonuses={"slash": 48, "stab": 24, "blunt": 0, "magic": 0, "ranged": 0},
)

register_item(
    name="Mithril Mace",
    item_type="Weapon",
    material="Mithril",
    tier=5,
    slot="weapon",
    attack_bonuses={"slash": 14, "stab": 10, "blunt": 54, "magic": 0, "ranged": 0},
)

register_item(
    name="Mithril Warmaul",
    item_type="Weapon",
    material="Mithril",
    tier=5,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 110, "magic": 0, "ranged": 0},
)

register_item(
    name="Mithril Bow",
    item_type="Weapon",
    material="Mithril",
    tier=5,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 0, "magic": 0, "ranged": 38},
)

register_item(
    name="Mithril Crossbow",
    item_type="Weapon",
    material="Mithril",
    tier=5,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 0, "magic": 0, "ranged": 48},
)

register_item(
    name="Mithril Magic Staff",
    item_type="Weapon",
    material="Mithril",
    tier=5,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 0, "magic": 34, "ranged": 0},
)

register_item(
    name="Mithril Magic Wand",
    item_type="Weapon",
    material="Mithril",
    tier=5,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 0, "magic": 44, "ranged": 0},
)


# --------------------
# ARMOR (Tier 5)
# --------------------

register_item(
    name="Mithril Helmet",
    item_type="Armor",
    material="Mithril",
    tier=5,
    slot="head",
    defence_bonuses={"slash": 0.25, "stab": 0.22, "blunt": 0.24, "magic": -0.021, "ranged": 0.21},
)

register_item(
    name="Mithril Platebody",
    item_type="Armor",
    material="Mithril",
    tier=5,
    slot="chest",
    defence_bonuses={"slash": 0.31, "stab": 0.27, "blunt": 0.29, "magic": -0.042, "ranged": 0.26},
)

register_item(
    name="Mithril Platelegs",
    item_type="Armor",
    material="Mithril",
    tier=5,
    slot="legs",
    defence_bonuses={"slash": 0.265, "stab": 0.235, "blunt": 0.255, "magic": -0.028, "ranged": 0.24},
)

register_item(
    name="Mithril Kiteshield",
    item_type="Armor",
    material="Mithril",
    tier=5,
    slot="shield",
    defence_bonuses={"slash": 0.32, "stab": 0.29, "blunt": 0.36, "magic": -0.048, "ranged": 0.27},
)

register_item(
    name="Mithril Square Shield",
    item_type="Armor",
    material="Mithril",
    tier=5,
    slot="shield",
    defence_bonuses={"slash": 0.30, "stab": 0.27, "blunt": 0.34, "magic": -0.042, "ranged": 0.26},
)

register_item(
    name="Mithril Cape",
    item_type="Armor",
    material="Mithril",
    tier=5,
    slot="cape",
    defence_bonuses={"slash": 0.10, "stab": 0.10, "blunt": 0.10, "magic": 0.0, "ranged": 0.10},
)


# --------------------
# ACCESSORIES (Tier 5)
# --------------------

register_item(
    name="Mithril Ring",
    item_type="Armor",
    material="Mithril",
    tier=5,
    slot="ring",
    attack_bonuses={"slash": 16, "stab": 16, "blunt": 16, "magic": 16, "ranged": 16},
    accuracy_bonus=0.08,
)

register_item(
    name="Mithril Necklace",
    item_type="Armor",
    material="Mithril",
    tier=5,
    slot="neck",
    attack_bonuses={"slash": 16, "stab": 16, "blunt": 16, "magic": 16, "ranged": 16},
    accuracy_bonus=0.08,
)


# --------------------
# CRAFTING (Tier 5)
# --------------------

register_item("Mithril Ingot", item_type="Crafting", material="Mithril", tier=5)
register_item("Dark Essence", item_type="Crafting", material="Essence", tier=5)


# --------------------
# FOOD (Tier 5)
# --------------------

register_item("Dragon Pepper Soup", item_type="Food", material="Soup", tier=5)
register_item("Grilled Venison", item_type="Food", material="Meat", tier=5)


# ============================================================
#                    TIER 6 ITEMS (ADAMANTITE)
# ============================================================

# --------------------
# WEAPONS (Tier 6)
# --------------------

register_item(
    name="Adamantite Dagger",
    item_type="Weapon",
    material="Adamantite",
    tier=6,
    slot="weapon",
    attack_bonuses={"slash": 18, "stab": 36, "blunt": 0, "magic": 0, "ranged": 0},
)

register_item(
    name="Adamantite Shortsword",
    item_type="Weapon",
    material="Adamantite",
    tier=6,
    slot="weapon",
    attack_bonuses={"slash": 42, "stab": 21, "blunt": 0, "magic": 0, "ranged": 0},
)

register_item(
    name="Adamantite Longsword",
    item_type="Weapon",
    material="Adamantite",
    tier=6,
    slot="weapon",
    attack_bonuses={"slash": 56, "stab": 28, "blunt": 0, "magic": 0, "ranged": 0},
)

register_item(
    name="Adamantite Mace",
    item_type="Weapon",
    material="Adamantite",
    tier=6,
    slot="weapon",
    attack_bonuses={"slash": 17, "stab": 13, "blunt": 64, "magic": 0, "ranged": 0},
)

register_item(
    name="Adamantite Warmaul",
    item_type="Weapon",
    material="Adamantite",
    tier=6,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 130, "magic": 0, "ranged": 0},
)

register_item(
    name="Adamantite Bow",
    item_type="Weapon",
    material="Adamantite",
    tier=6,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 0, "magic": 0, "ranged": 46},
)

register_item(
    name="Adamantite Crossbow",
    item_type="Weapon",
    material="Adamantite",
    tier=6,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 0, "magic": 0, "ranged": 56},
)

register_item(
    name="Adamantite Magic Staff",
    item_type="Weapon",
    material="Adamantite",
    tier=6,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 0, "magic": 44, "ranged": 0},
)

register_item(
    name="Adamantite Magic Wand",
    item_type="Weapon",
    material="Adamantite",
    tier=6,
    slot="weapon",
    attack_bonuses={"slash": 0, "stab": 0, "blunt": 0, "magic": 58, "ranged": 0},
)


# --------------------
# ARMOR (Tier 6)
# --------------------

register_item(
    name="Adamantite Helmet",
    item_type="Armor",
    material="Adamantite",
    tier=6,
    slot="head",
    defence_bonuses={"slash": 0.33, "stab": 0.30, "blunt": 0.32, "magic": -0.014, "ranged": 0.29},
)

register_item(
    name="Adamantite Platebody",
    item_type="Armor",
    material="Adamantite",
    tier=6,
    slot="chest",
    defence_bonuses={"slash": 0.40, "stab": 0.35, "blunt": 0.38, "magic": -0.031, "ranged": 0.34},
)

register_item(
    name="Adamantite Platelegs",
    item_type="Armor",
    material="Adamantite",
    tier=6,
    slot="legs",
    defence_bonuses={"slash": 0.355, "stab": 0.32, "blunt": 0.345, "magic": -0.021, "ranged": 0.31},
)

register_item(
    name="Adamantite Kiteshield",
    item_type="Armor",
    material="Adamantite",
    tier=6,
    slot="shield",
    defence_bonuses={"slash": 0.41, "stab": 0.37, "blunt": 0.45, "magic": -0.036, "ranged": 0.35},
)

register_item(
    name="Adamantite Square Shield",
    item_type="Armor",
    material="Adamantite",
    tier=6,
    slot="shield",
    defence_bonuses={"slash": 0.38, "stab": 0.35, "blunt": 0.43, "magic": -0.031, "ranged": 0.33},
)

register_item(
    name="Adamantite Cape",
    item_type="Armor",
    material="Adamantite",
    tier=6,
    slot="cape",
    defence_bonuses={"slash": 0.14, "stab": 0.14, "blunt": 0.14, "magic": 0.0, "ranged": 0.14},
)


# --------------------
# ACCESSORIES (Tier 6)
# --------------------

register_item(
    name="Adamantite Ring",
    item_type="Armor",
    material="Adamantite",
    tier=6,
    slot="ring",
    attack_bonuses={"slash": 20, "stab": 20, "blunt": 20, "magic": 20, "ranged": 20},
    accuracy_bonus=0.10,
)

register_item(
    name="Adamantite Necklace",
    item_type="Armor",
    material="Adamantite",
    tier=6,
    slot="neck",
    attack_bonuses={"slash": 22, "stab": 22, "blunt": 22, "magic": 22, "ranged": 22},
    accuracy_bonus=0.12,
)

register_item(
    name="Adamantite Cape",
    item_type="Armor",
    material="Adamantite",
    tier=6,
    slot="cape",
    defence_bonuses={"slash": 0.14, "stab": 0.14, "blunt": 0.14, "magic": 0.00, "ranged": 0.14},
)


# ============================================================
#                ARTIFACT WEAPONS (UNIQUE)
# ============================================================

# -------------------------------
# MAGIC ARTIFACTS (5)
# -------------------------------

register_item(
    name="Scepter of Umbral Stars",
    item_type="Weapon",
    material="Artifact",
    tier=10,
    slot="weapon",
    rarity="artifact",
    attack_bonuses={"magic": 78},
    accuracy_bonus=0.25,
    projectile_speed=2.8,
)


register_item(
    name="Tome of Broken Realms",
    item_type="Weapon",
    material="Artifact",
    tier=10,
    slot="weapon",
    rarity="artifact",
    attack_bonuses={"magic": 70},
    speed=6,
    special_effect={"dual_cast": True}
)

register_item(
    name="Crescent Ember Wand",
    item_type="Weapon",
    material="Artifact",
    tier=10,
    slot="weapon",
    rarity="artifact",
    attack_bonuses={"magic": 88},
    speed=3,
    special_effect={"bonus_burn_below_half": True}
)

register_item(
    name="Crystalline Soulrod",
    item_type="Weapon",
    material="Artifact",
    tier=10,
    slot="weapon",
    rarity="artifact",
    attack_bonuses={"magic": 76},
    speed=4,
    special_effect={"micro_lifesteal_on_cast": True}
)

register_item(
    name="Oculus of the Arcane Eye",
    item_type="Weapon",
    material="Artifact",
    tier=10,
    slot="weapon",
    rarity="artifact",
    attack_bonuses={"magic": 62},
    speed=5,
    special_effect={"detect_invisible": True}
)


# -------------------------------
# MELEE ARTIFACTS (5)
# -------------------------------

register_item(
    name="Ironhowl Fangblade",
    item_type="Weapon",
    material="Artifact",
    tier=10,
    slot="weapon",
    rarity="artifact",
    attack_bonuses={"slash": 84, "stab": 20},
    speed=5,
    special_effect={"armor_shred_on_crit": True}
)

register_item(
    name="Ashrender Maul",
    item_type="Weapon",
    material="Artifact",
    tier=10,
    slot="weapon",
    rarity="artifact",
    attack_bonuses={"blunt": 160},
    speed=8,
    special_effect={"slam_stun": True}
)

register_item(
    name="Dagger of the Nine Veins",
    item_type="Weapon",
    material="Artifact",
    tier=10,
    slot="weapon",
    rarity="artifact",
    attack_bonuses={"stab": 70, "slash": 28},
    speed=3,
    special_effect={"bleed_stacks": 9}
)

register_item(
    name="Oathbrand",
    item_type="Weapon",
    material="Artifact",
    tier=10,
    slot="weapon",
    rarity="artifact",
    attack_bonuses={"slash": 92, "stab": 18},
    speed=5,
    special_effect={"bonus_vs_undead": 0.25}
)

register_item(
    name="Spitehook Chains",
    item_type="Weapon",
    material="Artifact",
    tier=10,
    slot="weapon",
    rarity="artifact",
    attack_bonuses={"blunt": 68, "slash": 24},
    speed=6,
    special_effect={"pull_on_heavy": True}
)


# -------------------------------
# RANGED ARTIFACTS (5)
# -------------------------------

register_item(
    name="Vermillion Talon",
    item_type="Weapon",
    material="Artifact",
    tier=10,
    slot="weapon",
    rarity="artifact",
    attack_bonuses={"ranged": 72},
    speed=4,
    special_effect={"every_10th_arrow_crit": True}
)

register_item(
    name="Whispersting",
    item_type="Weapon",
    material="Artifact",
    tier=10,
    slot="weapon",
    rarity="artifact",
    attack_bonuses={"ranged": 82},
    speed=5,
    special_effect={"stealth_bonus_damage": 0.25}
)

register_item(
    name="Starfeather Launcher",
    item_type="Weapon",
    material="Artifact",
    tier=10,
    slot="weapon",
    rarity="artifact",
    attack_bonuses={"ranged": 64},
    speed=3,
    special_effect={"stacking_slow": True}
)

register_item(
    name="Echoshot Hornbow",
    item_type="Weapon",
    material="Artifact",
    tier=10,
    slot="weapon",
    rarity="artifact",
    attack_bonuses={"ranged": 90},
    speed=5,
    special_effect={"ricochet": True}
)

register_item(
    name="Blackglass Shardgun",
    item_type="Weapon",
    material="Artifact",
    tier=10,
    slot="weapon",
    rarity="artifact",
    attack_bonuses={"ranged": 100},
    speed=6,
    special_effect={"blind_chance": 0.05}
)



# ============================================================
#              ARTIFACT ARMOR SETS (45 PIECES)
# ============================================================
# Each set includes HELMET, CHEST, LEGS.
# Bonus effects are handled in set_bonuses.py.
# These pieces simply specify set_name + stats.


def make_artifact_armor_piece(name, set_name, slot, slash, stab, blunt, magic, ranged):
    return register_item(
        name=name,
        item_type="Armor",
        material="Artifact",
        tier=10,
        slot=slot,
        rarity="artifact",
        set_name=set_name,
        defence_bonuses={
            "slash": slash,
            "stab": stab,
            "blunt": blunt,
            "magic": magic,
            "ranged": ranged
        }
    )

# ============= MAGIC SETS (5 sets × 3 pieces = 15 items) =============

MAGIC_SETS = {
    "Starlight Shroud": (0.42, 0.36, 0.38, 0.18, 0.33),
    "Ashweaver Raiment": (0.40, 0.34, 0.36, 0.22, 0.30),
    "Runeshell Mantle":  (0.46, 0.39, 0.41, 0.27, 0.36),
    "Frostveil Regalia": (0.44, 0.37, 0.39, 0.20, 0.34),
    "Whispersoul Robes": (0.39, 0.33, 0.35, 0.29, 0.31),
}

for set_name, (sl, st, bl, mg, rg) in MAGIC_SETS.items():
    make_artifact_armor_piece(f"{set_name} Hood",   set_name, "head",  sl, st, bl, mg, rg)
    make_artifact_armor_piece(f"{set_name} Robe",   set_name, "chest", sl, st, bl, mg, rg)
    make_artifact_armor_piece(f"{set_name} Wraps",  set_name, "legs",  sl, st, bl, mg, rg)


# ============= MELEE SETS (5 sets × 3 pieces = 15 items) =============

MELEE_SETS = {
    "Titanbound Plate": (0.50, 0.44, 0.48, 0.12, 0.42),
    "Skullrender Armor": (0.52, 0.45, 0.49, 0.10, 0.40),
    "Drakehide Wrathset": (0.55, 0.47, 0.51, 0.14, 0.38),
    "Blackiron Enclave": (0.58, 0.50, 0.53, 0.09, 0.36),
    "Wardensteel Vesture": (0.54, 0.46, 0.50, 0.11, 0.39),
}

for set_name, (sl, st, bl, mg, rg) in MELEE_SETS.items():
    make_artifact_armor_piece(f"{set_name} Helm",   set_name, "head",  sl, st, bl, mg, rg)
    make_artifact_armor_piece(f"{set_name} Cuirass",set_name, "chest", sl, st, bl, mg, rg)
    make_artifact_armor_piece(f"{set_name} Greaves",set_name, "legs",  sl, st, bl, mg, rg)


# ============= RANGED SETS (5 sets × 3 pieces = 15 items) =============

RANGED_SETS = {
    "Galehunter’s Garb": (0.38, 0.34, 0.36, 0.16, 0.44),
    "Hollowbark Suit":   (0.41, 0.36, 0.37, 0.18, 0.46),
    "Emberstring Wraps": (0.39, 0.35, 0.36, 0.17, 0.49),
    "Snareweave Cuirass":(0.43, 0.38, 0.40, 0.14, 0.45),
    "Mirrorshade Mail":  (0.40, 0.34, 0.35, 0.15, 0.48),
}

for set_name, (sl, st, bl, mg, rg) in RANGED_SETS.items():
    make_artifact_armor_piece(f"{set_name} Mask",   set_name, "head",  sl, st, bl, mg, rg)
    make_artifact_armor_piece(f"{set_name} Vest",   set_name, "chest", sl, st, bl, mg, rg)
    make_artifact_armor_piece(f"{set_name} Striders",set_name, "legs", sl, st, bl, mg, rg)
