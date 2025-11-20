import arcade
import time
import uuid
import sys
import os
import math

# Make sure Python can see the parent folder (which contains aetheria_core)
CURRENT_DIR = os.path.dirname(__file__)
PARENT_DIR = os.path.dirname(CURRENT_DIR)
if PARENT_DIR not in sys.path:
    sys.path.insert(0, PARENT_DIR)

from aetheria_core.player import Player
from aetheria_core.items import ITEMS
from aetheria_core.monsters import (
    MONSTER_DATABASE,
    get_monster_by_id,
    get_monster_id_by_name,
    create_monster_instance,
)
from aetheria_core.combat_engine import CombatEngine, CombatActor
from ui_spawn_menu import SpawnMenu
from ui_item_menu import ItemMenu


# ============================================================
# CONSTANTS
# ============================================================
SCREEN_WIDTH = 1280
SCREEN_HEIGHT = 720
TILE_SIZE = 32

TICK_DURATION = 0.6  # 1 OSRS tick = 0.6 seconds

PLAYER_COLOR = arcade.color.BLUE
MONSTER_COLOR = arcade.color.DARK_SPRING_GREEN
MONSTER_TARGETED_COLOR = arcade.color.RED
PROJECTILE_COLOR = arcade.color.YELLOW

MELEE_STYLES = ("slash", "stab", "blunt")
MELEE_RANGE_TILES = 2.0
RANGED_MAGIC_RANGE_TILES = 20.0


# ============================================================
# SPRITE CLASSES
# ============================================================
class ActorSprite(arcade.SpriteSolidColor):
    """Square for player + monsters"""

    def __init__(self, width, height, color, entity_id):
        super().__init__(width, height, color)
        self.entity_id = entity_id


class ProjectileSprite(arcade.SpriteSolidColor):
    """Small moving projectile block"""

    def __init__(self, projectile_id):
        super().__init__(6, 6, PROJECTILE_COLOR)
        self.projectile_id = projectile_id


# ============================================================
# WORLD STATE STRUCTURE
# ============================================================
class WorldState:
    def __init__(self, player_obj):
        self.player = player_obj

        # Ensure these exist for the combat engine
        if not hasattr(self.player, "current_target"):
            self.player.current_target = None
        if not hasattr(self.player, "in_combat"):
            self.player.in_combat = False

        self.monsters = []
        # Kept for backwards compatibility; some old code might still use this.
        self.current_target = None


