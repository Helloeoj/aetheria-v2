# Compact art specification — v1

Recorded 2026-10-20 from current project assets and editing documentation. Existing reference artwork is authoritative; sampled colors below are guides, not a newly imposed limited palette.

## Shared rules

Environment only. Never bake in characters, creatures, NPCs, enemies, golems, animals or character sprites. Actors are added separately in code.

Detailed top-down fantasy game art with crisp small pixel clusters and readable shapes. Match the selected area's camera and light; do not mix oblique/isometric assets into it. No blur, stretched texture, new zoom, visible grid, labels or editor decorations. Preserve dimensions, alpha, placement, foot anchors, collision, portals and paths outside the task's explicit scope.

Terrain and objects are separate. Transparent props contain complete silhouettes and internal shading, without grass/soil mats, neighboring fragments or baked ground shadows. Review on light/dark backgrounds and the actual ground. Never remove a background by globally deleting green pixels.

## Profile: valtheiris-overworld

- Camera: match existing low top-down objects and overhead terrain; upper-left object lighting.
- Mood: peaceful royal countryside, healthy olive/yellow-green vegetation, warm tan roads, beige-gray stones, blue water; restrained clutter. Do not introduce ruins, battle damage or heavy road wear unless requested.
- Grid: 32 × 32 world-pixel terrain cells. Existing brush atlases are 256 × 64 with sixteen native cells. Whole objects have varied canvas sizes; preserve each canvas and root anchor. A terrain cell is not a requirement that every object fit in 32 pixels.
- Assembly: `res://scenes/ValtheirisWorldContent.tscn`; terrain on Grass, PathsAndQuays, Water and GroundDetails. Complete objects on the existing scene-tile layers, with feet-based depth sorting.
- Roads: paint several native cells wide. Match the reference's irregular pebbles and natural edges; avoid repeated diagonal ruts and stretched ribbons.
- Edges: current brushes/patches are not automatic terrain matching. Preserve shoreline and route masks; inspect joins explicitly.

Palette guide (most frequent fully opaque RGB values sampled directly from the named sources):

| Material | Sample colors | Reference under `res://Assets/MapTiles/` |
| --- | --- | --- |
| Grass | `#485C20` `#475D1D` `#42581D` `#3B531D` | `GrassBrushes.png` |
| Road | `#BA9A78` `#C6A886` `#C5A683` `#C3A381` | `PathsAndQuaysBrushes.png` |
| Water | `#00508F` `#004E8C` `#004F8E` `#004E8D` | `WaterBrushes.png` |
| Rock | `#A4957D` `#8A7D63` `#4F483C` `#4F483B` | `Objects/Outskirts_Rocks_015.png` |

Tree style reference: `CleanTrees/Outskirts_Trees_046.png` (177 × 184). All six clean masters and their exact anchors are in `CleanTrees/manifest.json`. Do not derive a new anchor from the bottommost opaque pixel when a reviewed anchor exists.

## Profile: golem-kingdom-detail4x

Match this dungeon's current restored art and shared crisp material. It is an independent area; do not apply overworld cell/scale assumptions.

- Logical canvas 1254 × 1254, content root scale 3, area 3762 × 3762 world pixels.
- Current restored master 5016 × 5016; terrain atlases padded to 5120 × 5120. Each 128-detail-pixel patch represents 32 source units and 96 world pixels.
- Terrain/artwork visual scale 0.25 beneath the unchanged root. Preserve these transforms, object offsets and foot anchors.
- Palette authority: `res://Assets/Maps/GolemKingdom/Rendering/Palette512.json` (512 colors); material `CrispEnvironment.tres` in that folder. Do not quantize source PNGs again merely to match the rendered palette.
- Editable content: `res://scenes/GolemKingdomContent.tscn`. Keep floor/decks/stairs on their ground draw plane. Terrain painting does not automatically update authored barriers.

Read [the dungeon asset guide](../../Assets/Maps/GolemKingdom/README.md) only for dungeon-specific implementation. For overworld details use [MapEditing.md](../MapEditing.md). The older WorldChunkSetup guide is not the current map-layout authority.

## Profile: golem-catacombs-floor01

- Independent volcanic dungeon; use the approved overview under `art_sources/golem-catacombs-floor01/` for materials and room flow. The two Great Crucible islands are removed; the northern gallery island stays.
- Native art uses0.75 world pixels per artwork pixel, nearest filtering and the existing Golem Kingdom crisp material. Each32-pixel native cell covers24 world pixels. Camera3×–4×; no fog or reveal system.
- Editable content: `res://scenes/CatacombsFloor01Content.tscn`. Ground, optional FloorDetails, VolcanicRock, Walls and individual Props remain separate. Wall bases and gateway posts collide; the ordinary floor stays clear.
- Start with the compact `manifest.json` and [GolemCatacombs.md](../GolemCatacombs.md). Read the large walkable-cell layout only when changing topology. The portable builder regenerates geometry and routes together; preserve manual edits before rebuilding.
- Only the first floor is installed. Northeast descent stays sealed until another floor is implemented. Keep all source artwork environment-only.
