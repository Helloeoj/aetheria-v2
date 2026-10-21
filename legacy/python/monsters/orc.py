from .monster import Monster, register_monster
# === ORCS ===
register_monster(Monster(
    name="Orc Grunt",
    tier=3,
    level=10,
    health=100,
    armor=0,
    resistances={'slash': 0.1, 'blunt': 0.1, 'stab': 0.05, 'magic': 0.0, 'ranged': 0.05},
    damage_type="slash",
    min_damage=5,
    max_damage=9,
    accuracy=0.24,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Orc Brawler",
    tier=4,
    level=20,
    health=140,
    armor=0,
    resistances={'slash': 0.1, 'blunt': 0.1, 'stab': 0.05, 'magic': 0.0, 'ranged': 0.05},
    damage_type="slash",
    min_damage=10,
    max_damage=14,
    accuracy=0.30,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Orc Slayer",
    tier=5,
    level=30,
    health=180,
    armor=0,
    resistances={'slash': 0.1, 'blunt': 0.1, 'stab': 0.05, 'magic': 0.0, 'ranged': 0.05},
    damage_type="slash",
    min_damage=15,
    max_damage=19,
    accuracy=0.36,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Orc Skirmisher",
    tier=5,
    level=40,
    health=220,
    armor=0,
    resistances={'slash': 0.1, 'blunt': 0.1, 'stab': 0.05, 'magic': 0.0, 'ranged': 0.05},
    damage_type="slash",
    min_damage=20,
    max_damage=24,
    accuracy=0.42,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Orc Warlock",
    tier=5,
    level=50,
    health=260,
    armor=0,
    resistances={'slash': 0.1, 'blunt': 0.1, 'stab': 0.05, 'magic': 0.0, 'ranged': 0.05},
    damage_type="magic",
    min_damage=25,
    max_damage=29,
    accuracy=0.48,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))


register_monster(Monster(
    name="Orc Warchief",
    tier=5,
    level=60,
    health=300,
    armor=0,
    resistances={'slash': 0.2, 'blunt': 0.2, 'stab': 0.1, 'magic': 0.1, 'ranged': 0.1},
    damage_type="hybrid",
    min_damage=30,
    max_damage=34,
    accuracy=0.54,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))
