from .monster import Monster, register_monster
# === WOLVES ===
register_monster(Monster(
    name="Wolf Cub",
    tier=1,
    level=5,
    health=60,
    armor=0,
    resistances={'slash': 0.05, 'blunt': 0.0, 'stab': 0.05, 'magic': -0.1, 'ranged': 0.05},
    damage_type="slash",
    min_damage=2,
    max_damage=6,
    accuracy=0.18,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Wolf Hunter",
    tier=2,
    level=10,
    health=100,
    armor=0,
    resistances={'slash': 0.05, 'blunt': 0.0, 'stab': 0.05, 'magic': -0.1, 'ranged': 0.05},
    damage_type="slash",
    min_damage=5,
    max_damage=9,
    accuracy=0.24,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Wolf Alpha",
    tier=3,
    level=15,
    health=140,
    armor=0,
    resistances={'slash': 0.1, 'blunt': 0.1, 'stab': 0.1, 'magic': 0.0, 'ranged': 0.1},
    damage_type="slash",
    min_damage=7,
    max_damage=11,
    accuracy=0.30,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Wolf Direwolf",
    tier=4,
    level=20,
    health=180,
    armor=0,
    resistances={'slash': 0.1, 'blunt': 0.05, 'stab': 0.1, 'magic': -0.05, 'ranged': 0.1},
    damage_type="slash",
    min_damage=10,
    max_damage=14,
    accuracy=0.36,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Wolf Moonfang",
    tier=5,
    level=25,
    health=220,
    armor=0,
    resistances={'slash': 0.05, 'blunt': 0.0, 'stab': 0.05, 'magic': -0.1, 'ranged': 0.05},
    damage_type="slash",
    min_damage=12,
    max_damage=16,
    accuracy=0.42,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Wolf Elder Fang",
    tier=5,
    level=30,
    health=260,
    armor=0,
    resistances={'slash': 0.05, 'blunt': 0.0, 'stab': 0.05, 'magic': -0.1, 'ranged': 0.05},
    damage_type="slash",
    min_damage=15,
    max_damage=19,
    accuracy=0.48,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))
