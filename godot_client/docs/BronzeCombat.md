# Tier 1 melee combat

Bronze melee weapons grant melee strength and separate slash, crush, and stab
accuracy bonuses. They no longer store fixed damage or accuracy percentages.
These are initial tuning values for review and encounter playtesting.

| Weapon | Melee strength | Slash | Crush | Stab | Interval | Hands |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Unarmed | 0 | 0 | 0 | 0 | 1.80 s | — |
| Bronze Dagger | 6 | 4 | 0 | 10 | 1.35 s | 1 |
| Bronze Shortsword | 12 | 12 | 0 | 6 | 1.62 s | 1 |
| Bronze Longsword | 20 | 16 | 0 | 8 | 2.25 s | 1 |
| Bronze Mace | 24 | 0 | 18 | 3 | 2.70 s | 1 |
| Bronze Warmaul | 48 | 0 | 30 | 0 | 3.00 s | 2 |

Daggers favor frequent stabs; shortswords favor quick slashes. Longswords trade
speed for strength and slash accuracy. Maces specialize in crush with a weak
stab option; they cannot slash. Warmauls trade speed and both hands for the
largest strength and crush bonuses. All retain 2-tile reach. Unarmed uses crush
with zero equipment bonuses.

The existing internal damage channel `blunt` represents Crush.
`set_attack_style("crush")` accepts the player-facing name.
Definitions live in `data/items.json`; formulas live in `scripts/stats.gd`.

## Damage

```text
S = sum of equipped melee_strength_bonus values
max_hit = max(1, floor(0.5 + (Strength skill + 8) × max(0, 16 + S) / 64))
```

Successful melee hits roll uniformly from 1 through max hit before any target
damage absorption. Absorption can reduce a landed hit to zero. Misses deal zero.
Existing critical multipliers remain capped at max hit. Attack skill and style
accuracy bonuses cannot change the damage ceiling or bias damage rolls.
Switching attack style does not change max hit. Strength cannot change accuracy.
Small strength increases need not cross a whole-number max-hit threshold.

| Weapon | Max at Strength 1 | Max at Strength 50 | Max at Strength 100 |
| --- | ---: | ---: | ---: |
| Unarmed | 2 | 15 | 27 |
| Dagger | 3 | 20 | 37 |
| Shortsword | 4 | 25 | 47 |
| Longsword | 5 | 33 | 61 |
| Mace | 6 | 36 | 68 |
| Warmaul | 9 | 58 | 108 |

These examples are calculated with only the named weapon, not stored weapon
damage values. Cadence, target weaknesses, and shield use are separate tradeoffs.
Neutral-target DPS is not guaranteed to be identical.

The damage formula uses a smaller base rating than accuracy so modest strength
bonuses give slow weapons enough power to justify their cadence. At Attack and
Strength 50 against an unarmoured Defence-50 target, preferred-style expected
DPS before critical effects is about 4.41 dagger, 4.65 shortsword, 4.53 longsword,
4.18 mace, and 6.48 warmaul. Warmauls earn higher damage output for giving up a
shield; maces trade some neutral damage output for crush effectiveness.

## Accuracy

```text
A = (Attack skill + 8) × max(0, 64 + selected style bonus)
    × max(0, 1 + equipment accuracy_bonus)
D = (target Defence level + 8) × 64 / (1 - selected style resistance)

if A > D: chance = 1 - (D + 2) / (2 × (A + 1))
otherwise: chance = A / (2 × (D + 1))
```

Final hit chance is bounded to 5–99%. Monster level supplies its Defence level
until dedicated monster defence skills exist. Monster authored resistances are
bounded to -50% through +80%. For player targets, raw equipment defence ratings
use the existing diminishing-returns conversion. Defence skill enters their
melee defence roll once; the old skill-resistance bonus is not also added.

There is no universal weapon accuracy percentage. At Attack 1 against an
unarmoured Defence-1 target, preferred-style chances are approximately:
unarmed 49.9%, dagger 56.7%, shortsword 57.8%, longsword 59.9%, mace 60.9%,
warmaul 65.9%. Higher Attack improves these chances; higher target Defence
reduces them. Different resistances can favor a secondary style.

Other equipment's attack bonuses contribute to accuracy only. Items without a
melee strength bonus contribute zero strength, so bronze jewelry improves
accuracy without increasing melee damage. Its generic accuracy bonus multiplies
the melee attack roll: +2% does not add two percentage points to final hit chance.

The journal displays all three style bonuses including zeros, melee strength,
computed damage, and the attack roll. It explains that hit chance depends on
target defence. The stats dictionary's compatibility `accuracy` value is a
reference chance against an unarmoured Defence-1 dummy; real hits use the rolls.

## Scope and validation

The outgoing melee model now applies to unarmed and all 40 melee weapons,
including all seven standard tiers and five artifacts. Monster melee attacks use
the same skill-based formulas, with no equipment bonuses and no player skill
cap. Ranged, magic, and spell costs retain their existing models.
Explicit accuracy overrides retain their previous behavior.

See [Melee Scaling and Titan Balance](MeleeScaling.md) for the tier strength
table, monster skill migration, landed-damage absorption, and encounter results.

Actors carry the new rolls through creation, equipment changes, and serialization.
Changing to a ranged weapon clears the melee roll. Auto-chase still stops inside
weapon reach and follows moving targets.

```powershell
Godot --headless --path godot_client res://scenes/dev_tools/bronze_combat_smoke.tscn
Godot --headless --path godot_client res://scenes/dev_tools/runite_equipment_smoke.tscn
Godot --headless --path godot_client --script res://scripts/dev_tools/inventory_items_smoke.gd
```

Tests cover skill/bonus separation, target defence and weaknesses, actual hits,
XP, cooldowns, growth, two-handed equipment, actor synchronization, chase,
existing tier progression, and journal item inspection.
