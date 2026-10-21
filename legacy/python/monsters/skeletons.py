from .monster import Monster, register_monster
# === SKELETONS ===
register_monster(Monster(
    name="Skeleton Boneshard",
    tier=1,
    level=6,
    health=80,
    armor=0,
    resistances={'slash': 0.1, 'blunt': -0.1, 'stab': 0.0, 'magic': 0.0, 'ranged': 0.05},
    damage_type="stab",
    min_damage=3,
    max_damage=7,
    accuracy=0.21,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Skeleton Footsoldier",
    tier=2,
    level=12,
    health=120,
    armor=0,
    resistances={'slash': 0.1, 'blunt': -0.1, 'stab': 0.0, 'magic': 0.0, 'ranged': 0.05},
    damage_type="stab",
    min_damage=6,
    max_damage=10,
    accuracy=0.27,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Skeleton Knight",
    tier=3,
    level=18,
    health=160,
    armor=0,
    resistances={'slash': 0.2, 'blunt': -0.1, 'stab': 0.1, 'magic': -0.05, 'ranged': 0.0},
    damage_type="slash",
    min_damage=9,
    max_damage=13,
    accuracy=0.33,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Skeleton Sniper",
    tier=4,
    level=24,
    health=200,
    armor=0,
    resistances={'slash': 0.1, 'blunt': -0.1, 'stab': 0.0, 'magic': 0.0, 'ranged': 0.05},
    damage_type="ranged",
    min_damage=12,
    max_damage=16,
    accuracy=0.39,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Skeleton Acolyte",
    tier=5,
    level=30,
    health=240,
    armor=0,
    resistances={'slash': 0.1, 'blunt': -0.1, 'stab': 0.0, 'magic': 0.0, 'ranged': 0.05},
    damage_type="magic",
    min_damage=15,
    max_damage=19,
    accuracy=0.45,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Skeleton Captain",
    tier=5,
    level=36,
    health=280,
    armor=0,
    resistances={'slash': 0.1, 'blunt': -0.1, 'stab': 0.0, 'magic': 0.0, 'ranged': 0.05},
    damage_type="stab",
    min_damage=18,
    max_damage=22,
    accuracy=0.51,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))
