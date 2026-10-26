# Reuse index

All `res://` paths are inside `godot_client/`. This index routes to authoritative assets; it does not duplicate large cell manifests. Status describes the saved project, not a new approval of every asset.

| ID | Existing resource | Use / status |
| --- | --- | --- |
| `ow-grass` | `res://Assets/MapTiles/GrassBrushes.png` | 16 native grass patches; installed; walkable |
| `ow-paths` | `res://Assets/MapTiles/PathsAndQuaysBrushes.png` | 16 road/quay patches; installed; walkable |
| `ow-water` | `res://Assets/MapTiles/WaterBrushes.png` | 16 water patches; installed; collision is in the TileSet |
| `ow-details` | `res://Assets/MapTiles/GroundDetails.png` | Existing detail atlas; inspect a selected patch before reusing |
| `wild-brushes` | `res://Assets/MapTiles/Wilderness/{Grass,Paths,Water}Brushes.png` | Three installed 16-patch families; use matching terrain/layers |
| `clean-trees` | `res://Assets/MapTiles/CleanTrees/manifest.json` | Six clean masters with sizes and anchors; installed via existing overrides |
| `ow-rock-reference` | `res://Assets/MapTiles/Objects/Outskirts_Rocks_015.png` | Existing whole rock, 74 × 66; style reference/reusable image; obtain collision/scene anchor from its existing object scene |
| `ore-node-source-art` | `art_sources/ore-nodes/README.md` (repository-relative) | `valtheiris-overworld`; four native 96 × 96 south-facing transparent bronze/tin full/depleted PNGs; candidate source art, user visual approval pending, not installed; author anchors/collision before placement |
| `world-objects` | `res://Assets/Tilesets/WorldMapObjects.tres` | Installed whole-object scene tiles: trees, buildings, rocks, props, walls, boats and crops |
| `world-terrain` | `res://Assets/Tilesets/World00_Grass.tres`, `World01_PathsAndQuays.tres`, `World02_Water.tres`, `World03_GroundDetails.tres` | Installed merged palettes; retain existing source IDs |
| `local-review` | `res://Assets/MapTiles/ReviewSections/sections.json` | Local terrain registration; D4D5 installed candidate, visual review recorded as pending |
| `dungeon-terrain` | `res://Assets/Maps/GolemKingdom/Detail4x/Terrain/` | Installed restored terrain; dungeon scale only |
| `dungeon-objects` | `res://Assets/Maps/GolemKingdom/Detail4x/Objects/` | Installed restored cutouts; reuse via existing nodes/anchors |
| `dungeon-palette` | `res://Assets/Maps/GolemKingdom/Rendering/Palette512.json` | Existing 512-color rendering palette |
| `tavern-interior` | `res://Assets/Maps/Tavern/Interior.png`, `layout.json` | User-approved installed interior; 0.75 world pixels/source pixel, nearest sampling; native UV foreground and physical bases. See [Taverns.md](../Taverns.md) before moving furniture. |

For selected original/wilderness object metadata, parse only matching objects from `res://Assets/MapTiles/map_manifest.json` or `Wilderness/wilderness_manifest.json`. Existing scene tiles carry gameplay collision and sorting; a PNG alone does not.

## Supporting workspace references

Resolve these under `work/map-planning/` in the separate supporting workspace:

| ID | Path | Status / purpose |
| --- | --- | --- |
| `overworld-render` | `references/current-outskirts-and-harbor.png` | Existing layered-map reference; compare with a fresh local render if the scene has changed |
| `north-guide` | `references/north-forest-and-goblin-cave.png` | Accepted northern visual guide |
| `d4d5-candidate` | `zone-d4d5/after-gameplay.png`, `REVIEW.md` | Local candidate and its review record; not blanket approval for other zones |
| `world-library-plan` | `pixellab-world-library/generation-plan.json`, `ASSET-PLAN.md`, `ROAD-KIT-PLAN.md` | Planned 10 trees, 10 rocks and road configurations; not generated or installed; existing hold remains |
| `library-packager` | `pixellab-world-library/build_library.cjs`, `package_library.ps1`, `PACKAGING.md` | Existing standalone PNG packaging tools; not a Godot importer |

The old plan's road-quality reference is a temporary clipboard file: it is not a durable default reference. Use persistent artwork above, or save a replacement reference before relying on it. Historical balance and cost estimates are not current quotes.

When adding an asset family, add one index row with its profile, path, reuse limits and status. Keep the full per-asset metadata with the family, rather than growing this index into a second manifest.
