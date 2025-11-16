from dataclasses import dataclass
from typing import List, Dict


@dataclass
class Monster:
    name: str
    tier: int
    level: int
    health: int
    armor: int
    resistances: Dict[str, float]   # e.g. {'slash': 0.1, 'blunt': -0.2}
    damage_type: str                # 'slash', 'blunt', 'magic', 'ranged', etc.
    min_damage: int
    max_damage: int
    accuracy: float                 # 0.0–1.0
    crit_chance: float              # 0.0–1.0
    crit_multiplier: float
    status_effects: List[str]       # Example: ['poison', 'burn']


# The global dictionary where all monsters are stored
MONSTER_DATABASE: Dict[str, Monster] = {}


def register_monster(monster: Monster):
    """Add a monster to the global monster registry."""
    MONSTER_DATABASE[monster.name] = monster


def get_monster(name: str) -> Monster:
    """Retrieve a monster by name."""
    return MONSTER_DATABASE.get(name)


def all_monsters() -> List[Monster]:
    """Return a list of all registered monsters."""
    return list(MONSTER_DATABASE.values())
