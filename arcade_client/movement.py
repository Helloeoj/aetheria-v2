import arcade
import time

TILE_MOVE_INTERVAL = 0.30  # seconds per tile movement (your chosen speed)

class MovementController:
    def __init__(self, player_ref):
        self.player = player_ref
        self.holding = {"up": False, "down": False, "left": False, "right": False}
        self.last_move_time = 0

    def on_key_press(self, key):
        if key == arcade.key.W:
            self.holding["up"] = True
        elif key == arcade.key.S:
            self.holding["down"] = True
        elif key == arcade.key.A:
            self.holding["left"] = True
        elif key == arcade.key.D:
            self.holding["right"] = True

    def on_key_release(self, key):
        if key == arcade.key.W:
            self.holding["up"] = False
        elif key == arcade.key.S:
            self.holding["down"] = False
        elif key == arcade.key.A:
            self.holding["left"] = False
        elif key == arcade.key.D:
            self.holding["right"] = False

    def update(self, delta_time):
        """Called every frame. Moves player once per TILE_MOVE_INTERVAL."""
        now = time.time()
        if now - self.last_move_time < TILE_MOVE_INTERVAL:
            return

        dx = 0
        dy = 0

        # Determine movement direction (tile-based)
        if self.holding["up"]:
            dy = 1
        elif self.holding["down"]:
            dy = -1

        if self.holding["left"]:
            dx = -1
        elif self.holding["right"]:
            dx = 1

        # No movement?
        if dx == 0 and dy == 0:
            return

        # Apply movement (tile size handled by renderer)
        self.player.x += dx
        self.player.y += dy

        self.last_move_time = now
