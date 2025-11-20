"""
Aetheria Core — Monsters Registry (Arcade / Tick Engine)

This version is deliberately simple:
- It only wires in the Goblin family for now.
- It exposes:
    MONSTER_DATABASE
    get_monster_by_id
    get_monster_id_by_name
    create_monster_instance
which is exactly what arcade_client/main.py imports.
"""

from __future__ import annotations

import copy
from typing import Dict, Optional

from monsters.goblins import MONSTER_FAMILY as GOBLIN_FAMILY
from monsters.monster import Monster


# ============================================================
# MASTER DATABASE
# ============================================================

# All monsters keyed by numeric ID:
#   MONSTER_DATABASE[2]  -> Goblin Scout
#   MONSTER_DATABASE[15] -> Goblin Worker
#   etc.
MONSTER_DATABASE: Dict[int, Monster] = {}

# Load goblins into the master DB
MONSTER_DATABASE.update(GOBLIN_FAMILY)


# ============================================================
# HELPER FUNCTIONS
# ============================================================

def get_monster_by_id(monster_id: int) -> Optional[Monster]:
    """Return the template Monster for this ID, or None if missing."""
    return MONSTER_DATABASE.get(monster_id)


def get_monster_id_by_name(name: str) -> Optional[int]:
    """Case-insensitive lookup from monster name -> ID."""
    name = name.lower().strip()
    for mid, monster in MONSTER_DATABASE.items():
        if monster.name.lower() == name:
            return mid
    return None


def create_monster_instance(monster_id: int, x: float, y: float) -> Monster:
    """
    Create a fresh Monster instance for this ID at (x, y).

    - Uses a deepcopy so each spawn has its own HP/state.
    - Calls monster.reset() so HP/timers are fresh.
    - Sets the position to (x, y).
    """
    template = get_monster_by_id(monster_id)
    if template is None:
        raise KeyError(f"Unknown monster ID: {monster_id}")

    # Clone the template so multiple spawns don't share HP/state
    monster: Monster = copy.deepcopy(template)

    # Reset state & position
    if hasattr(monster, "reset"):
        monster.reset()
    if hasattr(monster, "set_position"):
        monster.set_position(x, y)
    else:
        monster.x = x
        monster.y = y

    # entity_id is assigned later by the caller (arcade_client)
    if hasattr(monster, "entity_id"):
        monster.entity_id = None

    return monster
