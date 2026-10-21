import importlib
import importlib.util
from typing import Dict, List, Tuple

import arcade


Rect = Tuple[float, float, float, float]


class InventoryMenu:
    """
    Visual equipment + backpack overlay.

    - Toggle via the main window (I key).
    - Click backpack items to equip.
    - Click equipment slots to unequip.
    """

    SLOT_LAYOUT = [
        ("Head", "head"),
        ("Neck", "neck"),
        ("Cape", "cape"),
        ("Chest", "chest"),
        ("Legs", "legs"),
        ("Weapon", "weapon"),
        ("Shield", "shield"),
        ("Ring 1", "ring1"),
        ("Ring 2", "ring2"),
        ("Quiver", "quiver"),
    ]

    INVENTORY_MODULE_CANDIDATES = (
        "aetheria_core.inventory",
        "inventory",
        "player.inventory",
    )

    def __init__(self, game_ref):
        self.game = game_ref
        self.visible: bool = False
        self.status_text: str = (
            "Click a backpack item to equip it. Click a slot to unequip."
        )

        self.inventory_module = self._find_inventory_module()
        self.slot_boxes: Dict[str, Rect] = {}
        self.backpack_boxes: List[Dict] = []

    # -------------------------------------------------------------
    # VISIBILITY
    # -------------------------------------------------------------
    def toggle(self):
        self.visible = not self.visible
        if self.visible:
            self.status_text = (
                "Click a backpack item to equip it. "
                "Click an equipment slot to unequip."
            )

    # -------------------------------------------------------------
    # INPUT HANDLERS
    # -------------------------------------------------------------
    def on_key_press(self, key, modifiers):
        if not self.visible:
            return False

        if key == arcade.key.ESCAPE:
            self.visible = False
            return True

        return False

    def on_mouse_press(self, x: float, y: float, button, modifiers):
        if not self.visible:
            return False

        # Equipment slots first (so you can click even if backpack overlaps)
        for slot, rect in self.slot_boxes.items():
            if self._point_in_rect(x, y, rect):
                self._handle_unequip(slot)
                return True

        # Backpack items to equip
        for entry in self.backpack_boxes:
            if self._point_in_rect(x, y, entry["rect"]):
                self._handle_equip(entry["name"])
                return True

        return False

    # -------------------------------------------------------------
    # INVENTORY/ACTION HELPERS
    # -------------------------------------------------------------
    @staticmethod
    def _point_in_rect(x: float, y: float, rect: Rect) -> bool:
        left, right, bottom, top = rect
        return left <= x <= right and bottom <= y <= top

    def _find_inventory_module(self):
        for name in self.INVENTORY_MODULE_CANDIDATES:
            if importlib.util.find_spec(name):
                return importlib.import_module(name)
        return None

    def _refresh_combat_view(self):
        refresh = getattr(self.game, "_refresh_player_actor_from_player", None)
        if callable(refresh):
            refresh()

    def _handle_equip(self, item_name: str):
        if self.inventory_module is None:
            self.status_text = "Inventory module not found; cannot equip."
            return

        equip_item = getattr(self.inventory_module, "equip_item", None)
        if not callable(equip_item):
            self.status_text = "equip_item not available on inventory module."
            return
        result = equip_item(self.game.player, item_name)
        self.status_text = result
        self._refresh_combat_view()

    def _handle_unequip(self, slot: str):
        if self.inventory_module is None:
            self.status_text = "Inventory module not found; cannot unequip."
            return

        unequip_item = getattr(self.inventory_module, "unequip_item", None)
        if not callable(unequip_item):
            self.status_text = "unequip_item not available on inventory module."
            return

        result = unequip_item(self.game.player, slot)
        self.status_text = result
        self._refresh_combat_view()

    # -------------------------------------------------------------
    # DRAW
    # -------------------------------------------------------------
    def draw(self):
        if not self.visible:
            return

        window = arcade.get_window()
        if not window:
            return

        width, height = window.width, window.height
        left = 30
        right = width - 30
        bottom = 40
        top = height - 30

        # Background panel
        arcade.draw_lbwh_rectangle_filled(
            left,
            bottom,
            right - left,
            top - bottom,
            arcade.color.DARK_SLATE_GRAY,
        )
        arcade.draw_lbwh_rectangle_outline(
            left,
            bottom,
            right - left,
            top - bottom,
            arcade.color.LIGHT_GRAY,
            border_width=2,
        )

        title_text = "Equipment & Backpack (I to close)"
        arcade.draw_text(
            title_text,
            left + 20,
            top - 30,
            arcade.color.WHITE,
            font_size=18,
        )

        arcade.draw_text(
            self.status_text,
            left + 20,
            bottom + 20,
            arcade.color.APRICOT,
            font_size=12,
        )

        # Equipment area
        self._draw_equipment_section(left + 20, top - 60)

        # Backpack area
        self._draw_backpack_section(right - 20, top - 60, left + 20, bottom + 60)

    def _draw_equipment_section(self, start_x: float, start_y: float):
        slot_width = 200
        slot_height = 52
        padding_x = 16
        padding_y = 10
        cols = 2

        y = start_y - 30
        self.slot_boxes = {}

        for idx, (label, attr) in enumerate(self.SLOT_LAYOUT):
            col = idx % cols
            row = idx // cols
            left = start_x + col * (slot_width + padding_x)
            right = left + slot_width
            top = y - row * (slot_height + padding_y)
            bottom = top - slot_height

            arcade.draw_lbwh_rectangle_filled(
                left,
                bottom,
                right - left,
                top - bottom,
                arcade.color.GRAY,
            )
            arcade.draw_lbwh_rectangle_outline(
                left,
                bottom,
                right - left,
                top - bottom,
                arcade.color.WHITE,
                border_width=2,
            )

            equipped = getattr(self.game.player, attr, None)
            display = "Empty"
            if attr == "quiver":
                if getattr(self.game.player, "quiver_item", None) is not None:
                    ammo = self.game.player.quiver_item.name
                    qty = getattr(self.game.player, "quiver_amount", 0)
                    display = f"{qty}x {ammo}" if qty else ammo
            elif equipped is not None:
                display = equipped.name

            arcade.draw_text(
                label,
                left + 8,
                top - 18,
                arcade.color.AQUA,
                font_size=12,
            )
            arcade.draw_text(
                display,
                left + 8,
                bottom + 14,
                arcade.color.LIGHT_GRAY,
                font_size=12,
            )

            self.slot_boxes[attr] = (left, right, bottom, top)

    def _draw_backpack_section(self, right_edge: float, top: float, left_edge: float, bottom: float):
        title = "Backpack Items"
        arcade.draw_text(
            title,
            left_edge,
            top,
            arcade.color.WHITE,
            font_size=14,
        )

        # Grid settings
        cols = 4
        cell_width = 140
        cell_height = 60
        grid_padding = 12

        section_left = right_edge - (cols * cell_width + (cols - 1) * grid_padding)
        y = top - 30

        items = []
        self.backpack_boxes = []

        # Show inventory from player.backpack (list of items)
        backpack = getattr(self.game.player, "backpack", {})
        if isinstance(backpack, dict):
            items = sorted(backpack.items(), key=lambda kv: kv[0])
        elif isinstance(backpack, list):
            counts = {}
            for item in backpack:
                name = getattr(item, "name", str(item))
                counts[name] = counts.get(name, 0) + 1
            items = sorted(counts.items(), key=lambda kv: kv[0])

        if not items:
            arcade.draw_text(
                "Backpack is empty.",
                section_left,
                y - 10,
                arcade.color.LIGHT_GRAY,
                font_size=12,
            )
            return

        for idx, (name, qty) in enumerate(items):
            col = idx % cols
            row = idx // cols
            left = section_left + col * (cell_width + grid_padding)
            right = left + cell_width
            top = y - row * (cell_height + grid_padding)
            bottom = top - cell_height

            arcade.draw_lbwh_rectangle_filled(
                left,
                bottom,
                right - left,
                top - bottom,
                arcade.color.DARK_BLUE_GRAY,
            )
            arcade.draw_lbwh_rectangle_outline(
                left,
                bottom,
                right - left,
                top - bottom,
                arcade.color.LIGHT_GRAY,
                border_width=1,
            )

            arcade.draw_text(
                name,
                left + 6,
                top - 18,
                arcade.color.LIGHT_GREEN,
                font_size=12,
                width=cell_width - 12,
                multiline=True,
            )
            arcade.draw_text(
                f"x{qty}",
                left + 6,
                bottom + 12,
                arcade.color.YELLOW,
                font_size=12,
            )

            self.backpack_boxes.append(
                {
                    "name": name,
                    "rect": (left, right, bottom, top),
                }
            )
