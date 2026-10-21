# Editing the Valtheiris world

Open [`scenes/ValtheirisWorldContent.tscn`](../scenes/ValtheirisWorldContent.tscn)
in Godot to paint the map. It contains the outskirts, harbor, and four approved
wilderness sections in one shared terrain and object layer stack. Grass, roads,
water, trees, and buildings remain editable across section boundaries.

The running game uses
[`scenes/EastOutskirtsLayered.tscn`](../scenes/EastOutskirtsLayered.tscn). Its
existing `PlayableMapContent` node now instances the unified world scene and
keeps its original identity and transform. The runtime scene adds the player,
camera, combat controller, and outer map boundaries.

Regular painting only requires saving the scene. You do not need to regenerate
assets or rebuild the map.

## Paint terrain

Select the relevant `TileMapLayer` in `ValtheirisWorldContent.tscn`:

| Layer | Contents | TileSet palette |
| --- | --- | --- |
| `Grass` | Grass and ground | Sources 0/1: original patches/brushes; sources 2/3: wilderness patches/brushes |
| `PathsAndQuays` | Dirt, roads, quays, and piers | Sources 0/1: original patches/brushes; sources 2/3: wilderness patches/brushes |
| `Water` | River and harbor water | Sources 0/1: original patches/brushes; sources 2/3: wilderness patches/brushes |
| `GroundDetails` | Small surface details | Source 0: original patches; source 1: wilderness patches |

These layers use 32 × 32 pixel tiles and the merged `World*.tres` TileSets in
[`Assets/Tilesets/`](../Assets/Tilesets/). Original source IDs remain unchanged;
the wilderness sources are appended to the same palettes. Sources named
**Reusable … brushes** provide 16 clean patches where available. Water brushes
include collision; ground and path brushes remain walkable.

Use the existing edge patches when shaping banks and roads. These are editable
image patches, not a terrain system with automatic edge matching. Painting a
different surface may also require erasing the previous surface from its layer.

## Paint objects

The `Trees`, `Buildings`, `Rocks`, `Props`, `Walls`, and `Boats` layers contain
whole objects as scene tiles. The new `Wheat` layer contains walkable 32 pixel
crop patches as scene tiles, with depth sorting. Layers with an `Overlap` suffix
hold objects whose anchors occupy the same grid cell as another object of that
kind.

These object layers share
[`Assets/Tilesets/WorldMapObjects.tres`](../Assets/Tilesets/WorldMapObjects.tres).
Select source 0 for original map objects or source 1 for wilderness objects in
the TileMap palette, choose an object, and paint it. Each whole-object tile
places the complete object; wheat uses smaller patches to keep the field
editable. A solid object's collision shapes move with its tile, and erasing the
tile removes those shapes.

Objects sort against the character at their feet. Trees cover the character when
the character is behind their trunk; the character draws in front after passing
below it. Keep object and actor Z indices at 0 so they remain on the same sorting
plane. The object scene's `Footprint` node provides its actual sorting position.

## Edit collision

Open an object's scene under
[`scenes/MapObjectsGenerated/`](../scenes/MapObjectsGenerated/) for original
objects, or [`scenes/WildernessObjectsGenerated/`](../scenes/WildernessObjectsGenerated/)
for wilderness objects. Adjust the `CollisionShape2D` or `CollisionPolygon2D`
children of `Footprint`. Saving that scene updates every placement of that object
tile. To make one placement unique, create a separate object scene and scene
tile before changing its shapes. Wheat patches remain walkable.

Water collision belongs to the `Water` layer's TileSet, under
[`Assets/Tilesets/World02_Water.tres`](../Assets/Tilesets/World02_Water.tres).
Edit its tile physics polygons when
changing a shoreline patch or a water brush. Those polygons follow the painted
water tiles. Outer world boundaries are separate nodes in
`EastOutskirtsLayered.tscn`.

### Your original collision work

The original 25 authored rectangle and circle shapes were transferred with their
exact positions and dimensions into the corresponding object tiles. The original
water polygon was clipped along tile boundaries without changing its outline.
The original outskirts artwork remains in its original coordinates.

[`scenes/PlayableMapContent.tscn`](../scenes/PlayableMapContent.tscn) remains the
original outskirts and harbor reference. Its TileSets and generated object
scenes are retained. Paint the unified world scene for ongoing map edits.

[`scenes/EastOutskirtsBlockout.tscn`](../scenes/EastOutskirtsBlockout.tscn)
remains unchanged as the source reference. Its
`CollisionGeometry` instance in the runtime scene is hidden and disabled because
the editable tiles now supply those collisions. Make future gameplay collision
edits in the object scenes or water TileSet; editing the disabled blockout does
not update the running map automatically.

## Section layout and source layers

All existing map coordinates and authored collision coordinates remain fixed.
The world extends north and west from the original map:

| Section | Contents | World origin | Editable size |
| --- | --- | --- | --- |
| 01 | Riverside royal road | `(0, -1536)` | `1536 × 1536` |
| 02 | Woodland transition | `(0, -3072)` | `1536 × 1536` |
| 03 | Farm and wheat field | `(-1536, -1536)` | `1536 × 1536` |
| 04 | Roadside tavern | `(-1536, -3072)` | `1536 × 1536` |

The runtime world origin is `(-1536, -3072)` and its bounding size is
`3072 × 5728`. The playable land has an L shape: the unbuilt southwest below
`y = 0` is blocked. The existing camera follows the character, and mouse-wheel
zoom remains available. At the inside corner, a wide view may include some
unbuilt space.

