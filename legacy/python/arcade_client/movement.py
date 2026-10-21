import time

TILE_MOVE_INTERVAL = 0.30  # seconds per tile movement (your chosen speed)

class MovementController:
    def __init__(self, player_ref, direction_resolver=None):
        """
        direction_resolver: optional callable that translates any input payload
        (keyboard keycode, network event, etc.) into one of "up", "down",
        "left", or "right". If None, a simple string-based resolver is used.
        """

        self.player = player_ref
        self.holding = {"up": False, "down": False, "left": False, "right": False}
        self.last_move_time = 0
        self.direction_resolver = direction_resolver or self._default_direction_resolver

    def on_input(self, input_payload, pressed: bool):
        """Update directional state from an abstract input payload."""
        direction = self.direction_resolver(input_payload)
        if direction in self.holding:
            self.holding[direction] = pressed

    def on_key_press(self, key):
        """Compatibility layer for UI code to mark a key as pressed."""
        self.on_input(key, True)

    def on_key_release(self, key):
        """Compatibility layer for UI code to mark a key as released."""
        self.on_input(key, False)

    @staticmethod
    def _default_direction_resolver(input_payload):
        """Map simple string identifiers to cardinal directions."""
        if isinstance(input_payload, str):
            normalized = input_payload.lower()
            if normalized in {"w", "up"}:
                return "up"
            if normalized in {"s", "down"}:
                return "down"
            if normalized in {"a", "left"}:
                return "left"
            if normalized in {"d", "right"}:
                return "right"
        return None

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
