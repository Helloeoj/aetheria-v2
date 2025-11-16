from .monster import Monster, register_monster
# === GOLEMS (LOW ACCURACY) ===
register_monster(Monster(
    name="Golem Shardling",
    tier=1,
    level=15,
    health=140,
    armor=0,
    resistances={'slash': 0.4, 'blunt': 0.5, 'stab': 0.4, 'magic': 0.0, 'ranged': 0.3},
    damage_type="blunt",
    min_damage=9,
    max_damage=15,
    accuracy=0.30,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Golem Boulderkin",
    tier=2,
    level=30,
    health=180,
    armor=0,
    resistances={'slash': 0.4, 'blunt': 0.5, 'stab': 0.4, 'magic': 0.0, 'ranged': 0.3},
    damage_type="blunt",
    min_damage=17,
    max_damage=23,
    accuracy=0.30,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Golem Stoneguard",
    tier=3,
    level=45,
    health=220,
    armor=0,
    resistances={'slash': 0.4, 'blunt': 0.5, 'stab': 0.4, 'magic': 0.0, 'ranged': 0.3},
    damage_type="blunt",
    min_damage=24,
    max_damage=30,
    accuracy=0.30,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Golem Runeshell",
    tier=4,
    level=60,
    health=260,
    armor=0,
    resistances={'slash': 0.4, 'blunt': 0.5, 'stab': 0.4, 'magic': 0.0, 'ranged': 0.3},
    damage_type="blunt",
    min_damage=32,
    max_damage=38,
    accuracy=0.30,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Golem Crystalcore",
    tier=5,
    level=75,
    health=300,
    armor=0,
    resistances={'slash': 0.4, 'blunt': 0.5, 'stab': 0.4, 'magic': 0.0, 'ranged': 0.3},
    damage_type="blunt",
    min_damage=39,
    max_damage=45,
    accuracy=0.30,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Golem Titan",
    tier=5,
    level=90,
    health=340,
    armor=0,
    resistances={'slash': 0.4, 'blunt': 0.5, 'stab': 0.4, 'magic': 0.0, 'ranged': 0.3},
    damage_type="blunt",
    min_damage=47,
    max_damage=53,
    accuracy=0.30,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))
