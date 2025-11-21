import math
from unittest import mock

import pytest

from aetheria_core.combat_engine import CombatActor, CombatEngine, normalize


@pytest.fixture
def engine():
    return CombatEngine()


def test_roll_damage_respects_resistance(engine):
    attacker = CombatActor(
        entity_id="atk",
        name="Attacker",
        x=0,
        y=0,
        hp=100,
        max_hp=100,
        attack_style="slash",
        min_damage=5,
        max_damage=10,
        accuracy=0.2,
        crit_chance=0.1,
        crit_multiplier=2.0,
        resistances={},
        attack_speed=4,
    )
    defender = CombatActor(
        entity_id="def",
        name="Defender",
        x=0,
        y=0,
        hp=100,
        max_hp=100,
        attack_style="slash",
        min_damage=1,
        max_damage=1,
        accuracy=0.0,
        crit_chance=0.0,
        crit_multiplier=1.0,
        resistances={"slash": 0.3},
        attack_speed=4,
    )

    # Force the random roll to be high so a low effective accuracy misses.
    with mock.patch("random.random", return_value=0.99):
        dmg, crit = engine._roll_damage(attacker, defender)

    assert dmg == 0
    assert crit is False


def test_roll_damage_applies_critical(engine):
    attacker = CombatActor(
        entity_id="atk",
        name="Attacker",
        x=0,
        y=0,
        hp=100,
        max_hp=100,
        attack_style="slash",
        min_damage=4,
        max_damage=4,
        accuracy=0.9,
        crit_chance=0.5,
        crit_multiplier=1.5,
        resistances={},
        attack_speed=4,
    )
    defender = CombatActor(
        entity_id="def",
        name="Defender",
        x=0,
        y=0,
        hp=100,
        max_hp=100,
        attack_style="slash",
        min_damage=1,
        max_damage=1,
        accuracy=0.0,
        crit_chance=0.0,
        crit_multiplier=1.0,
        resistances={},
        attack_speed=4,
    )

    # Two calls to random.random: hit check then crit check.
    roll_values = iter([0.0, 0.0])
    with mock.patch("random.random", side_effect=lambda: next(roll_values)):
        dmg, crit = engine._roll_damage(
            attacker,
            defender,
            forced_damage=4,
            forced_accuracy=1.0,
        )

    assert dmg == math.floor(4 * attacker.crit_multiplier)
    assert crit is True


def test_spawn_projectile_sets_direction(engine):
    attacker = CombatActor(
        entity_id="atk",
        name="Attacker",
        x=0,
        y=0,
        hp=100,
        max_hp=100,
        attack_style="magic",
        min_damage=2,
        max_damage=6,
        accuracy=0.7,
        crit_chance=0.05,
        crit_multiplier=1.5,
        resistances={},
        attack_speed=4,
    )
    target = CombatActor(
        entity_id="def",
        name="Defender",
        x=3,
        y=4,
        hp=100,
        max_hp=100,
        attack_style="slash",
        min_damage=1,
        max_damage=1,
        accuracy=0.0,
        crit_chance=0.0,
        crit_multiplier=1.0,
        resistances={},
        attack_speed=4,
    )

    projectile = engine._spawn_projectile(attacker, target)

    expected_dx, expected_dy = normalize(3, 4)
    assert projectile.dx == pytest.approx(expected_dx)
    assert projectile.dy == pytest.approx(expected_dy)
    assert projectile.damage_type == "magic"
    assert projectile.projectile_id in engine.projectiles
