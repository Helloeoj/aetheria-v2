from .monster import Monster, register_monster
# === SPIDERS ===
register_monster(Monster(
    name="Spider Creeper",
    tier=1,
    level=8,
    health=80,
    armor=0,
    resistances={'slash': 0.05, 'blunt': -0.1, 'stab': 0.1, 'magic': 0.0, 'ranged': 0.05},
    damage_type="stab",
    min_damage=4,
    max_damage=8,
    accuracy=0.21,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Spider Webspinner",
    tier=2,
    level=16,
    health=120,
    armor=0,
    resistances={'slash': 0.05, 'blunt': -0.1, 'stab': 0.1, 'magic': 0.0, 'ranged': 0.05},
    damage_type="stab",
    min_damage=8,
    max_damage=12,
    accuracy=0.27,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Spider Fangmaw",
    tier=3,
    level=24,
    health=160,
    armor=0,
    resistances={'slash': 0.05, 'blunt': -0.1, 'stab': 0.1, 'magic': 0.0, 'ranged': 0.05},
    damage_type="stab",
    min_damage=12,
    max_damage=16,
    accuracy=0.33,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Spider Poisonfang",
    tier=4,
    level=32,
    health=200,
    armor=0,
    resistances={'slash': 0.1, 'blunt': -0.1, 'stab': 0.15, 'magic': 0.15, 'ranged': 0.05},
    damage_type="magic",
    min_damage=16,
    max_damage=20,
    accuracy=0.39,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Spider Silktomb",
    tier=5,
    level=40,
    health=240,
    armor=0,
    resistances={'slash': 0.05, 'blunt': -0.15, 'stab': 0.1, 'magic': 0.0, 'ranged': 0.1},
    damage_type="ranged",
    min_damage=20,
    max_damage=24,
    accuracy=0.45,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Spider Broodmother",
    tier=5,
    level=48,
    health=280,
    armor=0,
    resistances={'slash': 0.1, 'blunt': -0.1, 'stab': 0.2, 'magic': 0.1, 'ranged': 0.05},
    damage_type="stab",
    min_damage=24,
    max_damage=28,
    accuracy=0.51,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))
