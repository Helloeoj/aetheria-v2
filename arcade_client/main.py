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
from ui_inventory_menu import InventoryMenu

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
    def __init__(self, width, height, color, entity_id):
        super().__init__(width, height, color)
        self.entity_id = entity_id  # Unique ID from combat actor


# ============================================================
# MAIN WINDOW
# ============================================================
class AetheriaWindow(arcade.Window):
    def __init__(self):
        super().__init__(SCREEN_WIDTH, SCREEN_HEIGHT, "Aetheria (Arcade Test Client)")

        # ======================================
        # Combat Engine
        # ======================================
        self.combat = CombatEngine()

        # ======================================
        # Player Initialization
        # ======================================
        self.player = Player(name="Player")
        self.player.entity_id = "player"

        sprite = ActorSprite(TILE_SIZE, TILE_SIZE, PLAYER_COLOR, self.player.entity_id)
        sprite.center_x = 10 * TILE_SIZE
        sprite.center_y = 10 * TILE_SIZE
        self.player.sprite = sprite

        # Add player to combat engine
        player_stats = self.player.get_combat_stats()
        self.combat.register_actor(
            self._create_actor_from_stats(
                entity_id="player",
                name=self.player.name,
                x=self.player.x,
                y=self.player.y,
                stats=player_stats,
                is_monster=False,
                monster_attack_type=None,
            )
        )

        # ======================================
        # Sprite Lists
        # ======================================
        self.player_sprites = arcade.SpriteList()
        self.monster_sprites = arcade.SpriteList()
        self.projectile_sprites = arcade.SpriteList()

        # World state for the combat engine
        self.monsters = []

        self.player_sprites.append(self.player.sprite)

        # ======================================
        # Movement + Tick System
        # ======================================
        self.held_keys = set()
        self.last_tick_time = time.time()

        # ======================================
        # Targeting System
        # ======================================
        self.target_list = []        # list of monster entity_ids
        self.target_index = -1       # index into target_list
        self.auto_chase_target = False

        # ======================================
        # Dev Menus
        # ======================================
        self.spawn_menu = SpawnMenu(self, MONSTER_DATABASE)  # F5
        self.item_menu = ItemMenu(self, ITEMS)               # F6
        self.inventory_menu = InventoryMenu(self)            # I

    def _create_actor_from_stats(
        self,
        entity_id: str,
        name: str,
        x: int,
        y: int,
        stats: dict,
        is_monster: bool,
        monster_attack_type: str | None,
    ) -> CombatActor:
        health = stats.get("health", {})
        return CombatActor(
            entity_id=entity_id,
            name=name,
            x=x,
            y=y,
            hp=int(health.get("current", 1)),
            max_hp=int(health.get("max", 1)),
            attack_style=stats.get("style", "slash"),
            min_damage=int(stats.get("min_damage", 1)),
            max_damage=int(stats.get("max_damage", 1)),
            accuracy=float(stats.get("accuracy", 0.1)),
            crit_chance=float(stats.get("crit_chance", 0.05)),
            crit_multiplier=float(
                stats.get("crit_multiplier", 1.5)
            ),
            resistances=stats.get("resistances", {}) or {},
            attack_speed=int(stats.get("attack_speed", 5)),
            is_monster=is_monster,
            monster_attack_type=monster_attack_type,
        )

    def _refresh_player_actor_from_player(self):
        actor = self.combat.actors.get("player")
        if not actor:
            return

        stats = self.player.get_combat_stats()
        health = stats.get("health", {})

        actor.name = self.player.name
        actor.hp = int(health.get("current", actor.hp))
        actor.max_hp = int(health.get("max", actor.max_hp))
        actor.attack_style = stats.get("style", actor.attack_style)
        actor.min_damage = int(stats.get("min_damage", actor.min_damage))
        actor.max_damage = int(stats.get("max_damage", actor.max_damage))
        actor.accuracy = float(stats.get("accuracy", actor.accuracy))
        actor.crit_chance = float(stats.get("crit_chance", actor.crit_chance))
        actor.crit_multiplier = float(
            stats.get("crit_multiplier", actor.crit_multiplier)
        )
        actor.resistances = stats.get("resistances", actor.resistances) or {}
        actor.attack_speed = int(stats.get("attack_speed", actor.attack_speed))

    # ============================================================
    # MONSTER TARGETING HELPERS
    # ============================================================
    def _register_monster_for_targeting(self, monster_obj):
        if getattr(monster_obj, "entity_id", None) and monster_obj.entity_id not in self.target_list:
            self.target_list.append(monster_obj.entity_id)

    def _unregister_monster_for_targeting(self, entity_id):
        if entity_id in self.target_list:
            self.target_list.remove(entity_id)

        if self.player.current_target == entity_id:
            self._clear_target()

    def _update_target_highlight(self):
        for sprite in self.monster_sprites:
            if sprite.entity_id == self.player.current_target:
                sprite.color = MONSTER_TARGETED_COLOR
            else:
                sprite.color = MONSTER_COLOR

    def _set_target(self, entity_id):
        self.player.current_target = entity_id
        self._update_target_highlight()

    def _clear_target(self):
        self.player.current_target = None
        self._update_target_highlight()

    def _cycle_target(self):
        if not self.target_list:
            return

        self.target_index = (self.target_index + 1) % len(self.target_list)
        self._set_target(self.target_list[self.target_index])

    # ============================================================
    # SPAWNING
    # ============================================================
    def spawn_monster_by_id(self, monster_id):
        monster_data = get_monster_by_id(monster_id)
        if monster_data is None:
            print(f"[Error] No monster with ID {monster_id}")
            return

        x, y = 15, 15

        monster = create_monster_instance(monster_id, x, y)
        monster.entity_id = str(uuid.uuid4())
        entity_id = monster.entity_id

        self.monsters.append(monster)

        sprite = ActorSprite(TILE_SIZE, TILE_SIZE, MONSTER_COLOR, entity_id)
        sprite.center_x = x * TILE_SIZE
        sprite.center_y = y * TILE_SIZE

        self.monster_sprites.append(sprite)

        self.combat.register_actor(
            self._create_actor_from_stats(
                entity_id=entity_id,
                name=monster.name,
                x=x,
                y=y,
                stats=monster.get_combat_stats(),
                is_monster=True,
                monster_attack_type=monster.damage_type,
            )
        )

        self._register_monster_for_targeting(monster)
        print(f"[Spawned] {monster.name} (ID {monster_id})")

    # ============================================================
    # MOVEMENT + TICK ENGINE
    # ============================================================
    def _do_tick(self):
        events = self.combat.process_tick(self)

        # Move all actors (including player)
        for actor in self.combat.actors.values():
            sprite = None
            if actor.entity_id == "player":
                sprite = self.player.sprite
            else:
                for s in self.monster_sprites:
                    if getattr(s, "entity_id", None) == actor.entity_id:
                        sprite = s
                        break

            if sprite:
                sprite.center_x = actor.x * TILE_SIZE
                sprite.center_y = actor.y * TILE_SIZE

        self._update_target_highlight()

    def _move_player(self):
        actor = self.combat.actors.get("player")
        if not actor:
            return

        dx = dy = 0
        if arcade.key.W in self.held_keys:
            dy += 1
        if arcade.key.S in self.held_keys:
            dy -= 1
        if arcade.key.A in self.held_keys:
            dx -= 1
        if arcade.key.D in self.held_keys:
            dx += 1

        if dx or dy:
            actor.x += 1 if dx > 0 else -1 if dx < 0 else 0
            actor.y += 1 if dy > 0 else -1 if dy < 0 else 0

            self.player.sprite.center_x = actor.x * TILE_SIZE
            self.player.sprite.center_y = actor.y * TILE_SIZE

    # ============================================================
    # INPUT
    # ============================================================
    def on_key_press(self, key, modifiers):
        self.held_keys.add(key)

        # Menus take priority
        if self.spawn_menu.visible:
            if self.spawn_menu.on_key_press(key, modifiers):
                return

        if self.item_menu.visible:
            if self.item_menu.on_key_press(key, modifiers):
                return

        if self.inventory_menu.visible:
            if self.inventory_menu.on_key_press(key, modifiers):
                return

        # Toggle menus
        if key == arcade.key.F5:
            self.spawn_menu.toggle()
            return

        if key == arcade.key.F6:
            self.item_menu.toggle()
            return

        if key == arcade.key.I:
            self.inventory_menu.toggle()
            return

        # Targeting
        if key == arcade.key.T:
            self._cycle_target()
            return

        if key == arcade.key.U:
            self._clear_target()
            return

        # Attack
        if key == arcade.key.SPACE:
            actor = self.combat.actors.get("player")
            if actor is None:
                return

            target_id = self.player.current_target
            target_actor = self.combat.actors.get(target_id) if target_id else None

            # No target -> queue auto-chase to closest monster
            if target_actor is None:
                closest = None
                closest_dist = 999
                for entity_id, a in self.combat.actors.items():
                    if not a.is_monster:
                        continue
                    dist = abs(a.x - actor.x) + abs(a.y - actor.y)
                    if dist < closest_dist:
                        closest_dist = dist
                        closest = a
                if closest:
                    self.player.current_target = closest.entity_id
                    self.auto_chase_target = True
                    print(f"[Auto] chasing {closest.name}")
                return

            # Auto-chase the current target
            self.auto_chase_target = True
            return

        # Spawn helpers
        if key == arcade.key.KEY_1:
            self.spawn_monster_by_id(2)
        elif key == arcade.key.KEY_2:
            self.spawn_monster_by_id(42)
        elif key == arcade.key.KEY_3:
            self.spawn_monster_by_id(56)

    def on_mouse_press(self, x, y, button, modifiers):
        if self.inventory_menu.visible:
            if self.inventory_menu.on_mouse_press(x, y, button, modifiers):
                return

    def on_key_release(self, key, modifiers):
        if key in self.held_keys:
            self.held_keys.discard(key)

    # ============================================================
    # DRAWING
    # ============================================================
    def _draw_health_bars(self):
        for actor in self.combat.actors.values():
            sprite = None
            if actor.entity_id == "player":
                sprite = self.player.sprite
            else:
                for s in self.monster_sprites:
                    if getattr(s, "entity_id", None) == actor.entity_id:
                        sprite = s
                        break

            if not sprite:
                continue

            hp_ratio = actor.hp / actor.max_hp if actor.max_hp > 0 else 0
            bar_width = TILE_SIZE
            bar_height = 5
            bar_x = sprite.center_x
            bar_y = sprite.center_y + TILE_SIZE / 2 + 6

            left = bar_x - bar_width / 2
            bottom = bar_y

            # Background bar (full health)
            arcade.draw_lbwh_rectangle_filled(
                left,
                bottom,
                bar_width,
                bar_height,
                arcade.color.RED,
            )

            # Foreground bar (current health)
            green_width = bar_width * hp_ratio
            arcade.draw_lbwh_rectangle_filled(
                left,
                bottom,
                green_width,
                bar_height,
                arcade.color.GREEN,
            )

    def on_draw(self):
        # Clear the window each frame (arcade.start_render is deprecated in window classes)
        self.clear()

        # Grid
        for x in range(0, SCREEN_WIDTH, TILE_SIZE):
            arcade.draw_line(x, 0, x, SCREEN_HEIGHT, arcade.color.DARK_GRAY, 1)
        for y in range(0, SCREEN_HEIGHT, TILE_SIZE):
            arcade.draw_line(0, y, SCREEN_WIDTH, y, arcade.color.DARK_GRAY, 1)

        # Sprites
        self.player_sprites.draw()
        self.monster_sprites.draw()
        self.projectile_sprites.draw()

        self._draw_health_bars()

        # Menus
        self.spawn_menu.draw()
        self.item_menu.draw()
        self.inventory_menu.draw()

    # ============================================================
    # UPDATE LOOP
    # ============================================================
    def on_update(self, delta_time):
        self._move_player()

        # Tick engine
        if time.time() - self.last_tick_time >= TICK_DURATION:
            self.last_tick_time = time.time()
            self._do_tick()

        # Auto-chase for melee
        if self.auto_chase_target:
            actor = self.combat.actors.get("player")
            target_id = self.player.current_target
            target_actor = self.combat.actors.get(target_id) if target_id else None

            if actor and target_actor:
                dx = target_actor.x - actor.x
                dy = target_actor.y - actor.y
                dist = math.hypot(dx, dy)

                if dist <= MELEE_RANGE_TILES:
                    self.auto_chase_target = False
                    actor.next_attack_tick = 0
                else:
                    actor.x += 1 if dx > 0 else -1 if dx < 0 else 0
                    actor.y += 1 if dy > 0 else -1 if dy < 0 else 0

                    self.player.sprite.center_x = actor.x * TILE_SIZE
                    self.player.sprite.center_y = actor.y * TILE_SIZE


def main():
    AetheriaWindow()
    arcade.run()


if __name__ == "__main__":
    main()
