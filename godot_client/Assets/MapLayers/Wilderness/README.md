# Approved wilderness source layers

Each `Section01` through `Section04` folder contains eight transparent **1254 × 1254** PNGs on the same canvas:

- `00_Grass.png`
- `10_Paths.png`
- `20_Water.png`
- `25_GroundDetails.png`
- `30_Buildings.png`
- `40_Rocks.png`
- `50_Trees.png`
- `60_Wheat.png`

These are source-pixel cutouts of the approved section previews. Every source pixel belongs to one layer, so stacking a section's layers reconstructs its approved preview. Layers without content are transparent.

The game uses **editable 32px terrain tiles and whole-object scene tiles** in `scenes/ValtheirisWorldContent.tscn`. These source PNGs are not overlaid over the original map. The map scales sections to 1536px and adjusts their connecting edges with terrain patches while preserving existing map coordinates and collision geometry.

See `docs/MapEditing.md` for the shared layer palettes, object collisions, wheat, and rebuild instructions. Original approved previews are retained outside the Godot import folder in `art_sources/wilderness-v1/` at repository level.
