"""Quick smoke test for the tick-based combat loop.

Run with:
    python dev_tools/run_smoke.py
"""

from dataclasses import dataclass

from aetheria_core.combat_engine import CombatActor, CombatEngine
from aetheria_core.player import Player


@dataclass
class World:
    player: Player
    monsters: list


def build_player_actor(player: Player) -> CombatActor:
    stats = player.get_combat_stats()
    return CombatActor(
        entity_id=player.entity_id,
        name=player.name,
        x=player.x,
        y=player.y,
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


def build_monster(name: str, entity_id: str, x: int, y: int) -> CombatActor:
    return CombatActor(
        entity_id=entity_id,
        name=name,
        x=x,
        y=y,
        hp=60,
        max_hp=60,
        attack_style="slash",
        min_damage=3,
        max_damage=7,
        accuracy=0.5,
        crit_chance=0.05,
        crit_multiplier=1.5,
        resistances={"slash": 0.1},
        attack_speed=5,
        is_monster=True,
        monster_attack_type="slash",
    )


def main():
    engine = CombatEngine()

    player = Player("SmokeTester")
    player.entity_id = "player-1"
    player.give_and_equip("Bronze Shortsword")

    player_actor = build_player_actor(player)
    monster_actor = build_monster("Training Dummy", "mob-1", x=12, y=10)

    engine.add_actor(player_actor)
    engine.add_actor(monster_actor)

    world = World(player=player, monsters=[monster_actor])
    player.current_target = monster_actor.entity_id

    print("Starting smoke loop...\n")
    for tick in range(10):
        events = engine.process_tick(world)
        print(f"Tick {tick}: {events}")
        if monster_actor.hp <= 0 or player_actor.hp <= 0:
            break

    print("\nSmoke test complete.")


if __name__ == "__main__":
    main()
