# Skill Progression

Aetheria has nine independent player skills: Health, Attack, Strength, Defense,
Range, Magic, Fishing, Cooking, and Smithing. Each has its own level and experience total,
while all nine share the same level 1–100 experience curve. Fishing, Cooking and Smithing do not
contribute to combat level; see [Fishing.md](Fishing.md) for its minigame,
rod controls, bait requirements, and cast-distance rules.
See [Cooking.md](Cooking.md) for fish recipes, burn mastery and campfire integration.
See [Smithing.md](Smithing.md) for heat control, forging, quenching and XP pacing.

## Overall combat level

Player combat level ranges from 1 to 150 and is derived from five equally
weighted skills: Attack, Strength, Defense, Range, and Magic. Health has its own
progression and does not contribute to this rating.

Each of the five skills starts at 1 and can gain 99 levels, giving 495 skill
level increases. Combat level starts at 1 and can gain 149 levels. The formula is:

```text
combat level = 1 + floor((sum of the five skill levels - 5) * 149 / 495)
```

Every skill level gained contributes about 0.301 combat levels. The fractional
contributions combine before rounding down, so the displayed combat level rises
after every three or four combined skill increases. Level 150 requires all five
skills at 100; four maxed skills and one at 99 give combat level 149.

| Five combat skills | Combat level |
| --- | ---: |
| All at 1 | 1 |
| One at 100, four at 1 | 30 |
| All at 50 | 74 |
| All at 99 | 148 |
| Four at 100, one at 99 | 149 |
| All at 100 | 150 |

`PlayerState.get_combat_level()` derives the rating from the current skill
levels whenever requested. Skill XP and level changes therefore update it
automatically, without a separate combat XP total. The equipment screen displays
the rating, and combat level gains are announced alongside skill level gains.

Monster combat levels may exceed the player ceiling. The planned golem progression
starts around level 45 and ends with a level-180 Titan. Its proposed level ladder,
combat-stat questions, and warmaul rewards are recorded in
[`GolemLootReview.md`](GolemLootReview.md).

## What each skill controls

| Skill | Current effect | Experience source |
| --- | --- | --- |
| Health | Maximum HP is 20 per level. Gaining a Health level also grants the added HP capacity. | 1 XP per point of actual damage dealt with any attack style. |
| Attack | Melee accuracy for stab, slash, and blunt attacks. | 3 XP per point of actual melee damage dealt. |
| Strength | Maximum damage for melee attacks. | 3 XP per point of actual melee damage dealt. |
| Defense | Adds up to 0.25 physical armor rating before diminishing-return conversion. | 3 XP per point of actual damage received. |
| Range | Accuracy and maximum damage for ranged attacks. | 3 XP per point of actual ranged damage dealt. |
| Magic | Spell unlocks, spell accuracy and power, magic resistance, and mana capacity (10 per level). | 3 XP per point of actual magic damage dealt, plus cast XP based on the spell's unlock level. |
| Fishing | Rod range mastery, resistance to fish pull, a small control-boundary bonus, and bait/fish unlocks. | XP for successfully landing fish, varying by species. |
| Cooking | Raw fish recipes and declining burn chance, reaching zero at mastery. | XP per successfully cooked fish; burnt food awards none. See [Cooking.md](Cooking.md) for logic and deferred campfire integration. |

Damage XP uses HP actually removed from the target, so misses, fully resisted
hits, and damage beyond the target's remaining HP do not award extra XP. Failed
spell casts do not award cast XP. A successful cast awards 10 XP per required
Magic level: a level 1 spell grants 10 XP, while a level 100 spell grants 1,000
XP. Reward rates and this scaling rule are centralized in `SkillProgression` for
later tuning.

The Skills journal shows these XP sources and an earned-XP session meter.
Spell details show the cast and damage rewards. See
[`ExperienceRates.md`](ExperienceRates.md) for XP/hour controls, milestone
thresholds, the 80-hour reference calibration, and pending Magic sustain decisions.

Equipment and skill defense ratings are summed before conversion into resistance:
`rating / (1 + abs(rating))`, bounded from -0.5 to 0.8. Magic skill contributes
its defense bonus to magic rating; Defense contributes to physical ratings.
Incoming attacks against players multiply accuracy by `1 - resistance`, retaining
the 5% minimum and 99% maximum hit chance. This preserves armor tier improvements
without changing damage per landed hit. See [Runite Equipment](RuniteEquipment.md)
for the approved stacking rules, comparisons, and balance effects.

## Spell casting and mastery

Every unlocked spell has a 20% chance to fail to cast at its required Magic
level. Each Magic level above that requirement reduces the chance by one
percentage point. At 20 levels above the requirement, the spell is mastered
and can no longer fail to cast.

| Magic levels above the spell requirement | Cast failure chance |
| ---: | ---: |
| 0 | 20% |
| 5 | 15% |
| 10 | 10% |
| 15 | 5% |
| 20 or more | 0% |

The casting check uses the player's Magic level when the cast finishes. A
failed cast consumes its normal casting time and mana, produces no spell
effect, and awards no cast XP. This applies to damage, area, healing, wall,
and knockback spells. After a successful cast, damage spells still use the
existing accuracy and resistance rules to determine whether they hit.

The level 100 cap means spells requiring more than level 80 cannot reach full
mastery. At Magic 100, Cinderfall retains a 4% failure chance, Repelling Gust
8%, Astral Lance 16%, and Starfall 20%.

## Experience curve

The exponential curve is shared by every skill. Its first 80-hour melee reference
calibration puts level 1 at 0 XP, level 90 at 9,725,000 XP, and level 100 at
19,450,000 XP. The target accounts for available tier upgrades and 70% combat
uptime; other skill sources still need separate pacing review. XP stops at
the level 100 cap. Levels are derived from cumulative XP, and the player state
can report each skill's current level, XP total, next-level threshold, and XP
remaining to that threshold.

The default player retains the existing Health level 10 and starts the five
combat skills at level 1, giving combat level 1. Enabling the optional
`max_skills_for_testing` setting on the game scene sets all eight skills to level
100 and gives combat level 150; this setting defaults to false.
Magic unlock levels and spell names remain documented in
[`CoreSpellbook.md`](CoreSpellbook.md).

Equipment unlocks every 10 levels: Bronze tier 1 requires 0, Iron tier 2
requires 10, through tier 11 at 100. Weapons require Attack; catalog Armor
requires Defense. See [`EquipmentProgression.md`](EquipmentProgression.md).

## Implementation

`scripts/skill_progression.gd` owns shared thresholds, XP reward constants,
the casting failure curve, the combat level formula, skill names, and compatibility aliases. `PlayerState`
owns independent XP and level values and exposes `get_skill_progress()`, `get_skills_progress()`,
`get_combat_level()`, `set_skill_level()`, and `add_skill_experience()`. The older Magic-only API
continues to delegate to this shared system.

`CombatEngine` awards XP from resolved hit outcomes for melee, ranged, magic,
spell, and incoming damage. It checks for casting failure before applying spell
effects or awarding cast XP. It returns skill XP and level-up events alongside
combat events. Skill XP currently lives in the in-memory player state; player
save data is not part of the current runtime.
