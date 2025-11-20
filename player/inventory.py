"""
Simple inventory + equipment helpers for the core :class:`Player`.

This module is intentionally lightweight so new contributors can read it
quickly. It exposes a handful of free functions that operate on a
``Player`` instance:

- ``add_to_backpack``: add or stack loose items in the backpack.
- ``remove_from_backpack``: safely remove from a stack.
- ``equip_item``: move one item from the backpack into the right slot.
- ``unequip_slot``: move whatever is in a slot back to the backpack.

Where does this file live?
==========================
The path inside the repository is ``player/inventory.py``. If you have
cloned the repo, you can open or replace the file at:

    aetheria-game/player/inventory.py

The functions below are used by the ``aetheria_core.player.Player`` class
(as well as other helpers) to equip and unequip gear.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Callable, Dict, Optional

from aetheria_core.items import Item, ITEMS
from items.equipment_utils import is_two_handed

if TYPE_CHECKING:
    from aetheria_core.player import Player


# ---------------------------------------------------------------------------
# Backpack helpers
# ---------------------------------------------------------------------------

def add_to_backpack(player: "Player", item_name: str, amount: int = 1) -> None:
    """Add a quantity of an item to the player's backpack stack.

    A non-positive ``amount`` is ignored so callers do not have to pre-check
    values.
    """
    if amount <= 0:
        return
    player.backpack[item_name] = player.backpack.get(item_name, 0) + amount


def remove_from_backpack(player: "Player", item_name: str, amount: int = 1) -> bool:
    """Attempt to remove items from the backpack stack.

    Returns ``True`` when the items were removed (or ``amount`` was not
    positive), and ``False`` when the player did not have enough in the stack.
    """
    if amount <= 0:
        return True

    current = player.backpack.get(item_name, 0)
    if current < amount:
        return False

    new_amount = current - amount
    if new_amount > 0:
        player.backpack[item_name] = new_amount
    else:
        del player.backpack[item_name]

    return True


# ---------------------------------------------------------------------------
# Equipment helpers
# ---------------------------------------------------------------------------

def _unequip_and_store(player: "Player", slot_name: str, current_item: Optional[Item]) -> None:
    """Return the current item in ``slot_name`` back to the backpack."""
    if current_item is not None:
        add_to_backpack(player, current_item.name, 1)
        setattr(player, slot_name, None)


def _set_slot(player: "Player", slot_name: str, item: Item) -> None:
    """Equip ``item`` into ``slot_name`` without touching the backpack."""
    setattr(player, slot_name, item)


def equip_item(player: "Player", item_name: str) -> str:
    """Equip one item from the backpack into the appropriate equipment slot.

    Rules implemented here:
    - Backpack stacks items; equipment slots (except quiver) do not stack.
    - Equipping consumes **one** item from the backpack stack unless the
      quiver is filled, in which case the entire stack is moved.
    - Two-handed weapons clear the shield slot before equipping.
    """
    if item_name not in ITEMS:
        return f"Item '{item_name}' does not exist."

    stack_count = player.backpack.get(item_name, 0)
    if stack_count <= 0:
        return f"{player.name} has no {item_name} to equip."

    item: Item = ITEMS[item_name]
    slot = item.slot

    if slot is None:
        return f"{item.name} cannot be equipped."

    # ----------------------
    # Quiver (stacked ammo)
    # ----------------------
    if slot == "quiver":
        if player.quiver_item is not None:
            if player.quiver_item.name == item_name:
                player.quiver_amount += stack_count
                del player.backpack[item_name]
                return f"Loaded {stack_count} more {item.name} into quiver (total {player.quiver_amount})."

            add_to_backpack(player, player.quiver_item.name, player.quiver_amount)
            player.quiver_item = None
            player.quiver_amount = 0

        player.quiver_item = item
        player.quiver_amount = stack_count
        del player.backpack[item_name]
        return f"Loaded {player.quiver_amount}x {item.name} into quiver."

    # Helper to unequip with nice reuse
    def clear_slot(slot_name: str) -> None:
        current: Optional[Item] = getattr(player, slot_name)
        _unequip_and_store(player, slot_name, current)

    # ----------------------
    # Weapon slot
    # ----------------------
    if slot == "weapon":
        if is_two_handed(item):
            clear_slot("weapon")
            clear_slot("shield")
        else:
            clear_slot("weapon")

        if not remove_from_backpack(player, item_name, 1):
            return f"{player.name} has no {item.name} to equip."

        _set_slot(player, "weapon", item)
        return f"{player.name} equipped {item.name} as weapon."

    # ----------------------
    # Shield slot
    # ----------------------
    if slot == "shield":
        if player.weapon is not None and is_two_handed(player.weapon):
            return f"Cannot equip {item.name} because {player.weapon.name} is two-handed."

        clear_slot("shield")

        if not remove_from_backpack(player, item_name, 1):
            return f"{player.name} has no {item_name} to equip."

        _set_slot(player, "shield", item)
        return f"{player.name} equipped {item.name} as shield."

    # ----------------------
    # Armor slots (single)
    # ----------------------
    single_slots: Dict[str, str] = {
        "head": "head",
        "chest": "chest",
        "legs": "legs",
        "cape": "cape",
        "neck": "neck",
    }
    if slot in single_slots:
        target = single_slots[slot]
        clear_slot(target)

        if not remove_from_backpack(player, item_name, 1):
            return f"{player.name} has no {item_name} to equip."

        _set_slot(player, target, item)
        return f"{player.name} equipped {item.name} on {target}."

    # ----------------------
    # Ring slots (two available)
    # ----------------------
    if slot == "ring":
        if not remove_from_backpack(player, item_name, 1):
            return f"{player.name} has no {item_name} to equip."

        if player.ring1 is None:
            _set_slot(player, "ring1", item)
            return f"{player.name} equipped {item.name} in ring slot 1."

        if player.ring2 is None:
            _set_slot(player, "ring2", item)
            return f"{player.name} equipped {item.name} in ring slot 2."

        add_to_backpack(player, player.ring1.name, 1)
        _set_slot(player, "ring1", item)
        return f"{player.name} replaced ring slot 1 with {item.name}."

    return f"{item.name} cannot be equipped."


def unequip_slot(player: "Player", slot_name: str) -> str:
    """Unequip whatever is in ``slot_name`` and return it to the backpack."""
    slot_map: Dict[str, Callable[["Player"], Optional[Item]]] = {
        "head": lambda p: p.head,
        "chest": lambda p: p.chest,
        "legs": lambda p: p.legs,
        "cape": lambda p: p.cape,
        "neck": lambda p: p.neck,
        "ring1": lambda p: p.ring1,
        "ring2": lambda p: p.ring2,
        "weapon": lambda p: p.weapon,
        "shield": lambda p: p.shield,
    }

    if slot_name == "quiver" and player.quiver_item is not None and player.quiver_amount > 0:
        add_to_backpack(player, player.quiver_item.name, player.quiver_amount)
        name = player.quiver_item.name
        amount = player.quiver_amount
        player.quiver_item = None
        player.quiver_amount = 0
        return f"Unequipped quiver: returned {amount}x {name} to backpack."

    getter = slot_map.get(slot_name)
    if getter is None:
        return f"Unknown slot '{slot_name}'."

    current_item = getter(player)
    if current_item is None:
        return f"Nothing to unequip from {slot_name}."

    add_to_backpack(player, current_item.name, 1)
    setattr(player, slot_name, None)
    return f"Unequipped {current_item.name} from {slot_name}."
