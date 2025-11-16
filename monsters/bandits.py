from .monster import Monster, register_monster
# === BANDITS ===
register_monster(Monster(
    name="Bandit Cutpurse",
    tier=1,
    level=7,
    health=80,
    armor=0,
    resistances={'slash': 0.05, 'blunt': 0.05, 'stab': 0.05, 'magic': 0.0, 'ranged': 0.05},
    damage_type="stab",
    min_damage=3,
    max_damage=7,
    accuracy=0.21,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Bandit Footpad",
    tier=2,
    level=14,
    health=120,
    armor=0,
    resistances={'slash': 0.05, 'blunt': 0.05, 'stab': 0.05, 'magic': 0.0, 'ranged': 0.05},
    damage_type="stab",
    min_damage=7,
    max_damage=11,
    accuracy=0.27,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Bandit Enforcer",
    tier=3,
    level=21,
    health=160,
    armor=0,
    resistances={'slash': 0.05, 'blunt': 0.05, 'stab': 0.05, 'magic': 0.0, 'ranged': 0.05},
    damage_type="stab",
    min_damage=10,
    max_damage=14,
    accuracy=0.33,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Bandit Sharpshooter",
    tier=4,
    level=28,
    health=200,
    armor=0,
    resistances={'slash': 0.05, 'blunt': -0.05, 'stab': 0.1, 'magic': -0.1, 'ranged': 0.2},
    damage_type="ranged",
    min_damage=14,
    max_damage=18,
    accuracy=0.39,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Bandit Sorcerer",
    tier=5,
    level=35,
    health=240,
    armor=0,
    resistances={'slash': -0.1, 'blunt': -0.1, 'stab': -0.1, 'magic': 0.25, 'ranged': 0.1},
    damage_type="magic",
    min_damage=17,
    max_damage=21,
    accuracy=0.45,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Bandit Boss",
    tier=5,
    level=42,
    health=280,
    armor=0,
    resistances={'slash': 0.1, 'blunt': 0.1, 'stab': 0.1, 'magic': 0.1, 'ranged': 0.1},
    damage_type="hybrid",
    min_damage=21,
    max_damage=25,
    accuracy=0.51,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))
