# Hidden grid movement implementation plan

**Goal:** Add shared invisible 32-pixel movement cells without changing artwork,
collision geometry, controls, progression or uncommitted Catacombs content.

**Architecture:** Geometry-queried grid navigation and a shared step traveller
operate in existing simulation units. WorldState owns logical occupancy and
travellers. Offline and authoritative movement use the same implementation.
Area adoption requires a geometry compatibility audit; incompatible areas retain
their existing movement. AoE conversion is a subsequent task.

**Tech stack:** Godot 4.5.1, GDScript, existing physics geometry.

**Spec:** User's approved movement/AoE design in this chat, movement phase only.

## Constraints and review focus

- Work in the active checkout; preserve the existing dirty files.
- 32 world pixels per cell; 128 pixels/second players, 80 enemies.
- Arrival occupancy, buffered turns/releases, Euclidean diagonal duration.
- Body sweeps, diagonal clearance and bounded searches; no geometry edits.
- Legacy positions recover through checked travel, never through a wall.
- Strict lattice cannot preserve every tavern aisle; do not silently enable it.
- Remote authority and local prediction must agree on segment completion.
- Test boundary coordinates, released mid-step input, blocked corners, routes
  around walls, off-grid starts and unreachable endpoints.

## Tasks

1. Add headless failing behavioural tests for conversions, navigation and travel.
2. Implement `hidden_grid.gd` and `grid_traveller.gd`; run those tests.
3. Integrate WorldState and offline keyboard/click/chase/enemy movement.
4. Integrate authoritative walk commands, snapshots and grid presentation.
5. Add real-map audit/integration coverage; enable only validated areas.
6. Run relevant movement, server, interaction, editor and startup checks.
7. Review explicit staged paths, commit, push and verify remote commit.

## Implementation evidence

Shared navigation, travel, logical occupancy, offline controls, chase/enemy
movement, authority and prediction are implemented. Real geometry gates enable
Valtheiris, Golem Kingdom and the locally installed Catacombs. Tavern movement
remains continuous because its table aisles have incompatible lattice alignment.
No art, collision geometry or save schema changed. AoE conversion remains the
next phase. The scoped runner passed 14 suites with zero failures, including
editor import, login startup and the optional adapted local Catacombs suite.
