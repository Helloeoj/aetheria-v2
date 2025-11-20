# ============================================================
# ARTIFACT SET BONUSES (ACTIVATE WHEN FULL 3-PIECE SET EQUIPPED)
# ============================================================

SET_BONUSES = {

    # ========================================================
    # MAGIC SETS
    # ========================================================

    "Starlight Shroud": {
        "type": "auto_decoy",
        "description": "Below 25% HP, auto-casts a decoy illusion (once per combat).",
        "trigger_hp_percent": 0.25,
        "cooldown_type": "once_per_combat"
    },

    "Ashweaver Raiment": {
        "type": "burning_cinders",
        "description": "Spells leave burning cinders on the ground for 3 seconds.",
        "ground_burn_duration": 3,
        "burn_damage_per_tick": 5
    },

    "Runeshell Mantle": {
        "type": "spell_reflect",
        "description": "Reflects 10% of spell damage back to attackers.",
        "reflect_percent": 0.10
    },

    "Frostveil Regalia": {
        "type": "freeze_chance",
        "description": "Spells have a 20% chance to freeze enemies for 1 second.",
        "freeze_chance": 0.20,
        "freeze_duration": 1
    },

    "Whispersoul Robes": {
        "type": "death_revive",
        "description": "Once every 5 minutes, revive at 20% HP instead of dying.",
        "revive_hp_percent": 0.20,
        "cooldown_seconds": 300
    },


    # ========================================================
    # MELEE SETS
    # ========================================================

    "Titanbound Plate": {
        "type": "stacking_resist",
        "description": "Gain +5% damage resist every 10s in combat (max 25%).",
        "resist_per_stack": 0.05,
        "stack_interval_seconds": 10,
        "max_resist": 0.25
    },

    "Skullrender Armor": {
        "type": "lowhp_attack_speed",
        "description": "Below 30% HP, gain +25% attack speed.",
        "trigger_hp_percent": 0.30,
        "attack_speed_bonus": 0.25
    },

    "Drakehide Wrathset": {
        "type": "anti_knockback",
        "description": "Immune to knockback; reduce fire damage by 40%.",
        "fire_resist_percent": 0.40
    },

    "Blackiron Enclave": {
        "type": "flat_dr",
        "description": "Reduces all physical damage by a flat amount per hit.",
        "flat_reduction": 6  # adjustable
    },

    "Wardensteel Vesture": {
        "type": "taunt_on_crit",
        "description": "Being critically hit taunts nearby enemies.",
        "taunt_radius": 3.0
    },


    # ========================================================
    # RANGED SETS
    # ========================================================

    "Galehunter’s Garb": {
        "type": "dodge_crit_bonus",
        "description": "Dodging increases next shot’s crit chance by 50% (stacks x2).",
        "crit_bonus": 0.50,
        "max_stacks": 2
    },

    "Hollowbark Suit": {
        "type": "stealth_on_still",
        "description": "Standing still for 3 seconds grants stealth until you move.",
        "still_time_required": 3
    },

    "Emberstring Wraps": {
        "type": "explosive_shots",
        "description": "Shots have a 10% chance to explode on hit.",
        "explosion_chance": 0.10,
        "explosion_damage": 15
    },

    "Snareweave Cuirass": {
        "type": "trap_mastery",
        "description": "Traps reset 2x faster and root enemies longer.",
        "reset_multiplier": 0.5,
        "root_bonus_seconds": 1
    },

    "Mirrorshade Mail": {
        "type": "ranged_reflect",
        "description": "Small chance to reflect ranged attacks back at attacker.",
        "reflect_chance": 0.08
    }
}
