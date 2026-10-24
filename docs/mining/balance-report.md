# Mining balance simulation

Default result: **65.01 active hours from level 1 to 100**, within the initial 60–70 hour target. This is proposed simulation tuning, not installed gameplay balance. No world interaction or item definitions changed.

## Reproduce and configure

Use Python 3 (standard library only) from the repository root:

```powershell
python tools/mining_balance.py
python tools/mining_balance.py --csv
python tools/mining_balance.py --compare-level 90
python tools/mining_balance.py --config path/to/scenario.json
python -m unittest discover -s tools -p test_mining_balance.py
```

On this PC, use `$env:LOCALAPPDATA/Aetheria/online/venv/Scripts/python.exe` if `python` resolves to the Windows Store alias. `--csv` emits all 100 levels: best combination, probability, ores/hour, XP/hour, XP needed, hours to next level and cumulative hours to reach. `--compare-level` emits every unlocked ore/tool combination, allowing comparisons at fixed skill or fixed tool quality.

All tuning lives in `tools/mining_balance.json`: independent ore requirements, raw XP, probability endpoints/mastery/exponent, respawn durations, retarget time and tool intervals/unlocks. `xp_scale=1.212` scales proposed rewards with positive half-up integer rounding. The initial unscaled proposal took 78.76 hours; scaling XP gives 65.01 without hiding waiting time. Effective XP per ore: Bronze 121, Iron 230, Coal 400, Blacksteel 654, Mithril 1,054, Adamantite 1,757. These supersede the design's illustrative Bronze numbers for this experiment only.

P1–P5 are hypothetical performance profiles, not items or item IDs. Their unlocks are 1/18/37/59/78 and full attempt intervals 3.0/2.6/2.2/1.8/1.5 seconds. Real pickaxes still require separate catalog authorization. Ore names resolve through the existing catalog; Steel Ore and Starforged Ore are excluded.

## Model and limits

The simulator reads the current constants from `godot_client/scripts/skill_progression.gd` and evaluates its exponential, half-up-rounded thresholds (0 XP at 1; 9,725,000 at 90; 19,450,000 at 100). It uses the design's independent probability curve, without OSRS tables.

Each candidate site has **one uncontested deposit**. Every success yields one ore, depletes that deposit, and waits its full respawn plus 1.2 seconds for retargeting. Attempts are independent Bernoulli trials: expected extraction time is `interval / probability`, expected cycle time is `interval / probability + respawn + retarget`, and ores/hour is `3600 / cycle`. A full interval precedes the first roll. There is no tick manipulation, banking or extended travel. At each level, evaluate every unlocked ore/profile and select maximum expected XP/hour. This is optimal among these stationary single-site options, not an optimizer for multi-site rotations.

Availability is explicit and conservative relative to a dense patch: respawns are never assumed free or divided by an invented rock count. Increasing respawn models a longer effective wait; it does not simulate competing miners. Multi-deposit rotation, variable contention, discrete XP overshoot and finite-session startup/transient effects are not modeled. Level times use the steady-state fractional-reward approximation `XP gap / XP per hour`; totals are planning estimates rather than exact sample-path completion times. Final map density and contention must be measured before this becomes a production 65-hour claim.

## Progression checkpoints

| Level reached | Efficient ore / profile | Ores/hour | XP/hour | Hours to next | Cumulative hours |
| --- | --- | ---: | ---: | ---: | ---: |
| 1 | Bronze / P1 | 226.2 | 27,372 | 0.054 | 0.00 |
| 20 | Iron / P2 | 264.3 | 60,784 | 0.090 | 1.36 |
| 40 | Coal / P3 | 280.0 | 111,992 | 0.196 | 4.04 |
| 60 | Mithril / P4 | 185.7 | 195,771 | 0.447 | 10.25 |
| 80 | Adamantite / P5 | 189.5 | 333,008 | 1.050 | 25.94 |
| 90 | Adamantite / P5 | 211.2 | 371,065 | 1.882 | 39.73 |
| 95 | Adamantite / P5 | 219.2 | 385,146 | 2.563 | 50.41 |
| 99 | Adamantite / P5 | 224.5 | 394,375 | 3.301 | 61.70 |
| 100 | Adamantite / P5 | 225.6 | 396,446 | 0 | 65.01 |

Ore switches: Iron at 12, Coal at 27, Blacksteel at 42, Mithril at 60, Adamantite at 79. Profiles upgrade at their unlocks. Level-100 rates are hypothetical uncapped activity throughput; the actual XP cap prevents further XP gain.

Sensitivity: keeping P1 throughout takes **78.54 hours**; doubling all respawn waits takes **106.69 hours**. At level 90 on Adamantite, P1→P5 changes expected ores/hour from **172.3 to 211.2**. With P5 fixed, level 80→99 changes **189.5 to 224.5**. Deposit access therefore matters more than tool speed alone in this scenario.

Validation: seven deterministic unit tests cover curve milestones, geometric expectation/cooldown arithmetic, unlock/mastery boundaries, level/tool sensitivity, availability sensitivity, optimal-route/cumulative accounting, 60–70-hour target and invalid/restricted configuration. Run the commands above after balance edits; this report is a snapshot of the committed default configuration.
