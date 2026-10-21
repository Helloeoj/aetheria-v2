# Golem Kingdom dungeon

Runtime scene: `res://scenes/GolemKingdom.tscn`.
Editable art/collision scene: `res://scenes/GolemKingdomContent.tscn`.

The approved environment retains its original 1254 × 1254 logical coordinates
at an integer 3× scale, giving this independent area 3762 × 3762 world pixels.
The `Detail4x/` sibling assets restore finer pixel detail within that same
layout. The restored master is 5016 × 5016 pixels, with 5120 × 5120 padded
terrain atlases. No characters or creatures are baked into the assets.

This is a new art-detail pass using overlapping restoration regions, rather
than enlarging each old pixel into a larger square. The original 249 cutout
positions, feet, masks, and gameplay geometry remain aligned. Original PNGs
and TileSets under `Terrain/` and `Objects/` remain available for rollback.

Built-in image generation restored sixteen overlapping 354-square source
regions at 1254-square native detail (about 3.54 times the source density).
Those outputs are aligned on a 4× storage grid with nearest-neighbor
resampling and hard minimum-error joins. The supporting art workspace keeps
the exact prompt, source crops, generated outputs, final master and runtime
comparisons under `work/map-planning/golem-kingdom/sharpness-v1/`. Only visible
surfaces receive restored RGB; hidden reconstructed terrain retains its
original RGB so that foreground objects are not painted into the ground.

## Editing

The five `TileMapLayer` nodes contain ground, lava, northern falls, natural
cavern rock, and eastern entrance light. Each uses a separate TileSet under
`Detail4x/Terrain/`. A patch is now 128 × 128 detail pixels, while its logical
footprint stays 32 × 32 source units, or 96 × 96 world pixels. Each terrain
layer has a 0.25 visual scale beneath the unchanged 3× content root. Keep
these transforms and negative Z indices aligned.

Buildings, walls, bridge parts, stairs, racks, standing stones and braziers are
individual named child nodes. Their `Artwork` sprites are offset from their
source foot anchors. Objects sort against the character at Z = 0. Decks and
stairs use a negative Z so the character can stand on them. Flames already
belong to their extracted brazier/hearth cutout; do not add the original full
flames layer again. `Artwork` sprites use the matching `Detail4x/Objects/`
texture at 0.25 scale, keeping their original offset and world footprint.

These visual transforms make each detail texel 0.75 world pixels, matching
the peasant character's 64-pixel frame displayed at 48 world pixels. The
character, camera, map size, and movement distances have not been rescaled.

Move an object's root to move its artwork and its `Footprint` collisions
together. Edit its `CollisionPolygon2D` children to adjust projected bases.
Gateway jambs have separate footprints, leaving their openings traversable.
Some touching building groups remain a single source-visible cutout.

`TerrainCollision` blocks areas outside authored walkable terraces and molten
pools. Its static rectangles use source coordinates under the same 3× content
transform. Bridge decks and stairs remain traversable. Narrow decorative
fissures and reflected orange light do not partition walkable flagstones.
Painting a new floor patch does not automatically update these authored
terrain barriers.

The package's reconstructed hidden terrain sits beneath extracted objects.
Moving them can expose reconstructed ground or missing surfaces originally
hidden in the approved flattened image.

## Crisp environment rendering

`Rendering/CrispEnvironment.tres` is one shared material on the five terrain
layers and 249 `Artwork` sprites. Actors, UI and collision nodes are excluded.
It removes subtle surface grain, tightens existing high-contrast joints and
uses a balanced 512-color environment palette with a distinct black ink color.
The original detail PNGs, UV coordinates and alpha masks remain unchanged.

`Rendering/ColorLookup512.png` is nearest-sampled shader lookup data, not a
replacement map texture. `Palette512.json` records its 512 finite, distinct
colors. A gentle local contrast pass is clamped to source neighborhood values;
only high-confidence neutral dark creases receive the stronger ink treatment.
Transparent neighbors use the center color so cutout borders remain clean.
The treatment fades at minified zoom and skips the neighborhood pass when its
weight is negligible. It neither changes the camera nor rescales the player.

Keep texture reads directly in `fragment()`. Passing the built-in `TEXTURE`
sampler into a custom sampler function triggers a Godot 4.5.1 headless compiler
error; the alpha-guard helper instead receives an already-sampled `vec4`.
The supporting workspace's `sharpness-v2/` contains before/after comparisons,
palette generation, exact geometry fingerprints and the stderr-aware headless
regression command. A plain process exit code alone does not catch native
shader compiler errors.

## Entrance and bounds

The runtime scene owns its own camera, bounds, UI/combat controller, eastern
exit portal, and `SpawnPoints/EastCave` marker. The arrival marker is at world
`(3531, 1617)` on the eastern cobbled landing. The exit leads to the overworld
marker `GolemCaveReturn`; its approach is `(3606, 1518)`.

The content manifest records source-coordinate floor polygons, hazards,
landmarks, and source scale. `source-layer-manifest.json` retains the approved
12-layer and individual-object provenance. Regular Godot edits require only
saving the scene; do not regenerate over manual changes. The original layer
converter produces the original-detail scene, so do not rerun it over the
live restored scene without deliberately rebuilding the detail bindings too.

## Validation

Run `Godot --headless --path godot_client --script res://tools/golem_map_smoke.gd`
from the repository root, and confirm stderr is empty. It checks all 254 shared
material assignments, actor/UI exclusions, shader/LUT identity and settings,
nearest sampling, the runtime scene, 4× texture dimensions,
0.25 visual scales, unchanged world cell spacing and object footprints, object
and collision counts, arrival/exit coordinates, camera bounds, player-sized
clearance at all 12 gameplay landmarks, and representative lava/wall collisions.

The supporting art converter checks player-clearance connectivity between
every landmark. The original-detail GPU baseline reproduced the approved
1254 × 1254 image with zero changed pixels. The restoration deliberately
changes the source RGB detail; before/after geometry fingerprints verify that
scene layout, terrain cells, collision shapes, and runtime markers stay fixed.
