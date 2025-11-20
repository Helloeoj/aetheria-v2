# ============================================================
# AETHERIA UNIFIED COMBAT ENGINE (Tick-based, OSRS-style)
# ============================================================

from dataclasses import dataclass
import math
import uuid


# ------------------------------------------------------------
# DATA CLASSES
# ------------------------------------------------------------

@dataclass
class ProjectileEvent:
    projectile_id: str
    attacker_id: str
    target_id: str
    x: float
    y: float
    dx: float
    dy: float
    speed: float               # tiles per tick
    max_range: int             # tiles
    travelled: float = 0.0
    damage: int = 0
    accuracy: float = 0.0
    damage_type: str = "ranged"  # ranged or magic


@dataclass
class CombatActor:
    entity_id: str
    name: str
    x: int
    y: int
    hp: int
    max_hp: int
    attack_style: str              # slash/stab/blunt/magic/ranged
    min_damage: int
    max_damage: int
    accuracy: float
    crit_chance: float
    crit_multiplier: float
    resistances: dict
    attack_speed: int              # ticks per attack
    next_attack_tick: int = 0      # next allowed attack tick
    is_monster: bool = False
    monster_attack_type: str = None  # melee/ranged/magic/hybrid


# ------------------------------------------------------------
# UTILITY FUNCTIONS
# ------------------------------------------------------------

def distance(a, b):
    return math.sqrt((a.x - b.x)**2 + (a.y - b.y)**2)


def normalize(dx, dy):
    mag = math.sqrt(dx*dx + dy*dy)
    if mag == 0:
        return 0, 0
    return dx / mag, dy / mag


# ------------------------------------------------------------
# MAIN COMBAT ENGINE
# ------------------------------------------------------------

