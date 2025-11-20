import arcade

class ItemMenu:
    def __init__(self, game_ref, items_db):
        self.game = game_ref
        self.db = items_db
        self.visible = False
        self.input_text = ""
        self.status_text = "Type item ID and press ENTER to give+equip that item."
        self.page_index = 0
        self.page_size = 20
        self.items_sorted = sorted(self.db.values(), key=lambda i: i.item_id)
        self.items_by_id = {item.item_id: item for item in self.items_sorted}

    # -------------------------------------------------------------
    # VISIBILITY
    # -------------------------------------------------------------
    def toggle(self):
        self.visible = not self.visible
        self.status_text = "Type item ID and press ENTER to give+equip that item."
        self.input_text = ""
        self.page_index = 0

    # -------------------------------------------------------------
    # INPUT HANDLERS
    # -------------------------------------------------------------
    def on_key_press(self, key, modifiers):
        if not self.visible:
            return False

        if key == arcade.key.ESCAPE:
            self.visible = False
            return True

        if key == arcade.key.ENTER:
            try:
                item_id = int(self.input_text.strip())
            except ValueError:
                self.status_text = "Invalid ID (must be integer)."
                return True

            item = self.items_by_id.get(item_id)
            if item is None:
                self.status_text = f"No item with ID {item_id}"
                return True

            self.game.player.give_and_equip(item)
            self.game.inventory_menu._refresh_combat_view()
            self.status_text = f"Gave + equipped {item.name}."
            self.input_text = ""
            return True

        # Handle numeric input
        if arcade.key.NUM_0 <= key <= arcade.key.NUM_9:
            digit = key - arcade.key.NUM_0
            self.input_text += str(digit)
            return True

        if arcade.key.KEY_0 <= key <= arcade.key.KEY_9:
            digit = key - arcade.key.KEY_0
            self.input_text += str(digit)
            return True

        if key == arcade.key.PAGEUP:
            if self.page_index > 0:
                self.page_index -= 1
            return True

        if key == arcade.key.PAGEDOWN:
            max_page = max(0, (len(self.items_sorted) - 1) // self.page_size)
            if self.page_index < max_page:
                self.page_index += 1
            return True

        if arcade.key.BACKSPACE == key:
            self.input_text = self.input_text[:-1]
            return True

        return False

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
        left = 40
        right = width - 40
        bottom = 40
        top = height - 40

        # Panel background
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

        # Input label + value
        arcade.draw_text(
            "Item ID:",
            left + 20,
            top - 110,
            arcade.color.WHITE,
            font_size=14,
        )
        arcade.draw_text(
            self.input_text or "_",
            left + 120,
            top - 110,
            arcade.color.WHITE,
            font_size=14,
        )

        # Status text
        arcade.draw_text(
            self.status_text,
            left + 20,
            bottom + 40,
            arcade.color.LIGHT_GRAY,
            font_size=12,
            width=(right - left - 40),
            multiline=True,
        )

        self._draw_item_list(left + 20, bottom + 80, right - 40, top - 160)

    def _draw_item_list(self, start_x: float, start_y: float, width: float, height: float):
        header = (
            "Items (PageUp/PageDown to scroll) — "
            f"Page {self.page_index + 1}/{max(1, (len(self.items_sorted) - 1) // self.page_size + 1)}"
        )
        arcade.draw_text(
            header,
            start_x,
            start_y + height,
            arcade.color.WHITE,
            font_size=14,
        )

        y = start_y + height - 30
        start = self.page_index * self.page_size
        page_items = self.items_sorted[start : start + self.page_size]

        if not page_items:
            arcade.draw_text(
                "No items registered.",
                start_x,
                y,
                arcade.color.LIGHT_GRAY,
                font_size=12,
            )
            return

        for item in page_items:
            arcade.draw_text(
                f"[{item.item_id}] {item.name}",
                start_x,
                y,
                arcade.color.LIGHT_GRAY,
                font_size=12,
            )
            y -= 18
