# Goblin combat progression

The goblin family is the early melee progression, with the Shaman and Chieftain
anchored around players with individual Attack, Strength, and Defence skills of
40–50. Displayed monster level is an authored encounter rating, not a multiplier
on its skills. This pass changes no loot, monster IDs, spawn tiers, player weapons,
or Golem Titan stats.

## Combat profiles

| Goblin | Level | HP | Attack | Strength | Defence | Health | Attacks |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Scout | 5 | 60 | 5 | 14 | 3 | 3 | Ranged 2–6, base accuracy 30% |
| Worker | 12 | 120 | 12 | 24 | 6 | 6 | Stab 1–8 |
| Warrior | 25 | 200 | 22 | 40 | 12 | 10 | Stab 1–12 |
| Shaman | 45 | 700 | 25 | 54 | 15 | 35 | Magic 20–36, base accuracy 70% |
| Chieftain | 50 | 1000 | 85 | 160 | 50 | 50 | Slash 1–42; magic 16–28, base accuracy 65% |

Melee uses the same unarmed Attack/Strength rolls as other monsters; no hidden
weapon bonus. HP is Health × 20. Ranged and magic use the existing authored NPC
projectile profiles, not the unused melee skills on the Scout or Shaman. NPC
projectile criticals can exceed the listed non-critical damage range. All goblins
attack every three 0.6-second ticks (1.8 seconds).

At melee distance, the Chieftain performs three slash attacks followed by one
magic projectile. Beyond melee distance it uses magic and closes in. The Shaman
is physically easier to hit and has less health, but its magic remains dangerous
against melee equipment.

## Defences

| Goblin | Landed slash/stab/crush reduction | Landed magic reduction |
| --- | ---: | ---: |
| Scout / Worker / Warrior | 0% | 0% |
| Shaman | 0% | 60% |
| Chieftain | 25% | 25% |

Physical hit chance depends on the Defence skill above. Legacy slash/stab/crush
and magic accuracy-offset resistances are zero, avoiding a second defence layer
on top of the intended absorption. Ranged accuracy-offset resistances are
unchanged. Absorption rounds landed damage down once; it does not reduce the
chance to hit.

The older goblin levels in `LootEconomyReview.md` describe the historical loot
review. The combat levels above supersede those labels without modifying loot.

## Validation

Run the headless scene `res://scenes/dev_tools/goblin_combat_smoke.tscn` for runtime
profile checks, landed-damage absorption checks, and actual projectile/hybrid
attack rotation checks. Add `-- --benchmark-goblins` for 500 seeded duels per
matchup and a generated report at `user://combat_balance/goblins.json`.

The benchmark uses full matching melee armour, cape, two rings, necklace,
Longsword and Kiteshield. Attack/Strength/Defence equal the stated test skill;
Health equals that skill with a minimum of 10. Skills are held fixed to avoid
level-up healing during a duel. No food, spells, movement, terrain or other
enemies are included. The player initiates at melee distance. Real player
cooldowns, monster ticks, accuracy, criticals, absorption and projectile travel
are simulated with 0.03-second frames. These are controlled one-on-one balance
checks, not general survival guarantees.

### Seeded benchmark results

Observed wins without food, 500 duels per matchup:

| Attack / Strength / Defence / Health | Full set | Shaman survival | Chieftain survival | Shaman kill time | Chieftain kill time |
| --- | --- | ---: | ---: | ---: | ---: |
| 40 | Blacksteel | 23.0% | 1.2% | 61.1 s | 145.9 s |
| 40 | Mithril | 80.0% | 62.2% | 52.5 s | 118.1 s |
| 45 | Blacksteel | 74.6% | 43.4% | 59.8 s | 135.4 s |
| 45 | Mithril | 98.6% | 97.0% | 49.3 s | 108.7 s |
| 50 | Blacksteel | 97.4% | 94.4% | 56.4 s | 127.1 s |
| 50 | Mithril | 100% | 100% | 44.5 s | 97.3 s |

Kill times average victories only; the level-40 Blacksteel Chieftain time has
just six victories. These results make the bottom of the 40–50 skill window
dangerous, especially in Blacksteel. Mithril and higher skills make both bosses
much more manageable. The Shaman is substantially quicker to kill; the Chieftain
tests sustained survival. Sampled 100% survival is not a guarantee.

The early fixtures also won all 500 duels each: level-1 melee skills in full
Bronze against the Scout (Health 10, 75.7 seconds, 42.2 HP lost on average),
level-12 skills in full Iron against the Worker (Health 12, 45.9 seconds, 38.3 HP
lost), and level-25 skills in full Steel against the Warrior (Health 25, 36.6
seconds, 37.2 HP lost). These measure the stated complete gear sets, not naked or
partially equipped starters, consecutive kills, or multiple attackers.

### Actual combat level 40: full Steel versus Chieftain

Run the same scene with `-- --steel-level-40` to reproduce 1,000 seeded duels
per build. Every build has 135 total Attack/Strength/Defence levels, Range 1
and Magic 1, and the real `get_combat_level()` returns exactly 40. Steel's
Attack/Defence requirements are met by every build. Full Steel includes the
Longsword, Kiteshield, armour, cape, necklace and two rings, with Slash selected.
Health is held at 45 (900 HP) to isolate melee stat allocation; Health is
independent of combat level, so this is an explicit assumption, not a derived
player HP value. No food, spells, movement, additional enemies or mid-fight
skill gains are included. Game balance is unchanged by this test.

| Build | Attack | Strength | Defence | Wins / 1,000 | Observed survival |
| --- | ---: | ---: | ---: | ---: | ---: |
| Balanced | 45 | 45 | 45 | 30 | 3.0% |
| Attack focus | 65 | 35 | 35 | 0 | 0% |
| Strength focus | 35 | 65 | 35 | 150 | 15.0% |
| Defence focus | 35 | 35 | 65 | 2 | 0.2% |
| Attack + Strength | 55 | 55 | 25 | 18 | 1.8% |
| Attack + Defence | 55 | 25 | 55 | 0 | 0% |
| Strength + Defence | 25 | 55 | 55 | 72 | 7.2% |
| Extreme Attack | 95 | 20 | 20 | 0 | 0% |
| Extreme Strength | 20 | 95 | 20 | 85 | 8.5% |
| Extreme Defence | 20 | 20 | 95 | 0 | 0% |

The strongest tested split is 35/65/35, but it still dies in 85% of trials.
Its wins average 123.1 seconds with 81.2 HP remaining. Balanced wins average
158.0 seconds with 52.7 HP remaining. Increasing only accuracy or defence at
the expense of damage leaves the Chieftain alive too long. Extreme Defence
reduces its melee hit chance to 25.0%, but the unchanged magic portion and
long fight still overcome the player. Zero sampled wins does not prove that
a win is mathematically impossible; these are estimates from finite samples,
and this test does not establish an optimal split among every legal build.

This mode uses real engine player cooldowns, monster ticks, hybrid selection
and projectile resolution, skipping inactive time between events. In-flight
shots advance at intervals of at most 0.03 seconds. Generated results are saved
to `user://combat_balance/steel_level_40_chieftain.json`. The run completes
10,000 duels with 220 validation checks and no failures or timeouts.
