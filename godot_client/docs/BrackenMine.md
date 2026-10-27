# Bracken Mine

The user approved this original fantasy cave layout on 2026-10-27 and requested a
separate indoor scene reached through an exterior cave entrance. The requested
ore mix is copper, tin, iron and coal. The approved original images, prompt and
source history are retained under `art_sources/bracken-mine/`.

Enter through **Bracken Mine** in the clearing just north of Valtheiris, west of
the riverside road. Click the cave or choose **Enter Bracken Mine** from its
context menu. The lantern-framed southern doorway inside returns to Valtheiris.
Walking over either threshold does not automatically trigger travel.

## Editing the area

Open `res://scenes/BrackenMine.tscn` to run the whole area. Edit native terrain,
individual supply assemblies and ore placements through
`res://scenes/BrackenMineContent.tscn` and its artwork instance
`res://scenes/BrackenMineArtwork.tscn`.

The map spans 1536×1024 world pixels at identity scale. Ground, BoundaryRock and
Foreground are separate 32×32-cell TileMapLayers. The gameplay lattice shares
the existing 32px world cell size and fixed origin (0,0); artwork is not resized
to fit the player. Native nearest filtering, lossless import and no mipmaps
are required. The deterministic source export uses discrete 2px clusters and a
shared PixelLab palette to remove soft source transitions while retaining the
approved composition and world dimensions. Ore sprites remain unchanged at
their existing native scale.

Canonical ores are individual instances from `scenes/MapProps/OreNodes/`.
Use the existing **Ore Nodes - Full and Depleted** scene collection or drag a
named scene into the y-sorted content. Keep 96px centers for compact pockets,
128px alongside walking routes, and retain clear access at the front of each
rock. Place nodes against the outer room walls, leaving room centers and the
main loop clear. Do not paint replacement rock clusters into the terrain.

The user's annotated empty map replaces the earlier proposed placement layout.
Its 15 dots request three copper, three tin, four iron and five coal nodes.
`Assets/Maps/BrackenMine/ore-markers.json` preserves every dot, color and the
documented small correction for any wall, object or movement conflict.
Unconflicted marks stay exact. Do not add nodes or rebalance the ore counts.

Each dot denotes the visible alpha rectangle center. The canonical root is
24px below that center. Match marked positions at integer native pixels; do
not snap them to 32px or move the independent movement/AoE grid. Full visible
silhouettes must remain on the floor with 2px wall clearance, at least 4px from
other ore, and no overlap with the existing cart/supplies. Physical approaches
may use any accessible side, particularly for nodes beside southern walls.
Never force artwork into a wall to satisfy a foot-anchor proximity threshold.

The supply cart and crate/barrel assembly are reusable transparent scene props.
Touching and overlapping crates remain complete assemblies because the flat
source does not contain their hidden backs. Wall-attached lanterns stay integral
to their continuous stone/timber support. No actors are baked into map artwork.

## Rebuilding and collision

`tools/build_bracken_mine_art.py` rebuilds pixel preparation, bounded prop
extraction, repaired hidden floor and native terrain TileSets. It verifies exact
recomposition of the prepared source and prohibits repair outside prop masks.
`tools/build_bracken_mine_geometry.py` authors content from explicit traced
floor/exclusion polygons, placement records and room probes. It also synchronizes
the wrapper's runtime adoption probes whenever placements move. Geometry is not
inferred from image colors. See `Assets/Maps/BrackenMine/layout.json` and
`decomposition.json` for the exact current records.

These builders regenerate their own files. Preserve intentional manual changes
in the corresponding builder first. A source or layout revision needs the saved
map-art workflow and renewed physical/path verification, not just a new PNG.

The existing main scene, UI, character state, HiddenGrid and cave-portal travel
remain authoritative. Keep arrival/exit markers, room probes, physical rock
bases and all reachable approaches consistent between offline and online play.
The existing Golem Kingdom entrance has its own destination and remains intact.

This area places ore artwork and physical bases. It does not define new mining
skills, pickaxes, rewards, timing, depletion, progression, smelting or recipes.
Existing mining systems and production data are unchanged by this map task.

## Verification

Run Godot 4.5.1 with the installed project and the scoped development checks:

- `res://scripts/dev_tools/bracken_mine_geometry.gd`
- `res://scripts/dev_tools/bracken_mine_visuals.gd`
- `res://scenes/dev_tools/bracken_mine_travel.tscn`

These checks cover actual installed geometry, actor clearance, shared-grid paths
and portal/state behavior. Supplement them with a real scene render at camera4x
alongside the current character; source previews alone cannot verify runtime
clarity or depth ordering. Keep generated evidence outside the repository.

The previous 12-node arrangement passed base-collider checks but was rejected
by the user for visible wall clipping and blocked routes. Those old passing
counts do not validate its artwork. The new silhouette regression first failed
that arrangement, including nine rocks with alpha outside the authored floor.
It independently pins the 15 supplied dots and colors and checks the actual
imported alpha for every ore and both extracted supply props.

Keep fresh visual, geometry, runtime-grid and travel results in the supporting
task record. Real GPU overview and 4x renders must accompany the checks; the
character appears only in separate verification evidence. Source and scene
contain no baked actors. Existing ore textures, floor outlines and terrain
artwork remain unchanged by the marked-placement correction.

Marked-placement validation on 2026-10-27: 437 full-silhouette checks,
2560 geometry/grid checks and 58 travel checks passed. All 324 physically clear
grid centers connect to the entrance, and the installed main adapter validates
all 25 room/approach probes. Reserved through-lanes measure 48px in the western
rooms and 32px in the denser eastern pockets; the actual actor is 24px wide.
The real GPU render retains all 29070 opaque ore pixels exactly, preserves the
terrain outside ore masks and has no nonuniform 4x pixel blocks. Ten conflicted
marks receive documented corrections of 6–35px; five marks remain exact.
