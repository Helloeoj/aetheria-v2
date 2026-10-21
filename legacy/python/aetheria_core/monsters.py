"""Aetheria core monster registry and helpers.

Data sources:
    * :mod:`monsters.monster` — core :class:`Monster` definition.
    * :mod:`monsters.goblins` — currently the authoritative monster family data.

This module keeps the raw monster templates and provides helpers for cloning
fresh instances without any Arcade/UI coupling.
"""

from __future__ import annotations

import copy
from typing import Dict, Optional

from monsters.goblins import MONSTER_FAMILY as GOBLIN_FAMILY
from monsters.monster import Monster

# Master database keyed by numeric ID.
MONSTER_DATABASE: Dict[int, Monster] = {}

# Load goblins into the master DB (use copies so we can annotate IDs safely).
for monster_id, monster in GOBLIN_FAMILY.items():
    template = copy.deepcopy(monster)
    template.monster_id = monster_id
    MONSTER_DATABASE[monster_id] = template

# Name lookup index for convenience.
MONSTERS_BY_NAME = {monster.name.lower(): mid for mid, monster in MONSTER_DATABASE.items()}


def get_monster(monster_id: int) -> Optional[Monster]:
    """Return the template Monster for this ID, or ``None`` if missing."""

    return MONSTER_DATABASE.get(monster_id)


def get_monster_by_name(name: str) -> Optional[Monster]:
    """Case-insensitive lookup from monster name -> template."""

    monster_id = MONSTERS_BY_NAME.get(name.lower().strip())
    if monster_id is None:
        return None
    return MONSTER_DATABASE.get(monster_id)


def create_monster_instance(monster_id: int, x: float = 0.0, y: float = 0.0) -> Monster:
    """Create a fresh :class:`Monster` instance for this ID at ``(x, y)``."""

    template = get_monster(monster_id)
    if template is None:
        raise KeyError(f"Unknown monster ID: {monster_id}")

    monster: Monster = copy.deepcopy(template)
    monster.monster_id = monster_id
    monster.is_alive = True
    monster.current_hp = monster.max_hp
    monster.move_to(x, y)
    return monster


__all__ = [
    "Monster",
    "MONSTER_DATABASE",
    "MONSTERS_BY_NAME",
    "create_monster_instance",
    "get_monster",
    "get_monster_by_name",
]
