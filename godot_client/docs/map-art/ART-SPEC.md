# Compact art specification — v1

Recorded 2026-10-20 from current project assets and editing documentation. Existing reference artwork is authoritative; sampled colors below are guides, not a newly imposed limited palette.

## Shared rules

Environment only. Never bake in characters, creatures, NPCs, enemies, golems, animals or character sprites. Actors are added separately in code.

Detailed top-down fantasy game art with crisp small pixel clusters and readable shapes. Match the selected area's camera and light; do not mix oblique/isometric assets into it. No blur, stretched texture, new zoom, visible grid, labels or editor decorations. Preserve dimensions, alpha, placement, foot anchors, collision, portals and paths outside the task's explicit scope.

Terrain and objects are separate. Transparent props contain complete silhouettes and internal shading, without grass/soil mats, neighboring fragments or baked ground shadows. Review on light/dark backgrounds and the actual ground. Never remove a background by globally deleting green pixels.

Maximum-zoom acceptance: all images, objects and props must remain as crisp as the player character at the maximum 4x camera zoom. Keep native pixel clusters and source alpha, use nearest texture filtering with lossless import and no mipmaps, and avoid blurred source art, smooth enlargement or linear-filter overrides. Verify a real saved Godot render at Camera2D zoom 4x alongside the character; a source PNG or editor import alone does not prove runtime clarity. Preserve intentional area materials unless their appearance is explicitly in scope.

Ore design authority: the copper and tin full/depleted sprites in `art_sources/ore-nodes/` were visually approved by the user on 2026-10-26. The copper node was initially bronze-labeled; the user corrected that bronze is smelted from copper plus tin and is not mined. All subsequent ore and catalyst nodes must match that south-facing low top-down rock design, pixel detail, upper-left light and transparent complete silhouette. Reuse the matching depleted host rock when only the mineral color changes; retain distinct approval and runtime-installation statuses.

Scope: sprite generation and material-naming discussions authorize artwork, not mining skill behavior, progression, drops, item/catalog definitions, smelting recipes or world placement. Obtain explicit gameplay requirements before changing those systems. The Blackstone catalyst is an art concept here; no associated recipe or mining behavior is implemented by this sprite task.

## Profile: valtheiris-overworld

Canonical ore props: use `res://scenes/MapProps/OreNodes/` and source 2 of
`res://Assets/Tilesets/WorldMapObjects.tres` whenever an ore node is requested.
`res://Assets/Tilesets/OreNodes.tres` supplies the same named props on new maps.
All ten ores now share the same host-rock shape, anchor (48,72), depleted sprite
and physical base; only mineral streak colors differ, including revised Tin.
Use 96px/three-cell centers in compact clusters and 128px/four-cell spacing at
walking routes. See `docs/OreNodes.md` and the runtime manifest. This installs
a placeable library; it does not add world placements or mining skill behavior.

Ore placement: keep nodes against room boundaries. Room centers, entrances and
main walking routes must stay clear; retain reachable approaches from the room.
User-annotated ore dots/colors override generic spacing and prop snapping; only
conflicted nodes may move minimally. Verify full visible silhouettes against
walls and other props, physical bases and shared-grid approaches. Base-only
clearance is insufficient. Preserve the movement grid when matching marked art.

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
