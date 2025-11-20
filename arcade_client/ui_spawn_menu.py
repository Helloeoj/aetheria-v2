import arcade

class SpawnMenu:
    def __init__(self, game_ref, monster_db):
        self.game = game_ref
        self.db = monster_db
        self.visible = False
        self.input_text = ""
        self.status_text = "Type monster ID and press Enter to spawn."

    # -------------------------------------------------------------
    # VISIBILITY
    # -------------------------------------------------------------
    def toggle(self):
        self.visible = not self.visible
        self.status_text = "Type monster ID and press Enter to spawn."

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
                monster_id = int(self.input_text.strip())
            except ValueError:
                self.status_text = "Invalid ID (must be integer)."
                return True

            self.game.spawn_monster_by_id(monster_id)
            self.status_text = f"Spawned monster {monster_id}."
            self.input_text = ""
            return True

        # Handle numeric input
        if arcade.key.NUM_0 <= key <= arcade.key.NUM_9:
            digit = key - arcade.key.NUM_0
            self.input_text += str(digit)
            return True

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

        # Background panel
        left = 80
        right = 760
        bottom = 60
        top = 420

        arcade.draw_lbwh_rectangle_filled(
            left,
            bottom,
            right - left,
            top - bottom,
            arcade.color.DARK_SLATE_GRAY,
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
