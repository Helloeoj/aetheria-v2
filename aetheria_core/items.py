"""
Item core for Aetheria.

Re-exports the real item registry from items/items.py so different
front-ends don't have to know your folder structure.
"""

from items.items import Item, ITEMS, register_item

__all__ = ["Item", "ITEMS", "register_item"]
