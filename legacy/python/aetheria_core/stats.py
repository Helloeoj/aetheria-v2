"""Pure stat helpers shared by the :mod:`aetheria_core` package.

These helpers intentionally avoid any rendering or input handling. They focus
on translating equipped gear into combat-ready values and validating attack
styles for the current weapon.
"""

from __future__ import annotations

from typing import Dict, Iterable, List, Optional

from aetheria_core.items import Item

VALID_MELEE_STYLES = ["stab", "slash", "blunt"]
VALID_MAGIC_STYLES = ["magic"]
VALID_RANGED_STYLES = ["ranged"]

PROJECTILE_SPEEDS = {
    "bow": 3.0,
    "crossbow": 2.2,
    "wand": 2.5,
    "staff": 2.0,
    "spell": 2.4,
    "thrown": 2.8,
}

ATTACK_RANGES = {
    "melee": 2.0,
    "ranged": 18.0,
    "crossbow": 22.0,
    "magic": 20.0,
}


# ---------------------------------------------------------------------------
# Attack style helpers
# ---------------------------------------------------------------------------

def valid_styles_for_weapon(weapon: Optional[Item]) -> List[str]:
    """Return a list of viable attack styles for ``weapon``.

    The function inspects the ``attack_bonuses`` dict on the :class:`Item` and
    returns every style that has a positive value. Unarmed players fall back to
    ``["blunt"]`` to keep combat flowing.
    """
    if weapon is None:
        return ["blunt"]

    bonuses = getattr(weapon, "attack_bonuses", {}) or {}
    found_styles: List[str] = []
    for style in VALID_MELEE_STYLES + VALID_MAGIC_STYLES + VALID_RANGED_STYLES:
        if bonuses.get(style, 0) > 0:
            found_styles.append(style)

    return found_styles or ["blunt"]


# ---------------------------------------------------------------------------
# Weapon speed, range, projectile helpers
# ---------------------------------------------------------------------------

def weapon_speed_in_ticks(weapon: Optional[Item]) -> int:
    """Return the weapon swing speed in ticks, defaulting to 4."""
    if weapon is None or not isinstance(weapon, Item):
        return 4
    return int(getattr(weapon, "speed", 4) or 4)


def get_attack_range(style: str, weapon: Optional[Item]) -> float:
    """Return max range based on attack style and weapon details."""
    if style in VALID_MELEE_STYLES:
        return ATTACK_RANGES["melee"]

    if style == "magic":
        return ATTACK_RANGES["magic"]

    if style == "ranged":
        name = (weapon.name if weapon else "").lower()
        if "crossbow" in name:
            return ATTACK_RANGES["crossbow"]
        return ATTACK_RANGES["ranged"]

    return ATTACK_RANGES["melee"]


def get_projectile_speed(weapon: Optional[Item]) -> float:
    """Return projectile travel speed using a best-effort weapon heuristic."""
    if weapon is None:
        return 2.0

    name = weapon.name.lower()
    for key, speed in PROJECTILE_SPEEDS.items():
        if key in name:
            return speed

    return 2.0


# ---------------------------------------------------------------------------
# Gear aggregation helpers
# ---------------------------------------------------------------------------

def aggregate_attack_bonuses(items: Iterable[Item]) -> Dict[str, int]:
    total = {"slash": 0, "stab": 0, "blunt": 0, "magic": 0, "ranged": 0}
    for item in items:
        bonuses = getattr(item, "attack_bonuses", {}) or {}
        for key in total:
            total[key] += int(bonuses.get(key, 0))
    return total


def aggregate_defence_bonuses(items: Iterable[Item]) -> Dict[str, float]:
    total = {"slash": 0.0, "stab": 0.0, "blunt": 0.0, "magic": 0.0, "ranged": 0.0}
    for item in items:
        bonuses = getattr(item, "defence_bonuses", {}) or {}
        for key in total:
            total[key] += float(bonuses.get(key, 0.0))

    for key in total:
        if total[key] < -0.50:
            total[key] = -0.50
        if total[key] > 0.80:
            total[key] = 0.80
    return total


def total_accuracy_bonus(items: Iterable[Item]) -> float:
    bonus = 0.0
    for item in items:
        bonus += float(getattr(item, "accuracy_bonus", 0.0) or 0.0)
    return bonus
