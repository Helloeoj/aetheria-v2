# inventory.py

from __future__ import annotations

from typing import TYPE_CHECKING

from aetheria_core.items import Item, ITEMS
from equipment_utils import is_two_handed

if TYPE_CHECKING:
    from aetheria_core.player import Player


def add_to_backpack(player: "Player", item_name: str, amount: int = 1) -> None:
    """Add items to the player's backpack stack."""
    if amount <= 0:
        return
    player.backpack[item_name] = player.backpack.get(item_name, 0) + amount


def remove_from_backpack(player: "Player", item_name: str, amount: int = 1) -> bool:
    """
    Remove items from the player's backpack stack.

    Returns True if successful, False if not enough items.
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


def equip_item(player: "Player", item_name: str) -> str:
    """
    Equip ONE item from the player's backpack into the correct equipment slot.

    - All items are stackable in backpack.
    - Equipment slots NEVER stack (they hold at most 1 item), except quiver.
    - Equipping removes 1 item from the backpack stack (or moves full stack into quiver).
    """
    if item_name not in ITEMS:
        return f"Item '{item_name}' does not exist."

    item: Item = ITEMS[item_name]

    if item.slot is None:
        return f"{item.name} cannot be equipped."

    stack_count = player.backpack.get(item_name, 0)
    if stack_count <= 0:
        return f"{player.name} has no {item.name} to equip."

    slot = item.slot

    # --- QUIVER: holds a stack of a single ammo type ---
    if slot == "quiver":
        if player.quiver_item is not None:
            if player.quiver_item.name == item_name:
                # Same ammo type: top up from backpack into quiver
                player.quiver_amount += stack_count
                del player.backpack[item_name]
                return (
                    f"Loaded {stack_count} more {item.name} into quiver "
                    f"(total {player.quiver_amount})."
                )
            else:
                # Different ammo type: return old ammo to backpack first
                add_to_backpack(player, player.quiver_item.name, player.quiver_amount)
                player.quiver_item = None
                player.quiver_amount = 0

        # Move entire stack into quiver
        player.quiver_item = item
        player.quiver_amount = stack_count
        del player.backpack[item_name]
        return f"Loaded {player.quiver_amount}x {item.name} into quiver."

    # Helper: unequip a slot if it has something
    def _unequip_slot_if_filled(slot_name: str):
        unequip_slot(player, slot_name)

    # --- WEAPON SLOT ---
    if slot == "weapon":
        if stack_count <= 0:
            return f"{player.name} has no {item.name} to equip."

        if is_two_handed(item):
            # Two-handed weapon: clear weapon & shield
            _unequip_slot_if_filled("weapon")
            _unequip_slot_if_filled("shield")
        else:
            # One-handed weapon: if current weapon is two-handed, unequip it first
            if player.weapon is not None and is_two_handed(player.weapon):
                _unequip_slot_if_filled("weapon")
            else:
                _unequip_slot_if_filled("weapon")

        if not remove_from_backpack(player, item_name, 1):
            return f"{player.name} has no {item.name} to equip."
        player.weapon = item
        return f"{player.name} equipped {item.name} as weapon."

    # --- SHIELD SLOT ---
    if slot == "shield":
        if player.weapon is not None and is_two_handed(player.weapon):
            return f"Cannot equip {item.name} because {player.weapon.name} is two-handed."

        _unequip_slot_if_filled("shield")

        if not remove_from_backpack(player, item_name, 1):
            return f"{player.name} has no {item.name} to equip."
        player.shield = item
        return f"{player.name} equipped {item.name} as shield."

    # --- ARMOR SLOTS ---
    if slot == "head":
        _unequip_slot_if_filled("head")
        if not remove_from_backpack(player, item_name, 1):
            return f"{player.name} has no {item.name} to equip."
        player.head = item
        return f"{player.name} equipped {item.name} on head."

    if slot == "chest":
        _unequip_slot_if_filled("chest")
        if not remove_from_backpack(player, item_name, 1):
            return f"{player.name} has no {item.name} to equip."
        player.chest = item
        return f"{player.name} equipped {item.name} on chest."

    if slot == "legs":
        _unequip_slot_if_filled("legs")
        if not remove_from_backpack(player, item_name, 1):
            return f"{player.name} has no {item.name} to equip."
        player.legs = item
        return f"{player.name} equipped {item.name} on legs."

    if slot == "cape":
        _unequip_slot_if_filled("cape")
        if not remove_from_backpack(player, item_name, 1):
            return f"{player.name} has no {item.name} to equip."
        player.cape = item
        return f"{player.name} equipped {item.name} as cape."

    if slot == "neck":
        _unequip_slot_if_filled("neck")
        if not remove_from_backpack(player, item_name, 1):
            return f"{player.name} has no {item.name} to equip."
        player.neck = item
        return f"{player.name} equipped {item.name} as necklace."

    # --- RING SLOTS ---
    if slot == "ring":
        if not remove_from_backpack(player, item_name, 1):
            return f"{player.name} has no {item.name} to equip."

        if player.ring1 is None:
            player.ring1 = item
            return f"{player.name} equipped {item.name} in ring slot 1."

        if player.ring2 is None:
            player.ring2 = item
            return f"{player.name} equipped {item.name} in ring slot 2."

        # Both full: replace ring1
        add_to_backpack(player, player.ring1.name, 1)
        player.ring1 = item
        return f"{player.name} replaced ring slot 1 with {item.name}."

    return f"{item.name} cannot be equipped."


def unequip_slot(player: "Player", slot_name: str) -> str:
    """
    Unequip whatever is in the given slot and return it to the backpack.
    """
    if slot_name == "head" and player.head is not None:
        add_to_backpack(player, player.head.name, 1)
        name = player.head.name
        player.head = None
        return f"Unequipped {name} from head."

    if slot_name == "chest" and player.chest is not None:
        add_to_backpack(player, player.chest.name, 1)
        name = player.chest.name
        player.chest = None
        return f"Unequipped {name} from chest."

    if slot_name == "legs" and player.legs is not None:
        add_to_backpack(player, player.legs.name, 1)
        name = player.legs.name
        player.legs = None
        return f"Unequipped {name} from legs."

    if slot_name == "cape" and player.cape is not None:
        add_to_backpack(player, player.cape.name, 1)
        name = player.cape.name
        player.cape = None
        return f"Unequipped {name} from cape."

    if slot_name == "neck" and player.neck is not None:
        add_to_backpack(player, player.neck.name, 1)
        name = player.neck.name
        player.neck = None
        return f"Unequipped {name} from neck."

    if slot_name == "ring1" and player.ring1 is not None:
        add_to_backpack(player, player.ring1.name, 1)
        name = player.ring1.name
        player.ring1 = None
        return f"Unequipped {name} from ring slot 1."

    if slot_name == "ring2" and player.ring2 is not None:
        add_to_backpack(player, player.ring2.name, 1)
        name = player.ring2.name
        player.ring2 = None
        return f"Unequipped {name} from ring slot 2."

    if slot_name == "weapon" and player.weapon is not None:
        add_to_backpack(player, player.weapon.name, 1)
        name = player.weapon.name
        player.weapon = None
        return f"Unequipped {name} from weapon slot."

    if slot_name == "shield" and player.shield is not None:
        add_to_backpack(player, player.shield.name, 1)
        name = player.shield.name
        player.shield = None
        return f"Unequipped {name} from shield slot."

    if slot_name == "quiver" and player.quiver_item is not None and player.quiver_amount > 0:
        add_to_backpack(player, player.quiver_item.name, player.quiver_amount)
        name = player.quiver_item.name
        amount = player.quiver_amount
        player.quiver_item = None
        player.quiver_amount = 0
        return f"Unequipped quiver: returned {amount}x {name} to backpack."

    return f"Nothing to unequip from {slot_name}."
