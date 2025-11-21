"""Aetheria core loot helpers and registry data.

Data sources:
    * :mod:`loot.loot_tables` — tiered loot logic and gold tables.
    * :mod:`loot.goblin_loot`, :mod:`loot.bandit_loot`, :mod:`loot.skeleton_loot` —
      curated per-family loot tables kept for reference.

This wrapper exposes the raw constants and helper functions without any
Arcade/UI dependencies and adds a helper to roll loot directly from a monster
ID.
"""

from __future__ import annotations

from typing import Dict, Mapping, Optional

from loot import loot_tables
from loot.bandit_loot import bandit_loot_table
from loot.goblin_loot import goblin_loot_table
from loot.skeleton_loot import skeleton_loot_table

# Copy key constants/structures from the source module.
GOLD_TABLE = dict(loot_tables.GOLD_TABLE)
tier_weapons = {tier: list(items) for tier, items in loot_tables.tier_weapons.items()}
tier_armor = {tier: list(items) for tier, items in loot_tables.tier_armor.items()}
tier_accessories = {tier: list(items) for tier, items in loot_tables.tier_accessories.items()}
tier_general = {tier: list(items) for tier, items in loot_tables.tier_general.items()}
artifact_items = list(loot_tables.artifact_items)

# Optional curated tables by enemy family/name.
NAMED_LOOT_TABLES: Mapping[str, Mapping[str, dict]] = {
    "goblins": goblin_loot_table,
    "bandits": bandit_loot_table,
    "skeletons": skeleton_loot_table,
}


def roll_loot(monster_id: int) -> Dict[str, object]:
    """Roll tiered loot for the given monster ID using shared loot logic."""

    from aetheria_core.monsters import get_monster

    monster = get_monster(monster_id)
    if monster is None:
        raise KeyError(f"Unknown monster ID: {monster_id}")
    return loot_tables.roll_loot(monster)


def roll_artifact_loot():
    """Randomly return one of the registered artifact items (if available)."""

    return loot_tables.roll_artifact_loot()


def get_family_loot_table(family: str) -> Optional[Mapping[str, dict]]:
    """Return a named loot table (goblins/bandits/skeletons) if present."""

    return NAMED_LOOT_TABLES.get(family.lower().strip())


__all__ = [
    "artifact_items",
    "bandit_loot_table",
    "GOLD_TABLE",
    "NAMED_LOOT_TABLES",
    "goblin_loot_table",
    "skeleton_loot_table",
    "tier_accessories",
    "tier_armor",
    "tier_general",
    "tier_weapons",
    "get_family_loot_table",
    "roll_artifact_loot",
    "roll_loot",
]
