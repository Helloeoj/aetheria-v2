# ============================================================
# AETHERIA — PLAYER CLASS (PHASE 2 REWRITE)
# Adds:
# - manual attack styles
# - equipment stat bonuses
# - combat stat aggregation
# - weapon speed (ticks)
# - attack ranges
# - projectile speeds
# - world position + movement (for Arcade later)
# ============================================================

from dataclasses import dataclass, field
from math import sqrt


# ============================================================
#      PLAYER CONSTANTS & ATTACK STYLES
# ============================================================

VALID_MELEE_STYLES = ["stab", "slash", "blunt"]
VALID_MAGIC_STYLES = ["magic"]
VALID_RANGED_STYLES = ["ranged"]


# Weapon type → default projectile speed (tiles per tick)
PROJECTILE_SPEEDS = {
    "bow": 3.0,
    "crossbow": 2.2,
    "wand": 2.5,
    "staff": 2.0,
    "spell": 2.4,
    "thrown": 2.8
}

# Default attack ranges per category
ATTACK_RANGES = {
    "melee": 2.0,
    "ranged": 18.0,
    "crossbow": 22.0,
    "magic": 20.0,
}


# ============================================================
#                PLAYER CLASS
# ============================================================

class Player:
    def __init__(self, name):
        self.name = name

        # ---- Base stats (these expand later) ----
        self.levels = {
            "attack": 1,
            "strength": 1,
            "defence": 1,
            "magic": 1,
            "ranged": 1,
            "health_level": 10
        }

        self.max_hp = self.levels["health_level"] * 10
        self.current_hp = self.max_hp

        # ---- Equipment + Inventory ----
        self.equipped = {
            "head": None,
            "chest": None,
            "legs": None,
            "cape": None,
            "neck": None,
            "ring1": None,
            "ring2": None,
            "weapon": None,
            "shield": None,
            "quiver_item": None
        }

        self.backpack = {}  # item_name → quantity

        # ---- Combat info ----
        self.current_attack_style = "slash"  # default
        self.swing_timer = 0

        # ---- World position (Arcade) ----
        self.x = 5
        self.y = 5

    # -----------------------------------------------------------
    # POSITION HELPERS
    # -----------------------------------------------------------
    @property
    def position(self):
        return (self.x, self.y)

    def move(self, dx, dy):
        """Arcade client will call this every frame."""
        self.x += dx
        self.y += dy

    # -----------------------------------------------------------
    # EQUIPMENT + INVENTORY
    # -----------------------------------------------------------

    def add_to_backpack(self, item_name, qty=1):
        self.backpack[item_name] = self.backpack.get(item_name, 0) + qty

    def remove_from_backpack(self, item_name, qty=1):
        if item_name not in self.backpack:
            return
        self.backpack[item_name] -= qty
        if self.backpack[item_name] <= 0:
            del self.backpack[item_name]

    def equip_item(self, item):
        """Equips any valid gear item."""
        slot = item.equip_slot
        if slot is None:
            return False

        # Rings: need ring1 / ring2 logic
        if slot == "ring":
            if self.equipped["ring1"] is None:
                self.equipped["ring1"] = item
            elif self.equipped["ring2"] is None:
                self.equipped["ring2"] = item
            else:
                # Replace ring1 for now
                self.backpack[self.equipped["ring1"].name] = \
                    self.backpack.get(self.equipped["ring1"].name, 0) + 1
                self.equipped["ring1"] = item
            self.remove_from_backpack(item.name, 1)
            return True

        # Standard slot equip
        previous = self.equipped.get(slot)
        if previous:
            # Return old item to inventory
            self.backpack[previous.name] = self.backpack.get(previous.name, 0) + 1

        self.equipped[slot] = item
        self.remove_from_backpack(item.name, 1)
        return True

    # -----------------------------------------------------------
    # WEAPON & STYLES
    # -----------------------------------------------------------

    def get_equipped_weapon(self):
        return self.equipped["weapon"]

    def get_valid_styles_for_weapon(self):
        """Return list of valid styles based on weapon stats."""
        weapon = self.get_equipped_weapon()
        if weapon is None:
            return ["blunt"]  # unarmed fallback

        valid = []

        if weapon.stab_bonus > 0:
            valid.append("stab")
        if weapon.slash_bonus > 0:
            valid.append("slash")
        if weapon.blunt_bonus > 0:
            valid.append("blunt")
        if weapon.magic_bonus > 0:
            valid.append("magic")
        if weapon.ranged_bonus > 0:
            valid.append("ranged")

        return valid

    def set_attack_style(self, style):
        valid_styles = self.get_valid_styles_for_weapon()
        if style in valid_styles:
            self.current_attack_style = style
            return True
        return False

    # -----------------------------------------------------------
    # ATTACK SPEED, PROJECTILE SPEED, RANGE
    # -----------------------------------------------------------

    def weapon_speed_in_ticks(self):
        """Return weapon swing speed in ticks."""
        weapon = self.get_equipped_weapon()
        if weapon is None:
            return 4  # unarmed default

        return weapon.attack_speed_ticks

    def get_attack_range(self):
        """Return max range based on attack style."""
        style = self.current_attack_style

        if style in VALID_MELEE_STYLES:
            return ATTACK_RANGES["melee"]

        if style == "magic":
            return ATTACK_RANGES["magic"]

        if style == "ranged":
            weapon = self.get_equipped_weapon()
            if weapon is None:
                return ATTACK_RANGES["ranged"]

            if weapon.weapon_type == "crossbow":
                return ATTACK_RANGES["crossbow"]
            return ATTACK_RANGES["ranged"]

        return 2.0

    def get_projectile_speed(self):
        """Return projectile travel speed."""
        weapon = self.get_equipped_weapon()
        if weapon is None:
            return 2.0

        return PROJECTILE_SPEEDS.get(weapon.weapon_type, 2.0)

    # -----------------------------------------------------------
    # CALCULATE COMBAT BONUSES (ATTACK & DAMAGE)
    # -----------------------------------------------------------

    def calculate_attack_bonuses(self):
        """
        Aggregate all gear stats into a consistent dictionary:
        {
            "stab_acc": 0.72,
            "stab_dmg": (12, 19),
            "slash_acc": 0.81,
            "slash_dmg": (14, 22),
            ...
        }
        """

        # Base values
        bonuses = {
            "stab_acc": 0,
            "slash_acc": 0,
            "blunt_acc": 0,
            "magic_acc": 0,
            "ranged_acc": 0,

            "stab_dmg": (1, 3),
            "slash_dmg": (1, 3),
            "blunt_dmg": (1, 3),
            "magic_dmg": (1, 3),
            "ranged_dmg": (1, 3),
        }

        # Loop through equipped items
        for item in self.equipped.values():
            if item is None:
                continue

            # Accuracy bonuses
            bonuses["stab_acc"] += item.stab_bonus
            bonuses["slash_acc"] += item.slash_bonus
            bonuses["blunt_acc"] += item.blunt_bonus
            bonuses["magic_acc"] += item.magic_bonus
            bonuses["ranged_acc"] += item.ranged_bonus

            # Damage upgrades
            # We scale damage based on tier and weapon classifications
            bonuses["stab_dmg"] = (
                bonuses["stab_dmg"][0] + item.stab_min_damage,
                bonuses["stab_dmg"][1] + item.stab_max_damage,
            )

            bonuses["slash_dmg"] = (
                bonuses["slash_dmg"][0] + item.slash_min_damage,
                bonuses["slash_dmg"][1] + item.slash_max_damage,
            )

            bonuses["blunt_dmg"] = (
                bonuses["blunt_dmg"][0] + item.blunt_min_damage,
                bonuses["blunt_dmg"][1] + item.blunt_max_damage,
            )

            bonuses["magic_dmg"] = (
                bonuses["magic_dmg"][0] + item.magic_min_damage,
                bonuses["magic_dmg"][1] + item.magic_max_damage,
            )

            bonuses["ranged_dmg"] = (
                bonuses["ranged_dmg"][0] + item.ranged_min_damage,
                bonuses["ranged_dmg"][1] + item.ranged_max_damage,
            )

        # Convert accuracy into 0.0–1.0 scale
        for key in ["stab_acc", "slash_acc", "blunt_acc", "magic_acc", "ranged_acc"]:
            bonuses[key] = min(1.0, bonuses[key])

        return bonuses

    # -----------------------------------------------------------
    # HARD RESET
    # -----------------------------------------------------------

    def reset_hp(self):
        self.current_hp = self.max_hp

    def full_reset(self):
        self.reset_hp()
        self.swing_timer = 0

    # -----------------------------------------------------------
    # PRETTY PRINT PANEL SUPPORT (CLI SIDE)
    # -----------------------------------------------------------

    def summary(self):
        return {
            "name": self.name,
            "position": self.position,
            "hp": f"{self.current_hp}/{self.max_hp}",
            "attack_style": self.current_attack_style,
            "equipped": {slot: (item.name if item else None) for slot, item in self.equipped.items()},
            "backpack": self.backpack
        }
