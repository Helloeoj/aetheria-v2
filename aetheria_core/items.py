"""Aetheria core item accessors and registry helpers.

Data source:
    * :mod:`items.items` — master item registry with `ITEMS` and `Item` definitions.

This module mirrors the registry into convenient name and ID lookups so callers
can stay agnostic of the source package layout. No UI / Arcade imports live
here; it is purely data access.
"""

from __future__ import annotations

from typing import Dict, Iterable, Optional

from items.items import Item, ITEMS as _ITEMS_BY_NAME, get_item_by_name, register_item

# Snapshot dictionaries keyed by name and ID for easy lookups.
ITEMS: Dict[str, Item] = dict(_ITEMS_BY_NAME)
ITEMS_BY_ID: Dict[int, Item] = {item.item_id: item for item in ITEMS.values()}


def list_items() -> Iterable[Item]:
    """Return an iterable of all registered items."""

    return ITEMS.values()


def get_item(identifier: int | str) -> Optional[Item]:
    """Lookup an item by numeric ID or by case-sensitive name."""

    if isinstance(identifier, int):
        return ITEMS_BY_ID.get(identifier)
    return ITEMS.get(str(identifier))


__all__ = [
    "Item",
    "ITEMS",
    "ITEMS_BY_ID",
    "get_item",
    "get_item_by_name",
    "list_items",
    "register_item",
]
