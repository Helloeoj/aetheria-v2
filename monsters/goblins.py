# ============================================================
# AETHERIA — GOBLIN FAMILY
# ============================================================
# Wired for:
#   - monsters/monster.py  (Monster class)
#   - aetheria_core.monsters loader (MONSTER_FAMILY)
# ============================================================

from .monster import Monster  # this is monsters/monster.py

# Core dict used by loaders
MONSTER_FAMILY = {

    # --------------------------------------------------------
    # Goblin Scout  (Tier 1)
    # --------------------------------------------------------
    2: Monster(
        name="Goblin Scout",
        tier=1,
        level=5,
        max_hp=60,
        min_damage=2,
        max_damage=6,
        damage_type="stab",
        accuracy=0.30,
        resistances={
            "slash": 0.20,
            "stab": 0.10,
            "blunt": 0.00,
            "magic": -0.10,
            "ranged": 0.05,
        },
        attack_speed=5,
        projectile_speed=0,
        attack_range=2,
    ),

    # --------------------------------------------------------
    # Goblin Worker (Tier 2)
    # --------------------------------------------------------
    15: Monster(
        name="Goblin Worker",
        tier=2,
        level=10,
        max_hp=100,
        min_damage=5,
        max_damage=9,
        damage_type="stab",
        accuracy=0.35,
        resistances={
            "slash": 0.25,
            "stab": 0.15,
            "blunt": 0.05,
            "magic": -0.05,
            "ranged": 0.10,
        },
        attack_speed=5,
        projectile_speed=0,
        attack_range=2,
    ),

    # --------------------------------------------------------
    # Goblin Warrior  (Tier 3)
    # --------------------------------------------------------
    29: Monster(
        name="Goblin Warrior",
        tier=3,
        level=15,
        max_hp=140,
        min_damage=7,
        max_damage=11,
        damage_type="stab",
        accuracy=0.40,
        resistances={
            "slash": 0.30,
            "stab": 0.20,
            "blunt": 0.05,
            "magic": -0.05,
            "ranged": 0.10,
        },
        attack_speed=5,
        projectile_speed=0,
        attack_range=2,
    ),

    # --------------------------------------------------------
    # Goblin Ranger (Tier 4)
    # --------------------------------------------------------
    42: Monster(
        name="Goblin Ranger",
        tier=4,
        level=20,
        max_hp=180,
        min_damage=10,
        max_damage=14,
        damage_type="ranged",
        accuracy=0.40,
        resistances={
            "slash": 0.15,
            "stab": 0.15,
            "blunt": 0.10,
            "magic": -0.05,
            "ranged": 0.20,
        },
        attack_speed=5,
        projectile_speed=2.5,
        attack_range=18,
    ),

    # --------------------------------------------------------
    # Goblin Mage (Tier 5)
    # --------------------------------------------------------
    56: Monster(
        name="Goblin Mage",
        tier=5,
        level=25,
        max_hp=220,
        min_damage=12,
        max_damage=16,
        damage_type="magic",
        accuracy=0.45,
        resistances={
            "slash": 0.10,
            "stab": 0.10,
            "blunt": 0.05,
            "magic": 0.25,
            "ranged": 0.00,
        },
        attack_speed=5,
        projectile_speed=2.0,
        attack_range=20,
    ),

    # --------------------------------------------------------
    # Goblin Chieftain (Tier 5)
    # --------------------------------------------------------
    60: Monster(
        name="Goblin Chieftain",
        tier=5,
        level=30,
        max_hp=260,
        min_damage=15,
        max_damage=19,
        damage_type="hybrid",  # melee hybrid for now
        accuracy=0.50,
        resistances={
            "slash": 0.30,
            "stab": 0.20,
            "blunt": 0.10,
            "magic": -0.15,
            "ranged": 0.15,
        },
        attack_speed=5,
        projectile_speed=0,
        attack_range=2,
    ),
}

# Backwards-compat alias some tools might expect
MONSTERS = MONSTER_FAMILY
