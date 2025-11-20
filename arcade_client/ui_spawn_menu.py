import arcade

TILE_SIZE = 32


class SpawnMenu:
    """
    Very simple dev spawn menu.

    - Toggle with F5 (handled in main window).
    - When visible:
        * Type numeric monster ID.
        * ENTER spawns the monster with that ID.
        * ESC closes the menu.
    - Shows a short list of known monsters on the right.
    """

    def __init__(self, game_ref, monster_database):
        """
        game_ref: main Arcade window (AetheriaWindow)
        monster_database: dict of monster_id -> Monster template/definition
        """
        self.game = game_ref
        self.db = monster_database

        self.visible = False
        self.input_text = ""   # what the user typed (ID as string)
        self.status_text = "Type a monster ID and press Enter. ESC to close."

    # -------------------------------------------------------------
    # VISIBILITY
    # -------------------------------------------------------------
    def show(self):
        self.visible = True
        self.input_text = ""
        self.status_text = "Type a monster ID and press Enter. ESC to close."

    def hide(self):
        self.visible = False

    def toggle(self):
        if self.visible:
            self.hide()
        else:
            self.show()

    # -------------------------------------------------------------
    # INPUT HANDLING
    # -------------------------------------------------------------
    def on_key_press(self, key, modifiers):
        """Return True if we handled the key, False otherwise."""
        if not self.visible:
            return False

        # ESC → close menu
        if key == arcade.key.ESCAPE:
            self.hide()
            return True

        # ENTER → try to spawn
        if key == arcade.key.ENTER:
            self._spawn_from_input()
            return True

        # BACKSPACE → delete last character
        if key == arcade.key.BACKSPACE:
            if self.input_text:
                self.input_text = self.input_text[:-1]
            return True

        # Accept numeric input from top row or numpad
        key_to_digit = {
            arcade.key.KEY_0: "0",
            arcade.key.KEY_1: "1",
            arcade.key.KEY_2: "2",
            arcade.key.KEY_3: "3",
            arcade.key.KEY_4: "4",
            arcade.key.KEY_5: "5",
            arcade.key.KEY_6: "6",
            arcade.key.KEY_7: "7",
            arcade.key.KEY_8: "8",
            arcade.key.KEY_9: "9",
            arcade.key.NUM_0: "0",
            arcade.key.NUM_1: "1",
            arcade.key.NUM_2: "2",
            arcade.key.NUM_3: "3",
            arcade.key.NUM_4: "4",
            arcade.key.NUM_5: "5",
            arcade.key.NUM_6: "6",
            arcade.key.NUM_7: "7",
            arcade.key.NUM_8: "8",
            arcade.key.NUM_9: "9",
        }

        if key in key_to_digit:
            self.input_text += key_to_digit[key]
            return True

        # Ignore all other keys while menu is open
        return True

    def _spawn_from_input(self):
        text = self.input_text.strip()
        if not text:
            self.status_text = "No ID entered."
            return

        try:
            monster_id = int(text)
        except ValueError:
            self.status_text = f"'{text}' is not a valid number."
            return

        if monster_id not in self.db:
            self.status_text = f"Monster ID {monster_id} not found."
            return

        # Use the main window's helper to spawn it in front of the player
        try:
            self.game.spawn_monster_by_id(monster_id)
        except Exception as e:
            # If something unexpected happens, show a simple message
            self.status_text = f"Error spawning ID {monster_id}: {e}"
            return

        m = self.db[monster_id]
        name = getattr(m, "name", str(m))
        self.status_text = f"Spawned [{monster_id}] {name}"
        # Clear input so you can type a new one
        self.input_text = ""

    # -------------------------------------------------------------
    # DRAW
    # -------------------------------------------------------------
    def draw(self):
        if not self.visible:
            return

        # Background panel
        left = 80
        right = 760
        bottom = 60
        top = 420

        # IMPORTANT: this is lrbt, not lrtb
        arcade.draw_lrbt_rectangle_filled(
            left, right, bottom, top,
            arcade.color.DARK_SLATE_GRAY
        )

        # Title
        arcade.draw_text(
            "DEV SPAWN MENU (F5 to close)",
            left + 20,
            top - 40,
            arcade.color.AMBER,
            font_size=18,
        )

        # Input label + value
        arcade.draw_text(
            "Monster ID:",
            left + 20,
            top - 90,
            arcade.color.WHITE,
            font_size=14,
        )
        arcade.draw_text(
            self.input_text or "_",
            left + 140,
            top - 90,
            arcade.color.WHITE,
            font_size=14,
        )

        # Status / instructions text
        arcade.draw_text(
            self.status_text,
            left + 20,
            bottom + 40,
            arcade.color.LIGHT_GRAY,
            font_size=12,
            width=(right - left - 40),
            multiline=True,
        )

        # Monster list header
        arcade.draw_text(
            "Known Monsters:",
            left + 380,
            top - 90,
            arcade.color.WHITE,
            font_size=14,
        )

        # Scroll through the first ~15 monsters
        y = top - 120
        for mid in sorted(self.db.keys()):
            m = self.db[mid]
            name = getattr(m, "name", str(m))
            arcade.draw_text(
                f"[{mid}] {name}",
                left + 380,
                y,
                arcade.color.LIGHT_GRAY,
                font_size=12,
            )
            y -= 18
            if y < bottom + 60:
                break
