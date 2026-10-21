# ============================================================
# AETHERIA — MONSTER CLASS (PHASE 1.5 REWRITE, WITH CRITS)
# ------------------------------------------------------------
# Core monster data structure used by both CLI and Arcade.
#
# Features:
#   - World position (x, y) in tile coordinates
#   - Current + max HP
#   - Min / max damage
#   - Damage type: "slash", "stab", "blunt", "magic", "ranged"
#   - Accuracy (0.0–1.0)
#   - Per-type resistances (dict of damage_type -> float)
#   - Attack speed in ticks (OSRS tick = 0.6s)
#   - Attack range (tiles)
#   - Projectile speed (tiles per tick)
#   - Crit chance + crit multiplier
#   - Alive flag
#   - get_combat_stats() for CombatEngine / CombatActor
# ============================================================

from __future__ import annotations

from dataclasses import dataclass, field
from math import sqrt
from typing import Dict, Tuple

DamageType = str  # "slash", "stab", "blunt", "magic", "ranged"


@dataclass
class Monster:
    # Identity
    name: str
    tier: int
    level: int

    # Core combat stats
    max_hp: int
    min_damage: int
    max_damage: int
    damage_type: DamageType
    accuracy: float  # 0.0–1.0

    # Defence / resistances
    resistances: Dict[DamageType, float] = field(default_factory=dict)

    # Timing + range
    attack_speed: int = 5          # in ticks
    attack_range: int = 1          # in tiles
    projectile_speed: float = 0.0  # tiles per tick; 0 = melee / instant

    # Crits
    crit_chance: float = 0.05      # 5% default
    crit_multiplier: float = 1.5   # 1.5x default

    # World position (tile coords)
    x: float = 0.0
    y: float = 0.0

    # Runtime state
    current_hp: int = field(init=False)
    is_alive: bool = field(default=True, init=False)

    # Optional registry ID (set by your monsters database)
    monster_id: int | None = None

    def __post_init__(self) -> None:
        # Start at full health
        self.current_hp = self.max_hp

        # Normalize resistances to a plain dict
        self.resistances = dict(self.resistances or {})

    # -------------------------------------------------------
    # POSITION HELPERS
    # -------------------------------------------------------
    @property
    def position(self) -> Tuple[float, float]:
        return (self.x, self.y)

    def move_to(self, x: float, y: float) -> None:
        self.x = x
        self.y = y

    def distance_to(self, other: "Monster | object") -> float:
        """
        Euclidean distance in tile units.
        `other` may be another Monster or any object with .x/.y.
        """
        ox = getattr(other, "x", 0.0)
        oy = getattr(other, "y", 0.0)
        return sqrt((self.x - ox) ** 2 + (self.y - oy) ** 2)

    # -------------------------------------------------------
    # COMBAT STATS SNAPSHOT FOR ENGINE
    # -------------------------------------------------------
    def get_combat_stats(self) -> Dict[str, object]:
        """
        Returns a dict in the format expected by the CombatEngine /
        CombatActor. This lets the combat layer treat monsters and
        players in the same way.

        Keys here match what we wired earlier for the player:

          stats["health"]["current"]
          stats["health"]["max"]
          stats["min_damage"]
          stats["max_damage"]
          stats["style"]
          stats["accuracy"]
          stats["crit_chance"]
          stats["crit_multiplier"]
          stats["resistances"]
          stats["attack_speed"]
          stats["attack_range"]
          stats["projectile_speed"]
        """
        return {
            "health": {
                "current": self.current_hp,
                "max": self.max_hp,
            },
            "min_damage": self.min_damage,
            "max_damage": self.max_damage,
            # The engine treats this as the monster's attacking style
            "style": self.damage_type,
            "accuracy": self.accuracy,
            "crit_chance": self.crit_chance,
            "crit_multiplier": self.crit_multiplier,
            "resistances": self.resistances,
            "attack_speed": self.attack_speed,
            "attack_range": self.attack_range,
            "projectile_speed": self.projectile_speed,
        }

    # -------------------------------------------------------
    # RUNTIME HELPERS
    # -------------------------------------------------------
    def apply_damage(self, amount: int) -> None:
        """Subtract damage and update alive state."""
        if amount <= 0 or not self.is_alive:
            return
        self.current_hp = max(0, self.current_hp - int(amount))
        if self.current_hp == 0:
            self.is_alive = False

    # -------------------------------------------------------
    # PRETTY SUMMARY FOR DEBUG / CLI
    # -------------------------------------------------------
    def summary(self) -> Dict[str, object]:
        return {
            "name": self.name,
            "tier": self.tier,
            "level": self.level,
            "hp": f"{self.current_hp}/{self.max_hp}",
            "damage": f"{self.min_damage}-{self.max_damage}",
            "type": self.damage_type,
            "accuracy": self.accuracy,
            "resistances": self.resistances,
            "position": self.position,
            "alive": self.is_alive,
            "crit": {
                "chance": self.crit_chance,
                "multiplier": self.crit_multiplier,
            },
        }
