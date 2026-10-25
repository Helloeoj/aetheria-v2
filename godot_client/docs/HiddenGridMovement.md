# Invisible grid movement

Gameplay cells are 32 world pixels (one existing simulation unit). Art, actor
display scale and 24px collision shapes are unchanged. The map-local pixel origin
is fixed at `(0,0)`, projected into the existing Y-up simulation; it does not follow
the camera or shift when map bounds expand. Negative cells use floor division.

`HiddenGrid` supplies geometry-derived cell clearance, full-body swept edges,
diagonal cardinal clearance and bounded A* searches (8192 expanded cells).
`GridTraveller` supplies real-time travel and arrival occupancy. `WorldState`
owns traveller state for players and monsters and commits each segment through
the existing physical movement handler, including when one update crosses several
centers. Actors are not navigation obstacles and can share cells.

Players retain 128px/sec and enemies 80px/sec. Diagonals cost sqrt(2) times a
cardinal step. Direction changes and releases finish the committed edge before
turning or stopping. Movement locks pause immediately. Off-grid saved/spawned or
knocked-back positions recover through a checked connection at normal movement
speed on the next movement request; no save format or progression is replaced.
Authored markers remain unchanged. Logical cells are runtime state, while durable
coordinates retain the existing continuous format.

## Area adoption

The map adapter waits for transition completion and physics synchronization,
then validates spawn connections, routes between authored spawn/room probes,
portal/cooking approaches, fishing shores and crafting approaches. A failed
audit keeps the area's original movement. `grid_adoption_report()` explains
the decision; passing probes is not an exhaustive proof of every possible route.
Every executed edge is still checked against live physics.

Valtheiris and Golem Kingdom pass the installed geometry audit. The locally
installed Catacombs also passes its eight room probes; its source/art/navigation
remain separate, pre-existing uncommitted work. Its 24px navigation data is not
replaced or rounded into the 32px lattice. The adapter reads existing room probes
without modifying its assets or routing script. The area is optional when absent.

The tavern deliberately retains continuous movement: the two table aisles are
28.5px and 30.75px wide, and have no common center alignment on a 32px lattice.
Neither collision nor artwork is changed to conceal that incompatibility.

This movement phase does not convert AoE spell footprints, change wall rules or
add ground targeting. `CombatActor.logical_cell` is available for the next phase.

## Online parity

The authoritative region uses the same world/grid/traveller code. Walk commands
are validated by a checked route instead of requiring a straight terrain ray.
Snapshots add grid metadata and each actor's committed cell, segment target and
active flag. The client follows the server's adoption decision. Keyboard
prediction uses the shared stepper, replays pending input and remains bounded to
250ms; rendering corrections never change server occupancy. Remote actors retain
snapshot interpolation. Activities cannot start during an unfinished server step.

## Validation

`tools/test_hidden_grid.ps1 -Godot <installed Godot executable>` runs the scoped
regressions, editor import and login startup. It checks both exit codes and
script-error output, limits each process to 55 seconds, and writes evidence
outside the repository. The local Catacombs suite runs only when present.

Use installed Godot 4.5.1 with `--headless --path godot_client`:

- `--script res://scripts/dev_tools/hidden_grid_unit.gd`
- `--script res://scripts/dev_tools/hidden_grid_maps.gd`
- `res://scenes/dev_tools/movement_server_smoke.tscn`
- `--script res://scripts/dev_tools/movement_presentation_smoke.gd`
- `--script res://scripts/dev_tools/world_interaction_smoke.gd`
- `res://scenes/dev_tools/online_region_travel_smoke.tscn`
- `res://scenes/dev_tools/tavern_integration.tscn`
- `res://scenes/dev_tools/scene_travel_unit.tscn`
- `res://scenes/dev_tools/region_authority_smoke.tscn`
- `res://scenes/dev_tools/region_freeze_smoke.tscn`
- `res://scenes/dev_tools/bronze_combat_smoke.tscn`

The optional local Catacombs integration suite needs its pixel-exact walk
expectations updated to checked tile-center destinations. Its original source
was backed up outside the repository and the updated test remains uncommitted
with the rest of that pre-existing implementation. Geometry, reach, actual input,
corner, progression and round-trip assertions are retained.
