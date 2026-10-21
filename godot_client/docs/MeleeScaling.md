# Melee scaling and Golem Titan balance

All 40 melee weapons use independent strength and accuracy bonuses. The existing
Attack/Strength separation, attack intervals, range, and player level caps remain.
Ranged and magic weapon calculations are outside this migration.

## Standard weapon strength

| Material | Dagger | Shortsword | Longsword | Mace | Warmaul |
| --- | ---: | ---: | ---: | ---: | ---: |
| Bronze | 6 | 12 | 20 | 24 | 48 |
| Iron | 8 | 16 | 27 | 32 | 65 |
| Steel | 11 | 22 | 36 | 43 | 86 |
| Blacksteel | 14 | 29 | 48 | 58 | 115 |
| Mithril | 19 | 38 | 64 | 77 | 154 |
| Adamantite | 25 | 50 | 84 | 101 | 202 |
| Runite | 31 | 62 | 104 | 125 | 250 |

These are explicit item definitions, generated from bronze family baselines with
rounded material factors 1 / 1.35 / 1.8 / 2.4 / 3.2 / 4.2 / 5.2. Runtime does not
infer strength from style accuracy or material name. Existing authored style
accuracy bonuses are retained. Jewelry grants accuracy but no implicit strength.

Artifact strength: Ironhowl Fangblade 120; Ashrender Maul 300; Dagger of the Nine
Veins 40; Oathbrand 132; Spitehook Chains 150. Ashrender is explicitly two-handed.
Existing artifact special-effect metadata is preserved; this pass does not
implement effects that were previously only metadata.

## Shared player and monster logic

- HP = Health skill × 20.
- Melee max hit = floor(0.5 + (Strength + 8) × (16 + strength bonus) / 64).
- Melee attack roll = (Attack + 8) × (64 + style bonus) × (1 + accuracy bonus).
- Defence level and armour determine the opposing defence roll.
- Successful raw damage is uniform from 1 to max hit. Criticals stay inside max hit.

The bounded hit-roll comparison and armour rating conversion are documented in
[Bronze Combat](BronzeCombat.md). Player skills remain capped at 100; monster
skills are positive integers with no player cap. A monster's displayed combat
level is an independent authored encounter rating, not a multiplier on damage.

All 82 monster definitions now author Attack, Strength, Defense, and Health in
`skills`. They have no equipped melee weapon: attack/strength equipment bonuses
are zero. This covers boss melee without hidden boss multipliers. For non-golem
monsters the migration preserves HP and the previous melee maximum, uses their
existing encounter level for Attack and Defense, and replaces fixed melee
accuracy/minimum damage with skill rolls and a raw minimum of 1. Those encounters
still need individual balance review, except for the subsequently reviewed
[goblin progression](GoblinCombat.md). Non-melee attacks retain their existing
damage and accuracy definitions; hybrids use the new skills for their melee
portion and their existing secondary projectile profile.

## Golem progression

| Golem | Combat level | Attack | Strength | Defense | Health | HP | Melee max hit |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Shardling | 45 | 60 | 100 | 45 | 35 | 700 | 27 |
| Boulderkin | 75 | 100 | 170 | 75 | 60 | 1200 | 45 |
| Stoneguard | 110 | 180 | 240 | 110 | 95 | 1900 | 62 |
| Runeshell | 145 | 300 | 340 | 145 | 135 | 2700 | 87 |
| Titan | 180 | 500 | 468 | 180 | 180 | 3600 | 119 |

Golems have landed-damage absorption of 60% slash, 60% stab, and 20% crush.
These values live in `damage_reductions`, separate from hit-chance resistances.
Their old physical hit-chance resistance offsets are zeroed to avoid applying
the same protection twice. Their Defense skill still opposes accuracy normally.
Magic/ranged resistance values and monster loot tiers are retained.

