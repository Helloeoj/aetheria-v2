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

The installed layout has 12 nodes, three each of copper, tin, iron and coal.
Their physical bases remain within 32px of an outer wall and their foot anchors
within 64px, with all bases fully on the floor. Each room retains an authored
48px through-lane, and every south/front approach remains reachable. The north
rim iron node replaces the previous iron placement in the northeast passage.

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
- `res://scenes/dev_tools/bracken_mine_travel.tscn`

These checks cover actual installed geometry, actor clearance, shared-grid paths
and portal/state behavior. Supplement them with a real scene render at camera4x
alongside the current character; source previews alone cannot verify runtime
clarity or depth ordering. Keep generated evidence outside the repository.

After the user's room-boundary placement correction on 2026-10-27, installed
validation passed 2194 geometry checks and 58 offline/server travel checks.
The original installation also passed the existing 19 portal, 26 scene-state
and 111 server-travel checks. All 332 clear grid centers connect to the arrival.
The placement regression rejects the previous scattered layout, checks wall
proximity and alcove placement, and sweeps a 48px body through all four rooms.
The actual installed GPU composition matches the prepared source outside the
12 canonical ores;
all 23256 opaque ore pixels retain their exact RGB, and 4x environment pixel
blocks have no nonuniform samples. The character appears only in separate
verification renders. The source and scene contain no baked actors.
