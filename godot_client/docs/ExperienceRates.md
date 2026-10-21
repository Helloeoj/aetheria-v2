# Experience rates and the 80-hour target

## Design target

The target is approximately **80 hours to reach level 100 in one combat skill**,
with better weapons increasing actual damage and XP/hour as the player levels.
This is a pacing target, not a timer that awards or limits progression.

The first calibration uses current melee equipment and enemies. Attack and
Strength train together and reach 100 together in the reference model. Defense,
Range, Magic, and passively earned Health still need their own gameplay pacing
review; this shared curve does not guarantee identical training times for them.

The approved damage rewards remain active:

| Action | Earned XP |
| --- | --- |
| Deal 1 actual melee damage | 3 Attack + 3 Strength + 1 Health |
| Deal 1 actual ranged damage | 3 Range + 1 Health |
| Deal 1 actual magic damage | 3 Magic + 1 Health |
| Receive 1 actual damage | 3 Defense |
| Complete a successful spell cast | 10 Magic XP × the spell's required level |

Crush, Slash, and Stab all train Attack and Strength. Defense trains from HP
lost, so avoiding hits reduces its rate. Health gains across all outgoing
styles. There is no separate kill XP. Misses, zero damage, and overkill add no
damage XP. Cast XP is paid once per successful cast, while area damage XP is
paid per target. Failed casts award zero cast XP. Accepted XP stops at the cap.

## Implemented curve

The shared exponential shape is retained, with its cap rescaled from 1,000,000
to **19,450,000 XP** for the new 80-hour reference. Level 90 remains halfway to
100 by cumulative XP. This replaces the earlier absolute 500,000/1,000,000
anchors; rewards per damage and cast have not been multiplied.

| Level | Cumulative XP |
| ---: | ---: |
| 1 | 0 |
| 2 | 1,476 |
| 10 | 17,799 |
| 20 | 56,110 |
| 30 | 132,650 |
| 40 | 285,570 |
| 50 | 591,087 |
| 60 | 1,201,475 |
| 70 | 2,420,961 |
| 80 | 4,857,357 |
| 90 | 9,725,000 |
| 99 | 18,148,033 |
| 100 | 19,450,000 |

Skills start at 1; the current character starts at Health 10 with its threshold
of 17,799 XP. Combat level remains derived from five skill levels and has no
separate XP pool. Player XP is currently memory-only; restart play for a fresh
character initialized against the new curve.

## Gear-aware reference model

The deterministic calculator uses the current catalog and combat formulas:

- Attack and Strength rise together. All required weapons are available as
  soon as their Attack requirement is met. No jewelry bonuses are included.
- The most productive eligible melee weapon/style is selected at each level.
  The route uses Bronze, Iron, Steel, Blacksteel, Mithril, Adamantite, and Runite
  Warmauls, then the existing tier-10 Ashrender Maul at level 90.
- Targets progress through active Goblin Scout, Worker, Warrior, Shaman, and
  Chieftain definitions. Target HP and defense are read from the catalog.
- Calculations include target-dependent accuracy, uniform melee damage,
  integer-truncated critical hits capped at maximum damage, weapon intervals,
  and finite target HP so overkill earns no extra XP.
- Combat occupies 70% of play time; the remaining 30% represents travel,
  recovery, retargeting, and similar downtime. Gear acquisition is not
  simulated separately. Survival and incoming damage are not simulated.

At the old one-million cap this route takes about 4.11 hours. Rescaling to
19,450,000 produces approximately 80.00 hours. Approximate milestone times:

| Level reached | Total reference hours |
| ---: | ---: |
| 10 | 2.01 |
| 20 | 3.83 |
| 30 | 5.73 |
| 40 | 8.02 |
| 50 | 10.83 |
| 60 | 14.66 |
| 70 | 20.30 |
| 80 | 30.37 |
| 90 | 48.79 |
| 100 | 80.00 |

This is an analytical estimate, not an 80-hour gameplay test. Different
weapons, target selection, gear acquisition, jewelry, survival, and downtime
change the result. The calculator's alternate catalog-enemy route takes about
68.16 hours at this cap. Changes to weapon stats, enemies, missing tier items,
or XP rules require recalibration.

Reproducible calculator, detailed JSON, and band report are retained in the
supporting workspace's `work/xp-balance/` directory. The calculator reads the
active `godot_client/data` catalog; it does not modify game data.

## Equipment unlocks

Each tier requires `(tier - 1) × 10`. Bronze tier 1 has no skill requirement;
Iron tier 2 requires 10, through tier 11 at 100. Weapons use Attack, including
bows and magic weapons. Catalog Armor items use Defense, including shields,
capes, rings, and necklaces. Ammo is unrestricted.

Requirements are enforced before replacing gear or transferring stacks. The
journal and F6 item tool show the same policy and the actual equip result.
See [EquipmentProgression.md](EquipmentProgression.md) for the catalog ladder
and future tiers.

## Magic and Defense still need calibration

Defense's XP/hour depends on incoming damage and armor: better armor avoids
hits and lowers training XP. The melee reference cannot establish its time.

Spell cast rewards scale with requirement and vary by cast time. At unlock,
with 20% fizzles and unlimited mana, cast XP alone ranges from 16,000 XP/hour
for Razorwind to 2,534,400 for Repelling Gust. These theoretical continuous-cast
figures exclude damage, movement, recovery, and changing cast reliability.
Healing at full HP, raising walls, and empty area casts currently qualify for
successful-cast XP; requiring a useful effect is a separate design decision.

Mana recovery is absent. A fresh mage can make five Razorwind attempts; even
five maximum-damage successes grant at most 80 XP against level 2's new
1,476-XP threshold. Casting progression needs mana recovery. Magic weapon
attacks can still earn damage XP without spell mana. A chosen recovery rule
and real casting cadence are needed before calibrating Magic to 80 hours.

## Measuring training in game

Open **Journal → Skills** for XP sources, earned session XP, and XP/hour. The
shared timer starts with the first earned XP and includes subsequent play time
and downtime. Rates show **Measuring...** for the first 60 seconds to avoid
extrapolating a first hit into a misleading hourly rate. **Reset session**
clears only the measurements.

Only accepted combat XP events feed the meter. Practice level edits reset it
and exclude artificial XP changes. Restoring HP does not reset it. Counts stop
growing when a skill accepts no more XP at its cap. Spell details and tooltips
show successful-cast XP, damage XP, and zero XP for a failed cast.

`SkillProgression` owns thresholds and reward calculations;
`SkillTrainingSession` measures accepted events supplied by `main.gd`.