# ============================================================
# MAIN GAME WINDOW
# ============================================================
class AetheriaWindow(arcade.Window):
    def __init__(self):
        super().__init__(
            SCREEN_WIDTH,
            SCREEN_HEIGHT,
            "Aetheria (Arcade Tick Combat Prototype)",
        )
        arcade.set_background_color(arcade.color.BLACK)

        # ================================
        # Player + Combat Engine
        # ================================
        self.player = Player("Tester")
        self.player.entity_id = "player"
        if not hasattr(self.player, "current_target"):
            self.player.current_target = None
        if not hasattr(self.player, "in_combat"):
            self.player.in_combat = False

        self.world = WorldState(self.player)
        self.combat = CombatEngine()

        stats = self.player.get_combat_stats()

        player_actor = CombatActor(
            entity_id="player",
            name=self.player.name,
            x=10,
            y=10,
            hp=stats["health"]["current"],
            max_hp=stats["health"]["max"],
            attack_style=stats["style"],
            min_damage=stats["min_damage"],
            max_damage=stats["max_damage"],
            accuracy=stats["accuracy"],
            crit_chance=stats["crit_chance"],
            crit_multiplier=stats["crit_multiplier"],
            resistances=stats["resistances"],
            attack_speed=stats["attack_speed"],
            is_monster=False,
        )
        self.combat.add_actor(player_actor)

        # ================================
        # Sprite lists
        # ================================
        self.player_sprites = arcade.SpriteList()
        self.monster_sprites = arcade.SpriteList()
        self.projectile_sprites = arcade.SpriteList()

        # Player sprite
        self.player.sprite = ActorSprite(
            TILE_SIZE, TILE_SIZE, PLAYER_COLOR, "player"
        )
        self.player.sprite.center_x = 10 * TILE_SIZE
        self.player.sprite.center_y = 10 * TILE_SIZE
        self.player_sprites.append(self.player.sprite)

        # ================================
        # Movement + tick timer
        # ================================
        self.held_keys = set()
        self.last_tick_time = time.time()

        # ================================
        # Targeting system
        # ================================
        self.target_list = []        # list of monster entity_ids (alive)
        self.target_index = -1       # index into target_list
        self.auto_chase_target = False  # melee auto-run flag

        # ================================
        # DEV SPAWN MENU (F5)
        # ================================
        self.spawn_menu = SpawnMenu(self, MONSTER_DATABASE)

        # ================================
        # DEV ITEM MENU (F6)
        # ================================
        self.item_menu = ItemMenu(self, ITEMS)

    # ============================================================
    # MONSTER TARGETING HELPERS
    # ============================================================
    def _register_monster_for_targeting(self, monster_obj):
        """Add new monster to target list."""
        if getattr(monster_obj, "entity_id", None) and monster_obj.entity_id not in self.target_list:
            self.target_list.append(monster_obj.entity_id)

    def _unregister_monster_for_targeting(self, entity_id):
        """Remove monster from target list and clear target if needed."""
        if entity_id in self.target_list:
            self.target_list.remove(entity_id)

        if self.player.current_target == entity_id:
            self._clear_target()

    def _update_target_highlight(self):
        """Color targeted monster red, others default green."""
        for sprite in self.monster_sprites:
            if sprite.entity_id == self.player.current_target:
                sprite.color = MONSTER_TARGETED_COLOR
            else:
                sprite.color = MONSTER_COLOR

    def _set_target(self, entity_id):
        """Set current target by entity_id."""
        if entity_id is None:
            self._clear_target()
            return

        if entity_id not in self.combat.actors:
            self._clear_target()
            return

        self.player.current_target = entity_id
        self.world.current_target = entity_id  # for any old code
        self._update_target_highlight()

        actor = self.combat.actors[entity_id]
        print(f"▶ Targeting: {actor.name} ({entity_id})")

    def _cycle_target(self):
        """Cycle to the next monster in target_list."""
        if not self.target_list:
            print("[Target] No monsters to target.")
            return

        # If current target is in list, advance; otherwise start at 0
        if self.player.current_target in self.target_list:
            idx = self.target_list.index(self.player.current_target)
            idx = (idx + 1) % len(self.target_list)
        else:
            idx = 0

        self.target_index = idx
        self._set_target(self.target_list[idx])

    def _clear_target(self):
        """Clear target and remove highlight."""
        self.player.current_target = None
        self.world.current_target = None
        self.target_index = -1
        self.auto_chase_target = False
        self._update_target_highlight()
        print("◼ Target cleared.")

    # ============================================================
    # SPAWN MONSTER BY ID
    # ============================================================
    def spawn_monster_by_id(self, monster_id, offset=10):
        base = MONSTER_DATABASE.get(monster_id)
        if not base:
            print(f"[SpawnError] Monster ID {monster_id} not found.")
            return

        px = self.combat.actors["player"].x
        py = self.combat.actors["player"].y
        mx = px + offset
        my = py

        # Create real monster instance with stats
        monster_obj = create_monster_instance(monster_id, mx, my)
        monster_obj.entity_id = str(uuid.uuid4())

        stats = monster_obj.get_combat_stats()

        actor = CombatActor(
            entity_id=monster_obj.entity_id,
            name=monster_obj.name,
            x=mx,
            y=my,
            hp=stats["health"]["current"],
            max_hp=stats["health"]["max"],
            attack_style=stats["style"],
            min_damage=stats["min_damage"],
            max_damage=stats["max_damage"],
            accuracy=stats["accuracy"],
            crit_chance=stats["crit_chance"],
            crit_multiplier=stats["crit_multiplier"],
            resistances=stats["resistances"],
            attack_speed=stats["attack_speed"],
            is_monster=True,
        )

        self.combat.add_actor(actor)
        self.world.monsters.append(monster_obj)
        self._register_monster_for_targeting(monster_obj)

        sprite = ActorSprite(
            TILE_SIZE, TILE_SIZE, MONSTER_COLOR, monster_obj.entity_id
        )
        sprite.center_x = mx * TILE_SIZE
        sprite.center_y = my * TILE_SIZE
        self.monster_sprites.append(sprite)

        print(f"> Spawned {monster_obj.name} (ID {monster_id})")

    # ============================================================
    # UPDATE LOOP (TICKS)
    # ============================================================
    def on_update(self, delta_time):
        self._move_player(delta_time)

        now = time.time()
        if now - self.last_tick_time >= TICK_DURATION:
            self.last_tick_time = now
            events = self.combat.process_tick(self.world)
            self._handle_events(events)

    # ============================================================
    # EVENT HANDLING (tick outputs)
    # ============================================================
    def _handle_events(self, events):
        for event in events:
            if event["type"] == "monster_moved":
                ent = event["entity_id"]
                actor = self.combat.actors.get(ent)
                if actor:
                    for sprite in self.monster_sprites:
                        if sprite.entity_id == ent:
                            sprite.center_x = actor.x * TILE_SIZE
                            sprite.center_y = actor.y * TILE_SIZE

            elif event["type"] == "projectile_spawned":
                proj = self.combat.projectiles[event["projectile_id"]]
                sprite = ProjectileSprite(event["projectile_id"])
                sprite.center_x = proj.x * TILE_SIZE
                sprite.center_y = proj.y * TILE_SIZE
                self.projectile_sprites.append(sprite)

            elif event["type"] == "projectile_moved":
                pid = event["projectile_id"]
                proj = self.combat.projectiles.get(pid)
                if proj:
                    for sprite in self.projectile_sprites:
                        if sprite.projectile_id == pid:
                            sprite.center_x = proj.x * TILE_SIZE
                            sprite.center_y = proj.y * TILE_SIZE

            elif event["type"] == "projectile_hit":
                pid = event["projectile_id"]
                for sprite in list(self.projectile_sprites):
                    if sprite.projectile_id == pid:
                        sprite.remove_from_sprite_lists()

            elif event["type"] == "entity_died":
                ent = event["entity_id"]
                print(f"⚰ {event['name']} died")

                # Remove monster sprites
                for sprite in list(self.monster_sprites):
                    if sprite.entity_id == ent:
                        sprite.remove_from_sprite_lists()

                self.combat.remove_actor(ent)
                self.world.monsters = [
                    m for m in self.world.monsters if m.entity_id != ent
                ]
                self._unregister_monster_for_targeting(ent)

    # ============================================================
    # REFRESH PLAYER ACTOR STATS FROM PLAYER (DEV HELPER)
    # ============================================================
    def _refresh_player_actor_from_player(self):
        """Re-pull combat stats from Player into the CombatActor."""
        # Make sure the player actor exists
        if "player" not in self.combat.actors:
            return

        stats = self.player.get_combat_stats()
        actor = self.combat.actors["player"]

        # Keep HP ratio the same when max HP changes
        ratio = actor.hp / actor.max_hp if actor.max_hp > 0 else 1.0

        actor.max_hp = stats["health"]["max"]
        actor.hp = int(actor.max_hp * ratio)

        actor.attack_style = stats["style"]
        actor.min_damage = stats["min_damage"]
        actor.max_damage = stats["max_damage"]
        actor.accuracy = stats["accuracy"]
        actor.crit_chance = stats["crit_chance"]
        actor.crit_multiplier = stats["crit_multiplier"]
        actor.resistances = stats["resistances"]
        actor.attack_speed = stats["attack_speed"]

    # ============================================================
    # PLAYER MOVEMENT (manual + auto-chase for melee)
    # ============================================================
    def _move_player(self, dt):
        actor = self.combat.actors.get("player")
        if actor is None:
            # Player died / actor removed; nothing to move
            return

        # ----- AUTO-CHASE (melee follow) -----
        if self.auto_chase_target and self.player.current_target:
            target_actor = self.combat.actors.get(self.player.current_target)
            if not target_actor:
                self.auto_chase_target = False
            else:
                dx = 0
                dy = 0
                if target_actor.x > actor.x:
                    dx = 1
                elif target_actor.x < actor.x:
                    dx = -1
                if target_actor.y > actor.y:
                    dy = 1
                elif target_actor.y < actor.y:
                    dy = -1

                dist = math.hypot(
                    target_actor.x - actor.x, target_actor.y - actor.y
                )

                if dist <= MELEE_RANGE_TILES:
                    # in range → stop chasing; attack ASAP
                    self.auto_chase_target = False
                    actor.next_attack_tick = 0
                else:
                    actor.x += dx
                    actor.y += dy
                    self.player.sprite.center_x = actor.x * TILE_SIZE
                    self.player.sprite.center_y = actor.y * TILE_SIZE
            return

        # ----- NORMAL MANUAL MOVEMENT -----
        speed = 8 * dt
        dx = dy = 0

        if arcade.key.W in self.held_keys:
            dy += speed
        if arcade.key.S in self.held_keys:
            dy -= speed
        if arcade.key.A in self.held_keys:
            dx -= speed
        if arcade.key.D in self.held_keys:
            dx += speed

        if dx or dy:
            actor.x += 1 if dx > 0 else -1 if dx < 0 else 0
            actor.y += 1 if dy > 0 else -1 if dy < 0 else 0

            self.player.sprite.center_x = actor.x * TILE_SIZE
            self.player.sprite.center_y = actor.y * TILE_SIZE

    # ============================================================
    # INPUT
    # ============================================================
    def on_key_press(self, key, modifiers):
        # Track keys for movement
        self.held_keys.add(key)

        # If any dev menu is visible, let it handle keys first
        if getattr(self, "spawn_menu", None) and self.spawn_menu.visible:
            handled = self.spawn_menu.on_key_press(key, modifiers)
            if handled:
                return  # Don't process the key twice

        if getattr(self, "item_menu", None) and self.item_menu.visible:
            handled = self.item_menu.on_key_press(key, modifiers)
            if handled:
                return

        # F5 → toggle the dev spawn menu (monsters)
        if key == arcade.key.F5:
            if getattr(self, "spawn_menu", None):
                self.spawn_menu.toggle()
            return

        # F6 → toggle the dev item menu (items)
        if key == arcade.key.F6:
            if getattr(self, "item_menu", None):
                self.item_menu.toggle()
            return

        # T → cycle target
        if key == arcade.key.T:
            self._cycle_target()
            return

        # U → clear target
        if key == arcade.key.U:
            self._clear_target()
            return

        # SPACE → attack / start melee auto-chase
        if key == arcade.key.SPACE:
            actor = self.combat.actors.get("player")
            if actor is None:
                return

            target_id = getattr(self.player, "current_target", None)
            target_actor = (
                self.combat.actors.get(target_id) if target_id else None
            )

            if not target_actor:
                print("[Attack] No target selected.")
                return

            style = getattr(actor, "attack_style", "slash")
            dist = math.hypot(
                target_actor.x - actor.x, target_actor.y - actor.y
            )

            if style in MELEE_STYLES:
                if dist > MELEE_RANGE_TILES:
                    # too far → start auto-chase
                    print(
                        f"[Melee] Out of range ({dist:.1f} tiles). Chasing target..."
                    )
                    self.auto_chase_target = True
                else:
                    actor.next_attack_tick = 0
            else:
                if dist > RANGED_MAGIC_RANGE_TILES:
                    print(
                        f"[Ranged/Magic] Target out of range ({dist:.1f} tiles)."
                    )
                else:
                    actor.next_attack_tick = 0

            return

        # Optional: quick test keys that spawn default monsters
        # when BOTH menus are closed
        if not (
            (getattr(self, "spawn_menu", None) and self.spawn_menu.visible)
            or (getattr(self, "item_menu", None) and self.item_menu.visible)
        ):
            if key == arcade.key.KEY_1:
                self.spawn_monster_by_id(2)   # Goblin Scout
            elif key == arcade.key.KEY_2:
                self.spawn_monster_by_id(42)  # Goblin Ranger
            elif key == arcade.key.KEY_3:
                self.spawn_monster_by_id(56)  # Goblin Mage

    def on_key_release(self, key, modifiers):
        if key in self.held_keys:
            self.held_keys.discard(key)

    # ============================================================
    # DRAW — Arcade 3.3.3 uses clear() not start_render()
    # ============================================================
    def _draw_health_bars(self):
        """
        Draw health bars above the player and all monsters.
        Uses self.combat.actors for HP / max HP and the sprites for position.
        """
        if not hasattr(self, "combat"):
            return

        for actor in self.combat.actors.values():
            # Find the matching sprite for this actor
            if actor.entity_id == "player":
                sprite = getattr(self.player, "sprite", None)
            else:
                sprite = None
                for s in self.monster_sprites:
                    if getattr(s, "entity_id", None) == actor.entity_id:
                        sprite = s
                        break

            if sprite is None:
                continue

            # HP ratio (clamped)
            hp = max(actor.hp, 0)
            max_hp = max(actor.max_hp, 1)
            ratio = hp / max_hp

            # Bar dimensions
            bar_width = TILE_SIZE
            bar_height = 6
            cx = sprite.center_x
            # Slightly above the sprite
            cy = sprite.center_y + sprite.height // 2 + 8

            half_w = bar_width / 2
            half_h = bar_height / 2
            left = cx - half_w
            right = cx + half_w
            bottom = cy - half_h
            top = cy + half_h

            # Background (red) – full width
            arcade.draw_lrbt_rectangle_filled(
                left,
                right,
                bottom,
                top,
                arcade.color.DARK_RED,
            )

            # Foreground (green) – scaled by HP ratio
            if ratio > 0:
                green_width = bar_width * ratio
                green_right = left + green_width
                arcade.draw_lrbt_rectangle_filled(
                    left,
                    green_right,
                    bottom,
                    top,
                    arcade.color.GREEN,
                )


    def on_draw(self):
        self.clear()

        # Draw grid
        for x in range(0, SCREEN_WIDTH, TILE_SIZE):
            arcade.draw_line(x, 0, x, SCREEN_HEIGHT, arcade.color.DARK_GRAY, 1)
        for y in range(0, SCREEN_HEIGHT, TILE_SIZE):
            arcade.draw_line(0, y, SCREEN_WIDTH, y, arcade.color.DARK_GRAY, 1)

        # Draw all sprite groups
        self.player_sprites.draw()
        self.monster_sprites.draw()
        self.projectile_sprites.draw()

        # Draw HP bars above player + monsters
        self._draw_health_bars()

        # ================================
        # DEV SPAWN MENU OVERLAY
        # ================================
        if getattr(self, "spawn_menu", None):
            self.spawn_menu.draw()

        # ================================
        # DEV ITEM MENU OVERLAY
        # ================================
        if getattr(self, "item_menu", None):
            self.item_menu.draw()


def main():
    AetheriaWindow()
    arcade.run()


if __name__ == "__main__":
    main()
