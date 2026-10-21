import arcade
from math import sqrt


TILE_SIZE = 32


class ProjectileSprite:
    """
    Handles:
    - On-screen projectile representation
    - Movement per tick
    - Hit detection
    - Removal when finished
    """

    def __init__(self, projectile_obj, projectile_emoji="➤"):
        """
        projectile_obj = instance created from combat_engine.create_projectile()
        """
        self.p = projectile_obj  # logic object from combat engine
        self.emoji = projectile_emoji

        # start screen position matches logic position
        self.x = self.p.start_x
        self.y = self.p.start_y

        # projectiles update every tick in main.py
        self.marked_for_removal = False

    # ----------------------------------------------------
    # POSITION UTILS
    # ----------------------------------------------------

    def _distance(self, x1, y1, x2, y2):
        return sqrt((x1 - x2)**2 + (y1 - y2)**2)

    # ----------------------------------------------------
    # UPDATE LOGIC PER TICK
    # ----------------------------------------------------

    def update(self, active_monsters):
        """
        Moves projectile toward target based on speed.
        Removes projectile if:
         - it hits a monster
         - exceeds max range
         - target dies early
        """
        if self.marked_for_removal:
            return

        # Move projectile by speed_tiles_per_tick
        dx = self.p.dir_x * self.p.speed_tiles_per_tick
        dy = self.p.dir_y * self.p.speed_tiles_per_tick

        self.p.current_x += dx
        self.p.current_y += dy

        # Update screen position
        self.x = self.p.current_x
        self.y = self.p.current_y

        # Check distance from start (max range)
        travelled = self._distance(
            self.p.current_x, self.p.current_y,
            self.p.start_x, self.p.start_y
        )

        if travelled >= self.p.max_range:
            self.marked_for_removal = True
            return

        # If target is dead, projectile expires
        if self.p.target.current_hp <= 0:
            self.marked_for_removal = True
            return

        # Check for hit: if projectile reaches same tile as monster
        tx = self.p.target.x
        ty = self.p.target.y

        # Distance less than half a tile means HIT
        if self._distance(self.p.current_x, self.p.current_y, tx, ty) < 0.5:
            # Deal damage using combat engine
            dmg = self.p.resolve_hit()
            self.p.target.current_hp -= dmg
            self.marked_for_removal = True

    # ----------------------------------------------------
    # DRAW
    # ----------------------------------------------------

    def draw(self):
        """Draw projectile emoji at current world position."""
        screen_x = self.x * TILE_SIZE
        screen_y = self.y * TILE_SIZE

        arcade.draw_text(
            self.emoji,
            screen_x,
            screen_y,
            arcade.color.WHITE,
            font_size=22,
            anchor_x="center",
            anchor_y="center",
        )
