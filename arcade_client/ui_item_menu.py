import arcade

class ItemMenu:
    def __init__(self, game_ref, items_db):
        self.game = game_ref
        self.db = items_db
        self.visible = False
        self.input_text = ""
        self.status_text = "Type item ID and press ENTER to give+equip that item."

    # -------------------------------------------------------------
    # VISIBILITY
    # -------------------------------------------------------------
    def toggle(self):
        self.visible = not self.visible
        self.status_text = "Type item ID and press ENTER to give+equip that item."

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

            if item_id not in self.db:
                self.status_text = f"No item with ID {item_id}"
                return True

            item = self.db[item_id]
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
