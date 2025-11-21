"""
Shared combat helpers for deterministic hit/miss, damage, and status effects.

These utilities are intentionally UI-agnostic so they can be reused by
headless simulations, CLI tools, and the Arcade client alike. CombatEngine
imports from here to keep all hit calculation logic in a single place.
"""
from dataclasses import dataclass, field
import random
from typing import Any, Dict, List, Optional


@dataclass
class HitOutcome:
    """Result of a single attack roll."""

    damage: int
    crit: bool
    hit: bool
    status_effects: List[str] = field(default_factory=list)


def _get_stat(source: Any, name: str, default: Any = None) -> Any:
    if isinstance(source, dict):
        return source.get(name, default)
    return getattr(source, name, default)


def _set_stat(target: Any, name: str, value: Any) -> None:
    if isinstance(target, dict):
        target[name] = value
    elif hasattr(target, name):
        setattr(target, name, value)


def calculate_hit_outcome(
    attacker: Any,
    target: Any,
    *,
    forced_damage: Optional[int] = None,
    forced_accuracy: Optional[float] = None,
    damage_type: Optional[str] = None,
    rng: random.Random = random,
) -> HitOutcome:
    """
    Determine whether an attack hits and how much damage it deals.

    Accepts plain data objects (dicts or objects with attributes) so the logic
    can be reused across UI layers.
    """

    accuracy = forced_accuracy if forced_accuracy is not None else _get_stat(attacker, "accuracy", 0.5)
    attack_style = damage_type or _get_stat(attacker, "attack_style", "slash")

    resistances: Dict[str, float] = _get_stat(target, "resistances", {}) or {}
    effective_accuracy = max(0.05, accuracy - float(resistances.get(attack_style, 0)))

    hit_roll = rng.random()
    if hit_roll > effective_accuracy:
        return HitOutcome(damage=0, crit=False, hit=False, status_effects=[])

    # Damage roll
    if forced_damage is not None:
        damage = forced_damage
    else:
        min_damage = int(_get_stat(attacker, "min_damage", 0))
        max_damage = int(_get_stat(attacker, "max_damage", max(min_damage, 1)))
        damage = rng.randint(min_damage, max(min_damage, max_damage))

    crit_chance = float(_get_stat(attacker, "crit_chance", 0.0) or 0.0)
    crit_multiplier = float(_get_stat(attacker, "crit_multiplier", 1.0) or 1.0)
    crit = rng.random() < crit_chance
    if crit:
        damage = int(damage * crit_multiplier)

    status_effects = list(_get_stat(attacker, "status_effects", []) or [])

    return HitOutcome(damage=int(damage), crit=crit, hit=True, status_effects=status_effects)


def apply_hit_to_target(target: Any, outcome: HitOutcome) -> Dict[str, Any]:
    """
    Apply a :class:`HitOutcome` to the target and return resulting state info.

    Supports dict-based targets or simple objects with ``hp``/``current_hp``
    attributes. Returns a summary useful for event generation.
    """

    hp_attr = "hp" if hasattr(target, "hp") or (isinstance(target, dict) and "hp" in target) else "current_hp"
    current_hp = int(_get_stat(target, hp_attr, _get_stat(target, "max_hp", 0)))
    new_hp = current_hp

    if outcome.hit:
        new_hp = max(0, current_hp - int(outcome.damage))
        _set_stat(target, hp_attr, new_hp)

    return {
        "hp_before": current_hp,
        "hp_after": new_hp,
        "status_effects": outcome.status_effects,
    }


__all__ = ["HitOutcome", "calculate_hit_outcome", "apply_hit_to_target"]
