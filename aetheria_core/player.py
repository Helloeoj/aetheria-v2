# aetheria_core/player.py

from __future__ import annotations

from typing import Dict, Optional

from aetheria_core.items import ITEMS, Item


class Player:
    """
    Canonical player model shared by:
      - CLI tools
      - Arcade tick-combat client
    """

    def __init__(self, name: str):
        self.name = name

        # -------------------------------
        # LEVELS — OSRS-LIKE
        # -------------------------------
        self.levels: Dict[str, int] = {
            "attack": 1,
            "strength": 1,
            "defence": 1,
            "health": 10,
        }

        # -------------------------------
        # HEALTH
        # -------------------------------
        self.current_hp: int = self.levels["health"] * 20

        # -------------------------------
        # INVENTORY & EQUIPMENT
        # -------------------------------
        # Backpack is always: item_name -> quantity
        self.backpack: Dict[str, int] = {}

        # Equipment slots hold Item objects or None
        self.head: Optional[Item] = None
        self.chest: Optional[Item] = None
        self.legs: Optional[Item] = None
        self.cape: Optional[Item] = None
        self.neck: Optional[Item] = None
        self.ring1: Optional[Item] = None
        self.ring2: Optional[Item] = None
        self.weapon: Optional[Item] = None
        self.shield: Optional[Item] = None

        # Ranged ammo
        self.quiver_item: Optional[Item] = None
        self.quiver_amount: int = 0

        # -------------------------------
        # COMBAT STATE
        # -------------------------------
        # "slash", "stab", "blunt", "magic", "ranged"
        self.attack_style: str = "slash"

        self.entity_id: Optional[str] = None
        self.current_target: Optional[str] = None
        self.in_combat: bool = False

        # Simple world position (tile coords)
        self.x: int = 10
        self.y: int = 10

    # --------------------------------------------------------
    # PROPERTIES
    # --------------------------------------------------------
    @property
    def max_hp(self) -> int:
        return self.levels["health"] * 20

    @property
    def equipped(self) -> Dict[str, Optional[str]]:
        """Slot -> item name (or None), for pretty-print / saves."""
        return {
            "head": self.head.name if self.head else None,
            "chest": self.chest.name if self.chest else None,
            "legs": self.legs.name if self.legs else None,
            "cape": self.cape.name if self.cape else None,
            "neck": self.neck.name if self.neck else None,
            "ring1": self.ring1.name if self.ring1 else None,
            "ring2": self.ring2.name if self.ring2 else None,
            "weapon": self.weapon.name if self.weapon else None,
            "shield": self.shield.name if self.shield else None,
            "quiver_item": self.quiver_item.name if self.quiver_item else None,
        }

    # --------------------------------------------------------
    # LEVEL / HEALTH
    # --------------------------------------------------------
    def set_level(self, skill: str, value: int) -> None:
        if skill not in self.levels:
            return
        self.levels[skill] = max(1, int(value))
        if skill == "health" and self.current_hp > self.max_hp:
            self.current_hp = self.max_hp

    # --------------------------------------------------------
    # INVENTORY
    # --------------------------------------------------------
    def add_item(self, name: str, qty: int = 1) -> None:
        if name not in ITEMS or qty <= 0:
            return
        self.backpack[name] = self.backpack.get(name, 0) + qty

    def remove_item(self, name: str, qty: int = 1) -> bool:
        if qty <= 0:
            return True
        if name not in self.backpack:
            return False
        cur = self.backpack[name]
        if cur <= qty:
            del self.backpack[name]
            return True
        self.backpack[name] = cur - qty
        return True

    # --------------------------------------------------------
    # INTERNAL: EQUIPPED ITER
    # --------------------------------------------------------
    def _iter_equipped_items(self):
        for attr in (
            "head",
            "chest",
            "legs",
            "cape",
            "neck",
            "ring1",
            "ring2",
            "weapon",
            "shield",
        ):
            itm = getattr(self, attr)
            if itm is not None:
                yield itm

    # --------------------------------------------------------
    # INTERNAL: GEAR BONUSES
    # --------------------------------------------------------
    def _get_gear_attack_bonuses(self) -> Dict[str, int]:
        total = {"slash": 0, "stab": 0, "blunt": 0, "magic": 0, "ranged": 0}
        for item in self._iter_equipped_items():
            bonuses = getattr(item, "attack_bonuses", {}) or {}
            for k in total:
                total[k] += int(bonuses.get(k, 0))
        return total

    def _get_gear_defence_bonuses(self) -> Dict[str, float]:
        total = {"slash": 0.0, "stab": 0.0, "blunt": 0.0, "magic": 0.0, "ranged": 0.0}
        for item in self._iter_equipped_items():
            bonuses = getattr(item, "defence_bonuses", {}) or {}
            for k in total:
                total[k] += float(bonuses.get(k, 0.0))

        for k in total:
            if total[k] < -0.50:
                total[k] = -0.50
            if total[k] > 0.80:
                total[k] = 0.80
        return total

    def _get_total_accuracy_bonus(self) -> float:
        bonus = 0.0
        for item in self._iter_equipped_items():
            bonus += float(getattr(item, "accuracy_bonus", 0.0) or 0.0)
        return bonus

    # --------------------------------------------------------
    # INTERNAL: WEAPON INFO
    # --------------------------------------------------------
    def _get_weapon_speed(self) -> int:
        if self.weapon is None or not isinstance(self.weapon, Item):
            return 4
        return int(self.weapon.speed or 4)

    def _get_current_style(self) -> str:
        desired = self.attack_style or "slash"
        if desired not in ("slash", "stab", "blunt", "magic", "ranged"):
            desired = "slash"

        if self.weapon is None or not isinstance(self.weapon, Item):
            return "blunt"

        bonuses = getattr(self.weapon, "attack_bonuses", {}) or {}

        if bonuses.get(desired, 0) > 0:
            return desired

        best_style = desired
        best_value = -999
        for style, value in bonuses.items():
            if style in ("slash", "stab", "blunt", "magic", "ranged"):
                if value > best_value:
                    best_style = style
                    best_value = value

        return best_style

    # --------------------------------------------------------
    # PUBLIC: EQUIPPED NAMES (for UI / saves)
    # --------------------------------------------------------
    def get_equipped_names(self) -> Dict[str, Optional[str]]:
        data = dict(self.equipped)
        data["quiver_amount"] = self.quiver_amount
        return data

    # --------------------------------------------------------
    # PUBLIC: GIVE + EQUIP (used by dev UI)
    # --------------------------------------------------------
    def give_and_equip(self, item_name, slot=None):
    import aetheria_core.inventory as inv_mod
        """
        Dev helper used by Arcade item menu and CLI:
          - gives 1x item_name to backpack
          - equips it via the shared inventory module.
        """
        try:
            # Preferred: inventory.py inside the aetheria_core package
            from aetheria_core import inventory as inv_mod
        except ModuleNotFoundError:
            try:
                # Fallback: inventory.py at project root
                import inventory as inv_mod
            except ModuleNotFoundError:
                try:
                    # Last try: player/inventory.py style layout
                    from player import inventory as inv_mod
                except ModuleNotFoundError:
                    # All three failed: we *really* have no inventory module
                    self.add_item(item_name, 1)
                    return f"Gave {item_name}, but inventory module not available."

        # If we got here, one of the imports above worked
        add_to_backpack = getattr(inv_mod, "add_to_backpack")
        equip_item = getattr(inv_mod, "equip_item")

        add_to_backpack(self, item_name, 1)
        msg = equip_item(self, item_name)
        return msg

    # --------------------------------------------------------
    # COMBAT STATS FOR ENGINE
    # --------------------------------------------------------
    def get_combat_stats(self) -> Dict:
        attack_level = self.levels["attack"]
        strength_level = self.levels["strength"]
        defence_level = self.levels["defence"]

        gear_atk = self._get_gear_attack_bonuses()
        gear_def = self._get_gear_defence_bonuses()

        style = self._get_current_style()
        attack_speed = self._get_weapon_speed()

        # Attack roll
        effective_attack = attack_level + 8
        attack_bonus = gear_atk.get(style, 0)
        attack_roll = effective_attack * (attack_bonus + 64)

        if attack_roll <= 0:
            base_accuracy = 0.05
        else:
            base_accuracy = attack_roll / (attack_roll + 2000)

        base_accuracy += self._get_total_accuracy_bonus()
        accuracy = max(0.05, min(0.99, base_accuracy))

        # Max hit
        effective_strength = strength_level + 8
        strength_bonus = gear_atk.get(style, 0)
        max_hit = int((effective_strength * (strength_bonus + 64)) / 64)
        if max_hit < 1:
            max_hit = 1
        min_hit = max(0, max_hit // 3)

        return {
            "name": self.name,
            "style": style,
            "min_damage": int(min_hit),
            "max_damage": int(max_hit),
            "accuracy": round(accuracy, 3),
            "crit_chance": 0.05,
            "crit_multiplier": 1.5,
            "attack_speed": int(attack_speed),
            "resistances": gear_def,
            "health": {
                "current": int(self.current_hp),
                "max": int(self.max_hp),
            },
        }

    # --------------------------------------------------------
    # SUMMARY (for CLI debug)
    # --------------------------------------------------------
    def summary(self) -> Dict:
        return {
            "name": self.name,
            "hp": f"{self.current_hp}/{self.max_hp}",
            "levels": dict(self.levels),
            "equipped": self.equipped,
            "backpack": dict(self.backpack),
        }
