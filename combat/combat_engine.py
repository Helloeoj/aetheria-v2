import random


def hit_roll(attacker_accuracy: float, defender_evasion: float = 0.0) -> bool:
    """
    Determines if an attack hits.
    attacker_accuracy: 0.00–1.00
    defender_evasion: 0.00–1.00 (you can use this later for player dodge)
    """

    # Effective hit chance
    chance = attacker_accuracy - defender_evasion

    # Basement/floor so attacks aren’t 0% or 100%
    chance = max(0.05, min(chance, 0.95))

    return random.random() <= chance


def crit_roll(crit_chance: float) -> bool:
    """Returns True if the crit occurs."""
    return random.random() <= crit_chance


def roll_damage(min_damage: int, max_damage: int) -> int:
    """Rolls a random base damage."""
    return random.randint(min_damage, max_damage)


def apply_resistances_and_armor(damage: int, damage_type: str, defender) -> int:
    """
    Applies defender resistances + armor reduction.
    defender must have:
        defender.resistances (dict)
        defender.armor (int)
    """

    # Handle hybrid special case: average slash + blunt for now
    if damage_type == "hybrid":
        # Hybrid = (slash + blunt) / 2
        slash_res = defender.resistances.get("slash", 0)
        blunt_res = defender.resistances.get("blunt", 0)
        resistance = (slash_res + blunt_res) / 2
    else:
        # Normal single-type resistance
        resistance = defender.resistances.get(damage_type, 0)

    # Apply resistance as a percent modifier
    damage_after_res = int(damage * (1 - resistance))

    # Apply flat armor reduction
    damage_after_armor = max(0, damage_after_res - defender.armor)

    return damage_after_armor


def perform_attack(attacker, defender):
    """
    Runs a full OSRS-style attack:
    1) Accuracy check
    2) Crit roll
    3) Damage roll
    4) Resistance + armor reduction
    5) Apply damage and return result dict
    """

    # 1. HIT CHECK
    if not hit_roll(attacker.accuracy, defender_evasion=0.0):
        return {
            "result": "miss",
            "damage": 0,
            "remaining_hp": defender.health
        }

    # 2. CRIT CHECK
    is_crit = crit_roll(attacker.crit_chance)

    # 3. DAMAGE ROLL
    base_damage = roll_damage(attacker.min_damage, attacker.max_damage)

    if is_crit:
        base_damage = int(base_damage * attacker.crit_multiplier)

    # 4. DEFENSE REDUCTION
    final_damage = apply_resistances_and_armor(base_damage, attacker.damage_type, defender)

    # 5. APPLY DAMAGE
    defender.health -= final_damage

    return {
        "result": "crit" if is_crit else "hit",
        "damage": final_damage,
        "remaining_hp": defender.health
    }


def fight_turn(attacker, defender):
    """
    Returns a clean readable message for combat logs.
    """

    outcome = perform_attack(attacker, defender)

    if outcome["result"] == "miss":
        return f"{attacker.name} MISSED {defender.name}!"

    if outcome["result"] == "crit":
        return f"💥 CRITICAL HIT! {attacker.name} dealt {outcome['damage']} damage! ({defender.name} HP: {outcome['remaining_hp']})"

    # Normal hit
    return f"{attacker.name} hit {defender.name} for {outcome['damage']} damage. ({defender.name} HP: {outcome['remaining_hp']})"
