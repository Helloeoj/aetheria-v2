# Walkable monster spawns

User requirement: dev-menu monsters must spawn on a feasible tile within three
tiles of the player's current position; monsters may spawn only where players
can walk. Preserve the existing menus, controls, maps, artwork and saves.

Replace the fixed spawn point with a bounded search of connected 32px cells,
using the current player's actual position and a Euclidean radius of 3 tiles.
Require fresh 24px body collision clearance, authored floor support and legal
diagonal sweeps throughout the route. Exclude occupied bodies and the player's
own tile. If none exists, change no world state and report that in the dev menu.
Keep the same entry point for F5 and sprite-viewer spawns.

Reuse the tile floor checker as a normal runtime dependency, retaining its old
development path for compatibility. Recognize the installed Valtherian floor
contract without changing that map's art or geometry. Use the same terrain
predicate at real-world monster registration, including authoritative regions;
pure domain fixtures without a map retain their existing test geometry.

Implementation/validation:

- [x] Reproduce fixed/far/invalid spawns with actual maps before changing code.
- [x] Add bounded-selection unit coverage for barriers, holes, occupied cells,
  radius edges, signed coordinates and no-space failure.
- [x] Implement selection, common registration validation and honest dev-menu
  feedback; preserve existing unrelated main.gd export fixes when staging.
- [x] Run map spawn tests, floor/teleport/grid/combat and development-controls
  regressions, import and startup. Inspect real Godot 4x player/monster render.
- [x] Fresh read-only review found no actionable defects. Real seven-scene
  spawn suite: 135 checks, selector unit suite: 55, all passing. Existing sprite
  integration, combat, teleport, floor, grid, movement, authority and development
  controls pass. Editor import and Login startup are clean. Inspected real 4x
  player/three-monster render for placement, crispness and foot sorting.

Final synchronization: review the staged feature diff, commit only appropriate
changes, push to verified v2 origin and verify the remote hash. Retain inherited
unmerged branch history and all unrelated working-tree edits; report commit URL.

This changes runtime actor spawning, not environment prop placement, artwork,
collision definitions or persistent map content. The passive-prop worldbuilding
manifest does not certify runtime actors; actual physics/map/route tests and
the rendered game provide the relevant evidence.
