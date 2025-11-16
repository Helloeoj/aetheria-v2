from .monster import Monster, register_monster
# === TROLLS (DYNAMIC RESISTANCES) ===
register_monster(Monster(
    name="Troll Grub",
    tier=1,
    level=12,
    health=120,
    armor=0,
    resistances={'slash': 0.1, 'blunt': 0.2, 'stab': 0.1, 'magic': -0.1, 'ranged': -0.05},
    damage_type="blunt",
    min_damage=6,
    max_damage=10,
    accuracy=0.27,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Troll Basher",
    tier=2,
    level=24,
    health=160,
    armor=0,
    resistances={'slash': 0.2, 'blunt': 0.3, 'stab': 0.1, 'magic': 0.0, 'ranged': 0.0},
    damage_type="blunt",
    min_damage=12,
    max_damage=16,
    accuracy=0.33,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Troll Smasher",
    tier=3,
    level=36,
    health=200,
    armor=0,
    resistances={'slash': 0.1, 'blunt': 0.35, 'stab': 0.1, 'magic': -0.1, 'ranged': 0.0},
    damage_type="blunt",
    min_damage=18,
    max_damage=22,
    accuracy=0.39,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Troll Thrower",
    tier=4,
    level=48,
    health=240,
    armor=0,
    resistances={'slash': 0.1, 'blunt': 0.25, 'stab': 0.1, 'magic': 0.0, 'ranged': 0.1},
    damage_type="blunt",
    min_damage=24,
    max_damage=28,
    accuracy=0.45,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Troll Shaman",
    tier=5,
    level=60,
    health=280,
    armor=0,
    resistances={'slash': 0.1, 'blunt': 0.1, 'stab': 0.1, 'magic': 0.2, 'ranged': 0.1},
    damage_type="magic",
    min_damage=30,
    max_damage=34,
    accuracy=0.51,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))

register_monster(Monster(
    name="Troll Matron",
    tier=5,
    level=72,
    health=320,
    armor=0,
    resistances={'slash': 0.2, 'blunt': 0.2, 'stab': 0.2, 'magic': 0.1, 'ranged': 0.0},
    damage_type="blunt",
    min_damage=36,
    max_damage=40,
    accuracy=0.57,
    crit_chance=0.05,
    crit_multiplier=1.5,
    status_effects=[],
))