class CombatEngine:
    def __init__(self):
        self.actors = {}            # entity_id -> CombatActor
        self.projectiles = {}       # projectile_id -> ProjectileEvent
        self.current_tick = 0

    # --------------------------------------------------------
    # Register Players / Monsters into combat state
    # --------------------------------------------------------
    def add_actor(self, actor: CombatActor):
        self.actors[actor.entity_id] = actor

    def remove_actor(self, entity_id):
        if entity_id in self.actors:
            del self.actors[entity_id]

    # --------------------------------------------------------
    # Tick Processing (called every 0.6 seconds by Arcade)
    # --------------------------------------------------------
    def process_tick(self, world):
        """
        world contains:
            - player reference
            - monster list (with entity_ids)
            - map boundaries
        """

        events = []

        # 1) Move projectiles
        events.extend(self._process_projectiles())

        # 2) Monster AI logic
        events.extend(self._process_monster_ai(world))

        # 3) Actor attack resolution
        events.extend(self._process_attacks(world))

        self.current_tick += 1
        return events

    # --------------------------------------------------------
    # PROJECTILE HANDLING
    # --------------------------------------------------------
    def _process_projectiles(self):
        events = []
        to_delete = []

        for pid, proj in self.projectiles.items():
            # move projectile
            proj.x += proj.dx * proj.speed
            proj.y += proj.dy * proj.speed
            proj.travelled += proj.speed

            attacker = self.actors.get(proj.attacker_id)
            target = self.actors.get(proj.target_id)

            # Check hit
            if target and distance(proj, target) < 0.5:
                dmg, crit = self._roll_damage(attacker, target, proj.damage, proj.accuracy, proj.damage_type)
                target.hp -= dmg

                events.append({
                    "type": "projectile_hit",
                    "projectile_id": pid,
                    "target_id": target.entity_id,
                    "damage": dmg,
                    "crit": crit
                })

                if target.hp <= 0:
                    events.append({
                        "type": "entity_died",
                        "entity_id": target.entity_id,
                        "name": target.name
                    })

                to_delete.append(pid)
                continue

            # Range exceeded
            if proj.travelled >= proj.max_range:
                to_delete.append(pid)
                continue

            # Emit movement event
            events.append({
                "type": "projectile_moved",
                "projectile_id": pid,
                "x": proj.x,
                "y": proj.y
            })

        # Remove finished projectiles
        for pid in to_delete:
            del self.projectiles[pid]

        return events

    # --------------------------------------------------------
    # MONSTER AI (movement + attack decisions)
    # --------------------------------------------------------
    def _process_monster_ai(self, world):
        events = []
        player_actor = self.actors.get(world.player.entity_id)

        for monster in world.monsters:
            m = self.actors.get(monster.entity_id)
            if not m:
                continue

            dist = distance(m, player_actor)

            # Hybrid = distance based selection
            if m.monster_attack_type == "hybrid":
                if dist <= 2:
                    m.attack_style = "slash"  # melee default
                else:
                    m.attack_style = "magic"  # ranged/magic default
            else:
                m.attack_style = m.monster_attack_type

            # Move toward the player if needed
            if m.attack_style in ["slash", "stab", "blunt"] and dist > 2:
                # move 1 tile toward player
                dx = player_actor.x - m.x
                dy = player_actor.y - m.y
                nx, ny = normalize(dx, dy)
                m.x += round(nx)
                m.y += round(ny)

                events.append({
                    "type": "monster_moved",
                    "entity_id": m.entity_id,
                    "x": m.x,
                    "y": m.y
                })

        return events

    # --------------------------------------------------------
    # ATTACK RESOLUTION
    # --------------------------------------------------------
    def _process_attacks(self, world):
        events = []
        player_actor = self.actors.get(world.player.entity_id)

        # Resolve attacks for all actors
        for actor in list(self.actors.values()):
            if self.current_tick < actor.next_attack_tick:
                continue

            # Determine target
            if actor.is_monster:
                target = player_actor
            else:
                if not world.player.current_target:
                    continue
                target = self.actors.get(world.player.current_target)

            if not target:
                continue

            dist = distance(actor, target)

            # Attack distance rules
            if actor.attack_style in ["slash", "stab", "blunt"]:
                if dist > 2:
                    continue
            else:
                if dist > 20:
                    continue

            # READY TO ATTACK
            actor.next_attack_tick = self.current_tick + actor.attack_speed

            # Ranged/magic = projectile
            if actor.attack_style in ["magic", "ranged"]:
                projectile = self._spawn_projectile(actor, target)
                events.append({
                    "type": "projectile_spawned",
                    "projectile_id": projectile.projectile_id
                })
                continue

            # Melee = instant hit
            dmg, crit = self._roll_damage(actor, target)
            target.hp -= dmg

            events.append({
                "type": "entity_hit",
                "attacker_id": actor.entity_id,
                "target_id": target.entity_id,
                "damage": dmg,
                "crit": crit
            })

            if target.hp <= 0:
                events.append({
                    "type": "entity_died",
                    "entity_id": target.entity_id,
                    "name": target.name
                })

        return events

    # --------------------------------------------------------
    # DAMAGE CALCULATION
    # --------------------------------------------------------
    def _roll_damage(self, attacker, target, forced_damage=None, forced_accuracy=None, dmg_type=None):
        import random

        accuracy = forced_accuracy if forced_accuracy is not None else attacker.accuracy
        damage_type = dmg_type if dmg_type else attacker.attack_style

        # Resistances reduce accuracy multiplicatively
        resist = target.resistances.get(damage_type, 0)
        effective_acc = max(0.05, accuracy - resist)

        # Hit or miss
        if random.random() > effective_acc:
            return 0, False

        # Damage roll
        base = forced_damage if forced_damage is not None else random.randint(attacker.min_damage, attacker.max_damage)

        # Crit?
        crit = (random.random() < attacker.crit_chance)
        if crit:
            base = int(base * attacker.crit_multiplier)

        return base, crit

    # --------------------------------------------------------
    # PROJECTILE SPAWN
    # --------------------------------------------------------
    def _spawn_projectile(self, attacker, target):
        dx = target.x - attacker.x
        dy = target.y - attacker.y
        nx, ny = normalize(dx, dy)

        speed = 2.0 if attacker.attack_style == "magic" else 2.2

        proj = ProjectileEvent(
            projectile_id=str(uuid.uuid4()),
            attacker_id=attacker.entity_id,
            target_id=target.entity_id,
            x=attacker.x,
            y=attacker.y,
            dx=nx,
            dy=ny,
            speed=speed,
            max_range=20,
            damage=(attacker.min_damage + attacker.max_damage) // 2,
            accuracy=attacker.accuracy,
            damage_type=attacker.attack_style
        )

        self.projectiles[proj.projectile_id] = proj
        return proj

    # --------------------------------------------------------
    # CLI COMPATIBILITY (simple wrapper)
    # --------------------------------------------------------
    def fight_turn(self, attacker_id, defender_id):
        """
        Used ONLY for the CLI testing tool.
        Performs one instant-hit resolution.
        """
        attacker = self.actors.get(attacker_id)
        defender = self.actors.get(defender_id)

        dmg, crit = self._roll_damage(attacker, defender)
        defender.hp -= dmg

        return dmg, crit, (defender.hp <= 0)
