import arcade

TILE_SIZE = 32


class ItemMenu:
    """
    Dev item menu.

    - Toggle with F6 (handled in main window).
    - When visible:
        * Type numeric item ID.
        * ENTER to give+equip that item to the player.
        * ESC closes the menu.
        * PageUp/PageDown to scroll through pages of items.
    """

    def __init__(self, game_ref, item_registry):
        """
        game_ref: the AetheriaWindow instance.
        item_registry: dict of name -> Item (aetheria_core.items.ITEMS)
        """
        self.game = game_ref
        self.visible = False
        self.input_text = ""
        self.status_text = ""

        # Build ID -> Item mapping from the registry
        self.items_by_id = {}
        for item in item_registry.values():
            item_id = getattr(item, "item_id", None)
            if isinstance(item_id, int):
                self.items_by_id[item_id] = item

        # Sorted list of all IDs
        self.sorted_ids = sorted(self.items_by_id.keys())

        # Pagination
        self.items_per_page = 25
        self.page_index = 0

    # --------------------
    # BASIC CONTROL
    # --------------------
    def toggle(self):
        self.visible = not self.visible
        self.input_text = ""
        self.status_text = ""
        # Keep page_index as-is so you can reopen where you left off

    # --------------------
    # INPUT HANDLING
    # --------------------
    def on_key_press(self, key, modifiers):
        if not self.visible:
            return False  # not handled

        # ESC: close the menu
        if key == arcade.key.ESCAPE:
            self.visible = False
            return True

        # PAGE UP: previous page
        if key == arcade.key.PAGEUP:
            if self.page_index > 0:
                self.page_index -= 1
            return True

        # PAGE DOWN: next page
        if key == arcade.key.PAGEDOWN:
            if self.items_per_page > 0 and self.sorted_ids:
                max_page = (len(self.sorted_ids) - 1) // self.items_per_page
                if self.page_index < max_page:
                    self.page_index += 1
            return True

        # BACKSPACE: delete last digit
        if key == arcade.key.BACKSPACE:
            self.input_text = self.input_text[:-1]
            return True

        # ENTER: attempt to give+equip item by ID
        if key in (arcade.key.ENTER, arcade.key.RETURN):
            self._handle_enter()
            return True

        # DIGITS from numpad: NUM_0 .. NUM_9
        if arcade.key.NUM_0 <= key <= arcade.key.NUM_9:
            if len(self.input_text) < 4:
                digit = "0123456789"[key - arcade.key.NUM_0]
                self.input_text += digit
            return True

        # DIGITS from main number row (Pyglet keycodes line up with ASCII)
        try:
            ch = chr(key)
        except (ValueError, TypeError, OverflowError):
            ch = ""

        if ch.isdigit():
            if len(self.input_text) < 4:
                self.input_text += ch
            return True

        return False  # key not handled

    def _handle_enter(self):
        if not self.input_text:
            self.status_text = "Type an item ID, then press Enter."
            return

        try:
            item_id = int(self.input_text)
        except ValueError:
            self.status_text = f"'{self.input_text}' is not a valid ID."
            self.input_text = ""
            return

        item = self.items_by_id.get(item_id)
        if not item:
            self.status_text = f"No item with ID {item_id}."
            self.input_text = ""
            return

        # Give + equip using the Player helper (from aetheria_core.player.Player)
        player = self.game.player
        if hasattr(player, "give_and_equip"):
            msg = player.give_and_equip(item.name)
            self.status_text = msg
        else:
            # Fallback: just add 1x to backpack if helper missing
            if hasattr(player, "add_item"):
                player.add_item(item.name, 1)
                self.status_text = f"Gave 1x {item.name} (no equip helper)."
            else:
                self.status_text = "Player has no give_and_equip or add_item."

        # Clear input for next ID
        self.input_text = ""

    # --------------------
    # DRAW
    # --------------------
    def draw(self):
        if not self.visible:
            return

        window = arcade.get_window()
        if not window:
            return

        width, height = window.width, window.height
        left = 40
        right = width - 40
        bottom = 40
        top = height - 40

        # Panel background
        arcade.draw_lrbt_rectangle_filled(
            left,
            right,
            bottom,
            top,
            arcade.color.DARK_SLATE_GRAY,
        )
        arcade.draw_lrbt_rectangle_outline(
            left,
            right,
            bottom,
            top,
            arcade.color.WHITE,
            border_width=2,
        )

        # Title / instructions
        arcade.draw_text(
            "ITEM DEV MENU (F6 to close)",
            left + 20,
            top - 40,
            arcade.color.WHITE,
            font_size=18,
        )

        arcade.draw_text(
            "Type item ID and press ENTER to give+equip that item.",
            left + 20,
            top - 70,
            arcade.color.LIGHT_GRAY,
            font_size=12,
        )

        # Current input
        arcade.draw_text(
            f"ID: {self.input_text or '_'}",
            left + 20,
            top - 110,
            arcade.color.YELLOW,
            font_size=16,
        )

        # Status/error message
        if self.status_text:
            arcade.draw_text(
                self.status_text,
                left + 20,
                bottom + 60,
                arcade.color.LIGHT_GREEN,
                font_size=12,
            )

        # Page indicator
        if self.items_per_page > 0 and self.sorted_ids:
            max_page = (len(self.sorted_ids) - 1) // self.items_per_page
            page_text = f"Page {self.page_index + 1}/{max_page + 1} (PageUp/PageDown)"
        else:
            page_text = "Page 1/1"

        arcade.draw_text(
            page_text,
            left + 380,
            top - 40,
            arcade.color.WHITE,
            font_size=10,
        )

        # Item list on the right
        arcade.draw_text(
            "Items (ID → name):",
            left + 380,
            top - 60,
            arcade.color.WHITE,
            font_size=12,
        )

        y = top - 80

        if self.items_per_page > 0 and self.sorted_ids:
            start = self.page_index * self.items_per_page
            end = start + self.items_per_page
            slice_ids = self.sorted_ids[start:end]
        else:
            slice_ids = []

        for iid in slice_ids:
            item = self.items_by_id[iid]
            arcade.draw_text(
                f"[{iid}] {item.name}",
                left + 380,
                y,
                arcade.color.LIGHT_GRAY,
                font_size=12,
            )
            y -= 18
            if y < bottom + 60:
                break
