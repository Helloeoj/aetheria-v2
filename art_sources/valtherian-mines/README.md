# Valtherian Mines

The user approved the larger V3 progression layout and the native material proof on 2026-10-28, then supplied 29 ore dots. Grey means Coal (the charcoal label was a typo). The final area uses a long east-to-west route, five branches, eight large chambers and its own east-facing entrance beside the Valtheiris wall.

The native runtime assembly is in `godot_client/scenes/ValtherianMinesContent.tscn`; the playable wrapper is `ValtherianMines.tscn`. It preserves the shared 32px gameplay grid, all 5,498 authored floor cells, 192px main corridors and 128px branches. The original player and canonical 96px ore props retain their scale. No mining/combat rules, recipes, rewards or monster populations are added.

## Sources and reusable assets

- V3 layout reference: `unapproved/whole-map-v3.png`, retained at its original 1703x924 resolution. Its historical folder name is preserved. The enlarged overview FAILED actual 4x review and is never runtime terrain.
- Physical layout authority: `planning/tile-layout-v3.json`, 192x104 gameplay cells and 6144x3328 world pixels.
- Approved native material: `godot_client/Assets/Maps/ValtherianMines/Proofs/material-section-v1.png`, untouched 1536x1024 source. Sixty complete 128px floor regions at 0.25 density produce 32px physical cells. Floor-only mirrored macro repetition preserves matching edge texels.
- Complete wall props: `native-walls/` preserves original built-in imagegen sheets, exact prompts, export recipe and PixelLab cleanup decisions. Six whole native objects at 0.125 density, with no resampling/recoloring. PixelLab removed observed alpha1-127 background matte; all foreground RGBA128-255 remains unchanged.
- Complete timber/lantern support: `native-walls/timber-lantern-v1.*`, native 1254x1254 at 0.0625 density, anchor(864,1200). Four native processing quadrants were cleaned with PixelLab's free masked eraser then rejoined at exact coordinates. ForegroundRGBA128-255 changed 0 pixels; the final object is one complete connected silhouette. Eight supports mount against actual back walls.
- Runtime assets/contracts: `godot_client/Assets/Maps/ValtherianMines/`. Reusable scenes: `godot_client/scenes/MapProps/ValtherianMines/`. Editor palette: `godot_client/Assets/Tilesets/ValtherianMinesWalls.tres`. Rock/support visuals use feet sorting; continuous CaveBoundary owns their solid footprint.
- Entrance: untouched native 256x192 PixelLab source, east-facing, anchor (147,139), world (320,-1). Its exact east approach is (368,16), return (400,16). Existing Bracken/Golem/Tavern portals remain unchanged by this task.
- User marker authority: `approved/user-ore-annotation-2026-10-28.png`; registered positions and precise color/scene bindings: `godot_client/Assets/Maps/ValtherianMines/ore-markers.json`. Exactly 12 Blackstone, 7 Coal, 4 Mithril, 2 Adamantite, 4 Iron. All 29 rounded targets fit unchanged; 0 nudges. All 406 ore pairs clear 4px, full silhouettes clear floor/wall/decor by 2px. Screenshot crop/border is removed by measured affine registration; no naive full-image stretch.

## Validation and acceptance

The actual scene worldbuilding contract is `Assets/Maps/ValtherianMines/worldbuilding.json`: 12 native asset types and 14,337 geometry/visual/anchor/route checks pass. The validator compares shared resource pixels once per audit but still checks every instance's scale, anchor, visibility and nearest filtering. Exact reserved lane polygons retain their full width; physics uses a recorded 0.1px per-side numerical interior only. Ordinary 24px actor queries are unchanged. All four validator self-test groups pass.

The independent actual-physics harness classifies every floor cell, accounts for 103 centers occupied by canonical ores, checks all5,395 clear centers reachable, blocks14,470 void centers, checks all 29 approaches and protects progression/branches. Focused geometry helpers have 8 tests. Offline and authoritative travel pass 154 checks with 67 actual map probes, including all 29 exact ore approaches; existing Bracken travel passes 58 checks. Live online servers need the updated registry build before admitting the new region.

The final review inspected66 actual normal GPU captures and7 actual physical overlays, including ore approaches and the last legal south-floor row. No wall/peer cut-ins or floor-edge gaps were found. Source approval, automatic checks, agent visual review and local installation are separate statuses in `manifest.json` and `acceptance.json`. Generated reports and real 1x/4x screenshots remain outside Git in the supporting task. The native material remains grainier than the player, and modular repetition is visible over large spans; nearest filtering is not represented as repairing soft source artwork. The old rejected overview is retained only as layout/history evidence.

See `godot_client/docs/ValtherianMines.md` for scene structure, rebuild commands and reusable placement conventions. Exact built-in prompts and PixelLab edit IDs are preserved alongside source assets; no PixelLab generation credits were used for the native wall/support kit.
