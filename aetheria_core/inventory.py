"""Expose inventory helpers via the core package.

This file keeps the shared equip/backpack helpers reachable as
``aetheria_core.inventory`` for callers like the Arcade client. The actual
logic lives in ``player.inventory`` to keep the code centralized.
"""

from player.inventory import (
    add_to_backpack,
    remove_from_backpack,
    equip_item,
    unequip_slot,
)

__all__ = [
    "add_to_backpack",
    "remove_from_backpack",
    "equip_item",
    "unequip_slot",
]