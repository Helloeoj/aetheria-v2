# Golem Titan combat implementation

Goal: stationary Titan using varied main attacks, conditional haymakers, and
steering dark bolts, with shared authoritative combat and approved artwork.

Design: shuffled three-attack bags (slam, bolt, shadow eruption), no identical
back-to-back main attacks, independently randomized8-12tick spacing. Haymakers
fill free3tick windows at existing melee reach2 and never postpone the main
schedule. Two-tick warning; tile attacks hit at the rising spike/eruption peak
on tick3. Ten unique scattered clear cells include the captured target cell.
The bolt releases at tick2, uses limited-angle steering with collision sweeps,
and has finite range. Existing stats, saves, controls and other NPCs stay intact.

- Add failing engine tests for immobility, main rotation independent of melee
  occupancy, random fights, locked tiles/dodging, range checks and homing.
- Add a Titan-specific encounter controller, stationary movement guard, and
  opt-in projectile steering; use existing damage and collision rules.
- Add snapshot-backed presentation with approved slam/cast/haymaker and one
  independent effect per tile. Reuse actual authoritative projectile positions.
- Run focused engine/online checks and a real Golem Kingdom combat review.
- Commit only task deltas over the clean merge of existing spell integration
  and approved Titan asset branches; preserve the ordinary index/active branch.

No agent delegation. Stop after two unsuccessful fixes of the same problem.
