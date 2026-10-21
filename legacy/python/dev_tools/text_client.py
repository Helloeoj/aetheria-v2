"""
Text-mode driver for the extracted aetheria_core package.

Runs a single, deterministic combat exchange between the starter
player and a Goblin Scout so we can sanity-check the combat engine
without any networking or GUI.
"""
from __future__ import annotations

import pathlib
import random
import sys
import uuid
from typing import Dict

ROOT = pathlib.Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from aetheria_core.combat_engine import CombatActor, CombatEngine
from aetheria_core.monsters import create_monster_instance, get_monster_id_by_name
from aetheria_core.player import Player


# --------------------------------------------------------------
# HELPERS
# --------------------------------------------------------------
def as_actor(name: str, stats: Dict, *, entity_id: str, x: int, y: int, is_monster: bool = False, monster_attack_type: str | None = None) -> CombatActor:
    """Convert combat stats into a CombatActor for the engine."""
    return CombatActor(
        entity_id=entity_id,
        name=name,
        x=x,
        y=y,
        hp=int(stats["health"]["current"]),
        max_hp=int(stats["health"]["max"]),
        attack_style=stats.get("style", "slash"),
        min_damage=int(stats.get("min_damage", 1)),
        max_damage=int(stats.get("max_damage", 1)),
        accuracy=float(stats.get("accuracy", 0.1)),
        crit_chance=float(stats.get("crit_chance", 0.05)),
        crit_multiplier=float(stats.get("crit_multiplier", 1.5)),
        resistances=dict(stats.get("resistances", {})),
        attack_speed=int(stats.get("attack_speed", 4)),
        is_monster=is_monster,
        monster_attack_type=monster_attack_type,
    )


def print_header(title: str) -> None:
    print("=" * 60)
    print(title)
    print("=" * 60)


# --------------------------------------------------------------
# MAIN DEMO
# --------------------------------------------------------------
def run_demo() -> None:
    random.seed(1)

    player = Player("CLI Tester")
    player.set_level("attack", 25)
    player.set_level("strength", 25)
    player.entity_id = f"player-{uuid.uuid4()}"

    goblin_id = get_monster_id_by_name("Goblin Scout")
    if goblin_id is None:
        raise RuntimeError("Goblin Scout not found in MONSTER_DATABASE")

    monster = create_monster_instance(goblin_id, x=player.x + 1, y=player.y)
    monster.entity_id = f"monster-{uuid.uuid4()}"

    engine = CombatEngine()

    player_stats = player.get_combat_stats()
    monster_stats = monster.get_combat_stats()

    player_actor = as_actor(
        player.name,
        player_stats,
        entity_id=player.entity_id,
        x=player.x,
        y=player.y,
    )
    monster_actor = as_actor(
        monster.name,
        monster_stats,
        entity_id=monster.entity_id,
        x=monster.x,
        y=monster.y,
        is_monster=True,
        monster_attack_type=monster.damage_type,
    )

    engine.add_actor(player_actor)
    engine.add_actor(monster_actor)

    print_header("Aetheria Core — Text Combat Client")
    print("Player:", player.summary())
    print("Monster:", monster.summary())
    print()

    # Player attacks first
    dmg, crit, killed = engine.fight_turn(player_actor.entity_id, monster_actor.entity_id)
    print_header("Player Turn")
    print(f"{player_actor.name} hits {monster_actor.name} for {dmg} damage{ ' (CRIT)' if crit else ''}.")

    if killed:
        print(f"{monster_actor.name} is defeated!")
    else:
        # Monster retaliates
        retaliation = engine.fight_turn(monster_actor.entity_id, player_actor.entity_id)
        m_dmg, m_crit, m_killed = retaliation
        print_header("Monster Turn")
        print(f"{monster_actor.name} hits back for {m_dmg} damage{ ' (CRIT)' if m_crit else ''}.")
        if m_killed:
            print(f"{player_actor.name} falls in battle.")

    print_header("Post-combat HP")
    print(f"{player_actor.name}: {player_actor.hp}/{player_actor.max_hp}")
    print(f"{monster_actor.name}: {monster_actor.hp}/{monster_actor.max_hp}")


if __name__ == "__main__":
    run_demo()
