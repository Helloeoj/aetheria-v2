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
portal/cooking/mining approaches, fishing shores and crafting approaches. A failed
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

## Interactions and enemies

`InteractionApproach` reads existing authored positions and ranges for fishing,
cooking, crafting, mining, portals and ground pickups. `WorldInteraction` queues
a collision-checked approach and starts the original action/interface only when
the actor has arrived at a center within its real range. Mining retains its
line-of-sight requirement; other interactions retain their existing wall rules.
Objects are not moved, and small interaction ranges are not silently enlarged.
The existing P-key fishing practice shortcut still opens immediately.

Offline mining now delegates to the same `MiningService` as the server, including
eligibility, timing, rewards and depletion. Production's empty pickaxe catalog
and unapproved placement hold remain intact; tests use the existing tool fixture,
not new production items or deposits.

Auto-chase and monster chase/return use checked grid routes and existing speeds,
attack ranges, aggression and leashes. Forced displacement preserves the actual
knockback distance, invalidates the old step and recovers on the next movement
request. Monsters displaced beyond the leash walk home instead of teleporting.
The legacy roaming helper can use the shared world and per-frame advance; it has
no production caller, so this does not newly enable idle roaming in existing maps.

## Online parity

The authoritative region uses the same world/grid/traveller code. Walk commands
are validated by a checked route instead of requiring a straight terrain ray.
Interaction walk commands name a registered target; the server derives its
position, range and eligibility rather than trusting client-supplied coordinates
or range. Public drops also retain ownership checks. The tavern uses its existing
navigation around furniture while its grid adoption remains on hold.

Snapshots add grid metadata and each actor's committed cell, segment target,
active flag, displacement epoch and bounded arrival history (eight centers).
Region admission waits for the geometry audit and adopts it before returning;
concurrent entrants share one pending load and one region. The client follows the server's
adoption decision and ignores older snapshots. Keyboard
prediction uses the shared stepper, replays pending input and remains bounded to
250ms; rendering corrections never change server occupancy or cross collision.
Epoch changes invalidate prediction even for small knockbacks. Remote actors
interpolate along reported center arrivals rather than cutting across corners;
missing history holds/snaps instead of inventing a diagonal. Activities cannot
start during an unfinished server step, and direct pickup/portal commands also
require an arrived center. Reliable walk/activity commands replace
held keyboard intent without sending a later synthetic release that cancels them.

## Validation

`tools/test_hidden_grid.ps1 -Godot <installed Godot executable>` runs the scoped
regressions, editor import and login startup. It checks both exit codes and
script-error output, limits each process to 55 seconds, and writes evidence
outside the repository. The local Catacombs suite runs only when present.

Use installed Godot 4.5.1 with `--headless --path godot_client`:

- `--script res://scripts/dev_tools/hidden_grid_unit.gd`
- `--script res://scripts/dev_tools/grid_parity_unit.gd`
- `--script res://scripts/dev_tools/grid_interaction_integration.gd`
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

The runner also covers portal intents, mining definitions/service/authority/host,
crafting UI and snapshot transport. Run `tools/test_cooking.py` and
`tools/test_inventory_items.py` with the installed Godot executable for the
existing fishing/cooking input, minigame, food and inventory regression suites.

The optional local Catacombs integration suite needs its pixel-exact walk
expectations updated to checked tile-center destinations. Its original source
was backed up outside the repository and the updated test remains uncommitted
with the rest of that pre-existing implementation. Geometry, reach, actual input,
corner, progression and round-trip assertions are retained.
