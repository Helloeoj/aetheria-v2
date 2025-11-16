from typing import Optional
from .items import Item  # assumes equipment_utils.py is in the same package as items.py


def is_ammo(item: Item) -> bool:
    """
    Returns True if this item is equippable/usable ammo (arrows, bolts, etc.).
    Crafting components like 'Arrow Shafts' or 'Arrow Heads' will return False.
    """
    name = item.name

    # You can loosen this if you want, but this is safe to start with.
    if item.item_type not in ("Weapon", "Armor", "Enchantment/Misc", "Crafting"):
        return False

    ammo_suffixes = (" Arrow", " Arrows", " Bolt", " Bolts")

    return any(name.endswith(sfx) for sfx in ammo_suffixes)


def is_two_handed(item: Item) -> bool:
    """
    Returns True if this weapon should occupy both the weapon and offhand slots.
    """
    if item.item_type != "Weapon":
        return False

    name = item.name

    # 2h weapons in your game:
    # - Warmauls
    # - Bows
    # - Magic Staffs
    two_handed_keywords = [
        "Warmaul",
        " Bow",        # 'Bronze Bow', 'Starforged Bow', etc.
        "Magic Staff",
    ]

    return any(key in name for key in two_handed_keywords)


def get_item_slot(item: Item) -> Optional[str]:
    """
    Decide which equipment slot an item should occupy, based on its name and type.

    Returns one of:
      'weapon', 'offhand', 'head', 'chest', 'legs', 'shield',
      'ring', 'neck', 'cape', 'ammo'
    or None if it isn't equippable.
    """

    name = item.name

    # --- Weapons ---
    if item.item_type == "Weapon":
        # All weapons go in the weapon slot.
        # 2h behavior is handled separately by is_two_handed().
        return "weapon"

    # --- Armor / Accessories ---
    if item.item_type == "Armor":
        # Body armor
        if "Helmet" in name:
            return "head"
        if "Platebody" in name:
            return "chest"
        if "Platelegs" in name:
            return "legs"

        # Shields
        if "Kiteshield" in name or "Square Shield" in name:
            return "shield"

        # Jewelry / accessories
        if "Ring" in name:
            return "ring"
        if "Necklace" in name:
            return "neck"
        if "Cape" in name:
            return "cape"

    # --- Ammo ---
    if is_ammo(item):
        return "ammo"

    # Not equippable (materials, food, crafting components, etc.)
    return None
