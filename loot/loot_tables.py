# ============================================================
# AETHERIA — LOOT TABLE SYSTEM (PHASE 3 REWRITE)
#
# Hybrid Tier-Based Loot System:
# - Gold always drops
# - 40% chance to roll an item
# - Tier-weighted loot selection (65% same tier, 20% lower, 15% tier 1 bias)
# - Weapons/armor: 1/50 (2%)
# - Accessories: 1/150 (~0.66%)
# - All other items: common
# - Artifacts/Starforged tiers are excluded unless the monster is tier 7+
# ============================================================

import random
from items import ITEMS  # master item registry


# ============================================================
# GOLD DROP VALUES PER TIER
# ============================================================

GOLD_TABLE = {
    1: (3, 10),
    2: (5, 18),
    3: (10, 28),
    4: (18, 40),
    5: (25, 60),
    6: (40, 95),
    7: (75, 150)
}


# ============================================================
# BUILD TIER POOLS FROM ITEMS.PY
# These will auto-populate based on item.tier & item type
# ============================================================

tier_weapons = {t: [] for t in range(1, 8)}
tier_armor = {t: [] for t in range(1, 8)}
tier_accessories = {t: [] for t in range(1, 8)}
tier_general = {t: [] for t in range(1, 8)}

artifact_items = []  # special sources only — never drop normally


for item in ITEMS.values():

    # ARTIFACTS — never in normal monster tables
    if getattr(item, "is_artifact", False):
        artifact_items.append(item)
        continue

    t = item.tier
    if t < 1 or t > 7:
        continue

    item_type = (item.item_type or "").lower()
    item_slot = (getattr(item, "slot", "") or "").lower()

    # Weapon classification
    if item_type == "weapon":
        tier_weapons[t].append(item)
        continue

    # Accessories live in the accessory table even if their item_type is Armor
    if item_type == "accessory" or item_slot in ("ring", "neck", "cape"):
        tier_accessories[t].append(item)
        continue

    # Armor classification
    if item_type == "armor":
        tier_armor[t].append(item)
        continue

    # General items (food, crafting, misc)
    tier_general[t].append(item)


# ============================================================
# WEIGHTED TIER SELECTION
# (65% same-tier, 20% lower-tier, 15% tier-1 bias)
# ============================================================

def choose_loot_tier(monster_tier):
    """
    Decide which tier the item comes from.
    Higher monster tiers can drop lower tier stuff
    to create junk loot and healthy economy.
    """

    roll = random.random()

    if monster_tier <= 1:
        return 1

    same = 0.65
    lower = 0.20

    # 65% — same tier
    if roll < same:
        return monster_tier

    # 20% — drop one tier lower (if possible)
    if roll < same + lower and monster_tier > 1:
        return monster_tier - 1

    # 15% — lowest tier always accessible
    return 1


# ============================================================
# LOOT CHANCE LOGIC
# ============================================================

def roll_basic_item(tier):
    """
    Choose a random GENERAL item from the chosen tier.
    If tier doesn't have general items, fallback to tier 1.
    """
    pool = tier_general.get(tier, [])
    if not pool:
        pool = tier_general[1]

    return random.choice(pool)


def roll_weapon_or_armor(tier):
    """
    50/50 chance weapon or armor.
    """
    weapon_pool = tier_weapons.get(tier, [])
    armor_pool = tier_armor.get(tier, [])

    pools = []
    if weapon_pool:
        pools.append(("weapon", weapon_pool))
    if armor_pool:
        pools.append(("armor", armor_pool))

    if not pools:
        return roll_basic_item(tier)

    _, pool = random.choice(pools)
    return random.choice(pool)


def roll_accessory(tier):
    """Select random accessory from tier."""
    pool = tier_accessories.get(tier, [])
    if not pool:
        return roll_basic_item(tier)

    return random.choice(pool)


def _determine_stack_size(item):
    """Return a stack size for general items; equipment always drops as 1."""

    item_type = (getattr(item, "item_type", "") or "").lower()
    if item_type in ("crafting", "food"):
        return random.randint(1, 3)

    return 1


# ============================================================
# MAIN FUNCTION — ROLL LOOT FOR ANY MONSTER
# ============================================================

def roll_loot(monster):
    """
    Returns a dictionary:
    {
        "gold": int,
        "item": optional Item or None,
        "quantity": int (1+ for stackable general items)
    }
    """
    tier = getattr(monster, "tier", 1) or 1

    # ------------------------------
    # Always drop gold
    # ------------------------------
    gmin, gmax = GOLD_TABLE.get(tier, GOLD_TABLE[max(GOLD_TABLE)])
    gold_amount = random.randint(gmin, gmax)

    # ------------------------------
    # 60% chance → gold only
    # ------------------------------
    if random.random() > 0.40:
        return {"gold": gold_amount, "item": None, "quantity": 0}

    # ------------------------------
    # 40% chance → roll item
    # ------------------------------
    chosen_tier = choose_loot_tier(tier)

    # Rare rolls
    weapon_roll = (random.randint(1, 50) == 1)
    accessory_roll = (random.randint(1, 150) == 1)

    # 2% weapon/armor roll
    if weapon_roll:
        return {"gold": gold_amount, "item": roll_weapon_or_armor(chosen_tier), "quantity": 1}

    # 0.66% accessory roll
    if accessory_roll:
        return {"gold": gold_amount, "item": roll_accessory(chosen_tier), "quantity": 1}

    # Common general item
    general_item = roll_basic_item(chosen_tier)
    return {
        "gold": gold_amount,
        "item": general_item,
        "quantity": _determine_stack_size(general_item),
    }


# ============================================================
# SPECIAL SOURCES — ANCIENT RUINS / ARTIFACT DUNGEONS
# ============================================================

def roll_artifact_loot():
    """
    Only called in special dungeons.
    Artifacts NEVER drop from normal monsters.
    """
    if not artifact_items:
        return None
    return random.choice(artifact_items)
