"""
Core game logic for Aetheria: players, items, monsters, combat.

This package only wraps your existing modules:
- No input() / print()
- No windowing / UI

Both your CMD test runner and Arcade client can import from here.
"""

from . import player, items, monsters, combat

__all__ = ["player", "items", "monsters", "combat"]
