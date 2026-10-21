import random
import time
from math import sqrt


ROAM_MIN_DELAY = 0.6    # Minimum seconds between movement attempts
ROAM_MAX_DELAY = 1.2    # Max time before next movement attempt


class MonsterRoamingAI:
    def __init__(self, monster_sprite):
        """
        AI controller for roaming monsters.
        monster_sprite: instance of MonsterSprite
        """
        self.sprite = monster_sprite
        self.last_move_time = 0
        self.next_move_delay = random.uniform(ROAM_MIN_DELAY, ROAM_MAX_DELAY)

        # No active target point yet
        self.target_x = None
        self.target_y = None

    # ------------------------------------------------------------
    # UTILS
    # ------------------------------------------------------------

    def _distance(self, x1, y1, x2, y2):
        """Euclidean distance."""
        return sqrt((x1 - x2)**2 + (y1 - y2)**2)

    # ------------------------------------------------------------
    # MAIN UPDATE (called every tick/frame)
    # ------------------------------------------------------------

    def update(self):
        """Updates roaming behavior if monster is NOT in combat."""
        now = time.time()

        # If monster has low HP or is in combat, do NOT roam
        if self.sprite.monster.in_combat:
            return

        # Wait until enough time has passed before moving again
        if now - self.last_move_time < self.next_move_delay:
            return

        # Either no target position OR we reached it → pick new roaming goal
        if self.target_x is None or self.target_y is None:
            self._pick_new_target()

        # Attempt to move 1 tile toward target
        self._move_toward_target()

        # Reset timer
        self.last_move_time = now
        self.next_move_delay = random.uniform(ROAM_MIN_DELAY, ROAM_MAX_DELAY)

    # ------------------------------------------------------------
    # PICK NEW RANDOM TILE WITHIN ROAM RADIUS
    # ------------------------------------------------------------

    def _pick_new_target(self):
        """Pick a new tile within roam radius of spawn."""
        radius = self.sprite.roam_radius

        # Try random offsets until a valid point is found
        while True:
            offset_x = random.randint(-radius, radius)
            offset_y = random.randint(-radius, radius)

            candidate_x = self.sprite.spawn_x + offset_x
            candidate_y = self.sprite.spawn_y + offset_y

            # Must be within circle radius
            if self._distance(candidate_x, candidate_y,
                              self.sprite.spawn_x, self.sprite.spawn_y) <= radius:
                self.target_x = candidate_x
                self.target_y = candidate_y
                return

    # ------------------------------------------------------------
    # MOVE TOWARD TARGET BY 1 TILE
    # ------------------------------------------------------------

    def _move_toward_target(self):
        """Moves the monster 1 tile closer to target."""
        mx = self.sprite.monster.x
        my = self.sprite.monster.y

        dx = 0
        dy = 0

        # Determine direction (tile-based)
        if self.target_x > mx:
            dx = 1
        elif self.target_x < mx:
            dx = -1

        if self.target_y > my:
            dy = 1
        elif self.target_y < my:
            dy = -1

        # If monster is exactly on target tile → clear it
        if dx == 0 and dy == 0:
            self.target_x = None
            self.target_y = None
            return

        # Apply movement
        self.sprite.monster.x += dx
        self.sprite.monster.y += dy

        # Sync visual sprite
        self.sprite.update_position_from_monster()
