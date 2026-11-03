# Golem Titan combat

Spawn the approved Titan in the developer sandbox with **F5 → 1029 → Enter**.
The existing combat stats are retained. Its legs are bound: roaming, chasing,
ordinary movement and displacement cannot move the actor.

The shared combat engine chooses main attacks from shuffled bags containing
physical slam, dark bolt and shadow eruption. Consecutive main attacks cannot
be identical, including across bags. Start intervals vary from 8–12 game ticks.
Haymakers fill available three-tick gaps only when the target is within the
existing two-tile melee reach and visible. Range and sight are checked again
at contact; stepping away makes the punch miss. Remaining in melee never
suppresses or postpones the main attacks.

Both tile attacks capture ten unique, scattered, clear cells, including the
target's occupied cell when the warning begins. In very small spaces only
available clear cells are selected. Each cell runs its own approved animation:
red physical warnings/spikes or purple magic warnings/eruptions. Two ticks
warn, one tick rises, one tick retracts; damage resolves once at the peak on
tick three against current occupancy. Leaving a warned cell avoids that hit.

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
--headless --path . res://scenes/dev_tools/orb_combat_smoke.tscn
--headless --path . res://scenes/dev_tools/region_freeze_smoke.tscn
--path . --script res://scripts/dev_tools/titan_combat_review.gd -- --output=<absolute evidence directory>
```

The graphical review spawns the actual Titan and player in Golem Kingdom,
drives the real combat engine, captures all attacks at 4× zoom, and checks the
Titan's position after the fight. It uses an isolated development character
and does not save it.
