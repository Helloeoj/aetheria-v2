"""
Core game logic for Aetheria: players, items, monsters, combat, inventory.

This package only wraps your existing modules.
It contains no input() / print() and no UI code.

Both your CMD test runner and your Arcade client can import from here.
"""

from . import player
from . import items
from . import monsters
from . import combat
from . import inventory
from . import world

__all__ = ["player", "items", "monsters", "combat", "inventory", "world"]