Absorption applies once, after raw damage and critical capping, rounded down to
an integer. A raw 100 slash/stab hit lands for 40; a raw 100 crush hit for 80.
XP uses actual HP removed, so absorbed damage does not grant extra XP. Projectile
damage uses the same final absorption step where the target defines it.

The Titan attacks every three 0.6-second ticks (1.8 seconds). Its Attack 500
gives an unarmed roll of 32,512: approximately 89% accuracy against an unarmoured
Defence-100 character, with lower chances against equipped armour. There is no
separate arbitrary base hit percentage used for its melee attacks.

## Reproducible encounter checks

Run Godot headless with `res://scenes/dev_tools/titan_balance_smoke.tscn`.
The suite uses the real combat engine's hit, critical, damage, absorption, and
HP application functions, and the real main scene's actor adapter. It compares
max-level players in matching equipment with two rings, necklace, and cape.
Warmauls have no shield. Trials assume continuous melee contact and no spells,
movement avoidance, eating delays, or regeneration.
Each warmaul fixture explicitly asserts the equipped weapon's exact name,
Crush style, an empty shield slot, and a 3.0-second attack interval. The report
records the weapon, style, hit chances, and raw/absorbed maximum hit for every row.

The optional healing model is explicitly hypothetical: four instant 200-HP heals
trigger at 1000 HP. It is an 800-HP preparation budget, not an implemented food
action. Food items currently have no usable eating mechanic. Finite healing is
necessary when interpreting minimum reliable equipment; unlimited healing would
undermine any statistical equipment threshold.

Results are written outside the repository to
`user://combat_balance/titan.json`. These tests establish a balance baseline,
not a guarantee of player outcomes. Actual playtesting, food timing and future
boss mechanics can change practical difficulty.

### Measured results

Godot 4.5.1, 2,000 seeded trials per loadout and healing condition:

| Max-level loadout | Wins without healing | Wins with 800 HP healing | Mean winning time with healing |
| --- | ---: | ---: | ---: |
| Naked unarmed | 0% | 0% | — |
| Full Bronze, warmaul | 0% | 0% | — |
| Full Iron, warmaul | 0% | 0% | — |
| Full Steel, warmaul | 0% | 0% | — |
| Full Blacksteel, warmaul | 0% | 0.10% | 110 s |
| Full Mithril, warmaul | 1.00% | 27.35% | 102 s |
| Full Adamantite, warmaul | 30.65% | 90.05% | 84 s |
| Full Runite, warmaul | 79.30% | 99.80% | 68 s |

These are measured encounter baselines for the recommended crush loadout, not
all weapons of a material. Sword users lose 60% landed damage and should expect
substantially worse results. Zero observed wins does not prove a mathematical
impossibility. With finite healing, Adamantite is the first tested tier to cross
85% success, while Runite crosses 99%; actual food implementation must retest
these targets with its eating time and preparation limits.

Verified warmaul-only output, with all player skills at 100:

| Warmaul and matching equipment | Hit chance | Raw max hit | Max after Titan's 20% crush absorption |
| --- | ---: | ---: | ---: |
| Bronze | 50.42% | 108 | 86 |
| Iron | 62.32% | 137 | 109 |
| Steel | 69.91% | 172 | 137 |
| Blacksteel | 74.20% | 221 | 176 |
| Mithril | 79.76% | 287 | 229 |
| Adamantite | 83.51% | 368 | 294 |
| Runite | 86.37% | 449 | 359 |

The extended suite covers all seven warmaul tiers plus naked unarmed, with
2,000 trials for each healing condition: 32,000 duels, 628 checks, zero failures.

The current Titan Strength of 468 raises max hit from 102 to 119 to target
approximately 30% no-healing survival for the max-level Adamantite warmaul
loadout at a 3.0-second attack interval. The measured rate is 613 wins out of
2,000 trials (30.65%). A regression check permits 27–33% to reflect a statistical
balance target. Run the same scene with `-- --calibrate-titan` to compare nearby
Strength values without changing the live monster definition.