The approved artwork was also separated into **32 transparent source PNGs**:
eight aligned `1254 × 1254` layers per section. Each section folder contains
grass, paths, water, ground details, buildings, rocks, trees, and wheat:

- [`Assets/MapLayers/Wilderness/Section01/`](../Assets/MapLayers/Wilderness/Section01/)
- [`Assets/MapLayers/Wilderness/Section02/`](../Assets/MapLayers/Wilderness/Section02/)
- [`Assets/MapLayers/Wilderness/Section03/`](../Assets/MapLayers/Wilderness/Section03/)
- [`Assets/MapLayers/Wilderness/Section04/`](../Assets/MapLayers/Wilderness/Section04/)

These PNGs retain the original concept-art separation for reference. They are
not the final polished gameplay assets. The running map uses the shared terrain
TileMapLayers and individual object scenes.

### Wilderness polish

The wilderness uses native-scale grass, dirt and water samples from the original
outskirts palette across all four sections. Texture quilting hides patch joins
without stretching the artwork. The road and shoreline masks are continuous
across section boundaries. Grass is opaque beneath the terrain and objects.

All 149 wilderness trees and 26 wilderness rocks use complete original-style
sprites under `Assets/MapTiles/Wilderness/PolishedObjects/`. Their cells, feet
and collision shapes retain their positions. Building roof fringes were cleaned;
the farm, wheat field and tavern keep their approved layout. Small grass and
flower details use complete source sprites, with no cut canopy fragments.

Four original trees cropped at the old northern edge use completed visual
variants under `scenes/MapObjectsPolished/` in the unified world only. Their
original Footprint transforms and collision resources are retained. The original
reference scene and its object files remain available. A native tower-crown cap
adds the missing northern wall artwork and collision above `y = 0`.

The active terrain PNGs are `Grass.png`, `Paths.png`, `Water.png` and
`GroundDetails.png` under `Assets/MapTiles/Wilderness/`. Each is an aligned
3072 × 3072 atlas divided into editable 32-pixel tiles. Their brush atlases and
the scene tiles remain available in the unified world's TileSets.

## Tree artwork cleanup

The reused tree family now comes from six transparent sprites in
`Assets/MapTiles/CleanTrees/`, registered with their original canvas dimensions
and root anchors in `manifest.json`. The runtime PNG paths are retained, so
cleaning their leaf contours and removing baked ground fringes does not move
painted objects, colliders, or sorting feet. Damaged original/harbor tree groups
also have reviewed whole-tree replacements. Complete original trees without
visible extraction defects retain their existing artwork.

Tree cast shadows are omitted. The original grass atlas has also been cleaned
where it contained baked tree silhouettes and trunk remnants; its alpha outline
is retained. Ground and tree changes remain image assets in the existing shared
layers.

`Assets/MapTiles/CleanTrees/overrides.json` retains the reviewed PNG copies.
The original-map asset builder reapplies these after checking its archival
source reconstruction. Wilderness polish reads the six clean masters directly
and keeps their full canvas and anchors. These hooks are for deliberate source
rebuilds; regular map painting still requires only saving the scene.

## Limits of the source artwork

The source was flattened artwork, so some forest sections, walls, and prop
clusters remain grouped. The three original tree pairs with separate authored
trunks have been split so each tree sorts at its own trunk. Other connected
groups still move and sort together.

The original outskirts and harbor terrain backing has been filled beneath
extracted objects. Moving those original objects can still
expose details or reveal missing parts of an object that were hidden in the
flattened source; those areas may need manual art or terrain touchups. Existing
art patches do not become a fully modular or automatically tiling art set merely
by being placed in a TileSet.

## Rebuilding generated content

**Back up manual map edits before running generators or the world merge.**

- Repository tool `tools/build_map_assets.cjs` rebuilds the extracted images and
  map manifest from the source artwork and blockout reference.
- Godot tool `tools/build_playable_map.gd` rebuilds `PlayableMapContent.tscn`, its
  TileSets, and the generated object scenes from that manifest.
- Repository tool [`tools/build_wilderness_assets.cjs`](../../tools/build_wilderness_assets.cjs)
  rebuilds the polished wilderness terrain atlases, complete object images and
  manifest using `tools/polish_wilderness_assets.cjs`. Its portable layout and
  masks live in `art_sources/wilderness-v1/polish-layout/`. It samples original
  map textures without modifying them. Optional `--output-dir PATH` selects
  the preview/report directory. `--legacy-extraction` explicitly selects the
  older concept-art cutout pipeline, which is retained for archival exports.
- Godot tool [`tools/build_wilderness_map.gd`](../tools/build_wilderness_map.gd)
  rebuilds `WildernessMapContent.tscn`, its TileSets, and wilderness object scenes.
- Godot tool [`tools/merge_wilderness_into_world.gd`](../tools/merge_wilderness_into_world.gd)
  copies the original and wilderness cells into `ValtheirisWorldContent.tscn`
  and writes the merged `World*.tres` TileSets. It leaves the source map scenes
  intact.

Rebuilding can overwrite painted map cells and edited generated resources. Use
these tools only when intentionally rebuilding the source conversion. Continue
normal map development directly in `ValtheirisWorldContent.tscn` without
rerunning them. Saving normal painting does not require regeneration.

When deliberately rebuilding, run the asset generator first, let Godot import
the changed PNGs (`--headless --editor --quit`), then run the wilderness builder
and world merge in that order. Rendering before the import finishes can show
stale textures from the previous build.
