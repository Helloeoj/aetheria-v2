# Golem Titan combat

Spawn the approved Titan in the developer sandbox with **F5 Ã¢â€ â€™ 1029 Ã¢â€ â€™ Enter**.
The existing combat stats are retained. Its legs are bound: roaming, chasing,
ordinary movement and displacement cannot move the actor.

Both dodgeable ground AoEs (slam spikes and shadow eruption) deal **2×** the
normal hit damage. The multiplier applies after the existing accuracy,
critical-hit and damage-reduction calculation; bolt and haymaker damage stay
at 1×. A miss still deals no damage.

Once engaged, all monsters retain aggression when a player stops attacking or
clears their target. They drop dead/missing targets and targets outside their
existing boundary. Returning after a boundary reset does not re-engage them
without a new attack.

The shared combat engine chooses main attacks from shuffled bags containing
physical slam, dark bolt and shadow eruption. Consecutive main attacks cannot
be identical, including across bags. Start intervals vary from 8Ã¢â‚¬â€œ12 game ticks.
Haymakers fill available three-tick gaps only when the target is within the
existing two-tile melee reach and visible. Range and sight are checked again
at contact; stepping away makes the punch miss. Remaining in melee never
suppresses or postpones the main attacks. When the target stays outside punch
reach, an available gap immediately selects a main attack instead of waiting
for a punch opportunity: one main attack every four ticks (2.4 seconds), with
no out-of-range haymaker.

Both tile attacks capture ten unique, scattered, clear cells, including the
target's occupied cell when the warning begins. In very small spaces only
available clear cells are selected. Each cell runs its own approved animation:
red physical warnings/spikes or purple magic warnings/eruptions. The body
winds up for two ticks before revealing or locking the cells. The coloured
floor cue remains visible during the existing one-tick rise; damage resolves
once at its peak on tick three, giving 0.6 seconds from floor cue to damage.
Retraction keeps its approved speed. Moving during the body windup changes
which player tile is selected; leaving it after the cue avoids that hit.

The dark bolt has no ground warning. The approved roar and purple crystals
announce casting; release occurs after two ticks. The existing orb art follows
the simulated missile with bounded steering, swept collision and a finite
40-tile lifetime. Ordinary projectiles retain straight flight. Losing the
target removes a homing missile.

`titan_encounter.gd` owns decisions and damage in both offline and authoritative
region simulation. Snapshots publish current action age, cells and projectile
positions so clients can join during an attack. `titan_combat_visuals.gd` only
presents that state, reusing the approved body and tile animations. It never
chooses hits. No permanent world spawn or production-server deployment is
introduced by this change.

Validation with Godot 4.5.1 from `godot_client`:

```text
--headless --path . res://scripts/dev_tools/titan_combat_smoke.tscn
--headless --path . res://scripts/dev_tools/titan_combat_feedback_smoke.tscn
--headless --path . res://scripts/dev_tools/titan_damage_aggro_smoke.tscn
--headless --path . res://scenes/dev_tools/orb_combat_smoke.tscn
--headless --path . res://scenes/dev_tools/region_freeze_smoke.tscn
--path . --script res://scripts/dev_tools/titan_combat_review.gd -- --output=<absolute evidence directory>
```

Use `--ranged` after `--` for the out-of-melee regression and delayed warning captures.
Add `--stop-attacking` to clear the player target after engagement and verify retaliation.

The graphical review spawns the actual Titan and player in Golem Kingdom,
drives the real combat engine, captures all attacks at 4Ãƒâ€” zoom, and checks the
Titan's position after the fight. It uses an isolated development character
and does not save it.

## Idle playback

The approved 48 idle PNGs remain intact and the loop stays 2.4 seconds long.
Identical poses around the loop boundary share a single visible-pose duration,
removing the previous 250ms freeze. On return from a combat body animation,
idle starts from neutral instead of revealing its hidden mid-cycle frame.

Real-map pacing and handoff check:

```text
--path . --script res://scripts/dev_tools/titan_idle_pacing_review.gd -- --output=<absolute evidence directory>
```

This measures actual rendered pose holds after warm-up, captures the Titan
beside the player at 4x, and checks a combat-animation handoff to idle frame 0.
