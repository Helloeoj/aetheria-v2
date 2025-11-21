"""Compatibility wrapper that re-exports inventory helpers from
:mod:`aetheria_core.inventory`.

The real logic now lives in the core package so that all front-ends share the
same data-only helpers. This module simply forwards imports for callers that
still reference :mod:`player.inventory`.
"""

from __future__ import annotations

from aetheria_core.inventory import *  # noqa: F401,F403

__all__ = [
    "add_to_backpack",
    "remove_from_backpack",
    "equip_item",
    "unequip_slot",
]
