from dataclasses import dataclass, field
from typing import Dict, Optional
from items.items import Item  # note: imports from Aetheria/items/items.py


@dataclass
class Player:
    name: str

    # Core combat levels
    attack_level: int = 1
    strength_level: int = 1
    defence_level: int = 1
    health_level: int = 1  # players only

    # Health (computed from health_level)
    max_health: int = field(init=False)
    health: int = field(init=False)

    # Generic combat fields
    crit_chance: float = 0.05
    crit_multiplier: float = 1.5

    # Flat damage reduction
    armor: int = 0

    # Backpack: all items stack here (name -> count)
    backpack: Dict[str, int] = field(default_factory=dict)

    # Equipment slots: ONE item each, never stacks
    head: Optional[Item] = None
    chest: Optional[Item] = None
    legs: Optional[Item] = None
    cape: Optional[Item] = None
    ring1: Optional[Item] = None
    ring2: Optional[Item] = None
    neck: Optional[Item] = None
    weapon: Optional[Item] = None
    shield: Optional[Item] = None

    # Quiver: one ammo type + stack amount
    quiver_item: Optional[Item] = None
    quiver_amount: int = 0

    def __post_init__(self):
        # Players use: 100 base health + 10 per health level
        self.max_health = 100 + self.health_level * 10
        self.health = self.max_health

    @property
    def is_alive(self) -> bool:
        return self.health > 0

    @property
    def resistances(self) -> Dict[str, int]:
        # Base player resistances (before armor) are all zero.
        total = {
            "slash": 0,
            "blunt": 0,
            "stab": 0,
            "magic": 0,
            "ranged": 0,
        }
        # Later we’ll add armor bonuses here.
        return total

    @property
    def equipped_items(self) -> Dict[str, Optional[Item]]:
        return {
            "head": self.head,
            "chest": self.chest,
            "legs": self.legs,
            "cape": self.cape,
            "ring1": self.ring1,
            "ring2": self.ring2,
            "neck": self.neck,
            "weapon": self.weapon,
            "shield": self.shield,
            "quiver_item": self.quiver_item,
        }
