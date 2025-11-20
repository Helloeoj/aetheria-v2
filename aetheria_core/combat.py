# aetheria_core/combat.py
# Wrapper module for compatibility with older CLI code.
# All real combat logic now lives in CombatEngine.

from aetheria_core.combat_engine import CombatEngine

# Create a shared engine instance (CLI will use this)
engine = CombatEngine()

__all__ = ["engine", "CombatEngine"]
