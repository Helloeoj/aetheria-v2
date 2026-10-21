import time
from combat_engine import (
    prepare_player_combat_stats,
    prepare_monster_combat_stats,
    fight_turn,
    create_projectile
)

TICK_INTERVAL = 0.60  # OSRS tick speed


class CombatTickSystem:
    def __init__(self, game_ref):
        """
        game_ref = Your main window instance.
        Must contain:
            - player
            - active_monsters
            - projectile_sprites
            - targeted_monster
        """
        self.game = game_ref
        self.last_tick = time.time()

        # Attack cooldowns
        self.player_next_attack_time = 0
        self.monster_next_attack = {}  # monster -> next attack timestamp

    # ---------------------------------------------------------
    # MAIN UPDATE LOOP (called every frame from main.py)
    # ---------------------------------------------------------

    def update(self):
        now = time.time()
        if now - self.last_tick < TICK_INTERVAL:
            return  # Not time for combat tick

        self.last_tick = now
        self._update_projectiles()
        self._update_player_combat()
        self._update_monster_combat()

    # ---------------------------------------------------------
    # PROJECTILE PROCESSING
    # ---------------------------------------------------------

    def _update_projectiles(self):
        """Move and resolve all active projectiles."""
        to_remove = []

        for proj in self.game.projectile_sprites:
            proj.update(self.game.active_monsters)
            if proj.marked_for_removal:
                to_remove.append(proj)

        for proj in to_remove:
            self.game.projectile_sprites.remove(proj)

    # ---------------------------------------------------------
    # PLAYER COMBAT LOGIC
    # ---------------------------------------------------------

    def _update_player_combat(self):
        player = self.game.player
        target = self.game.targeted_monster

        # No target? Nothing to do
        if not target:
            return

        # Target dead?
        if target.current_hp <= 0:
            target.in_combat = False
            player.in_combat = False
            self.game.targeted_monster = None
            return

        now = time.time()
        if now < self.player_next_attack_time:
            return  # Still on cooldown

        # Prepare player combat stats
        pstats = prepare_player_combat_stats(player)

        # Ranged or magic → spawn projectile
        if pstats.get("projectile_speed") > 0:
            proj = create_projectile(player, target, pstats)
            self.game.projectile_sprites.append(
                self.game.projectile_factory(proj)
            )
        else:
            # Melee → immediate hit
            damage = fight_turn(player, target, pstats)
            target.current_hp -= damage

        # Player enters combat
        player.in_combat = True
        target.in_combat = True

        # Set next attack time
        attack_speed_seconds = pstats["attack_speed"] * TICK_INTERVAL
        self.player_next_attack_time = now + attack_speed_seconds

    # ---------------------------------------------------------
    # MONSTER AI COMBAT LOGIC
    # ---------------------------------------------------------

    def _update_monster_combat(self):
        now = time.time()

        for msprite in self.game.active_monsters:
            m = msprite.monster

            if not m.in_combat:
                continue  # Passive unless provoked

            if m.current_hp <= 0:
                m.in_combat = False
                continue

            # Must have a target
            if m.target is None:
                m.in_combat = False
                continue

            # Attack cooldown
            next_atk = self.monster_next_attack.get(m, 0)
            if now < next_atk:
                continue

            # Prepare monster stats
            mstats = prepare_monster_combat_stats(m)

            # Monster ranged or magic?
            if mstats.get("projectile_speed") > 0:
                proj = create_projectile(m, m.target, mstats)
                self.game.projectile_sprites.append(
                    self.game.projectile_factory(proj)
                )
            else:
                # Melee monster attack → immediate hit
                dmg = fight_turn(m, m.target, mstats)
                m.target.current_hp -= dmg

            # Assign next monster attack time
            attack_speed_seconds = mstats["attack_speed"] * TICK_INTERVAL
            self.monster_next_attack[m] = now + attack_speed_seconds
