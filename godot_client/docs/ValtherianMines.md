# Valtherian Mines

The approved V3 layout is a long east-to-west dungeon with five side branches
and eight large chambers. Its separate east-facing entrance stands beside the
Valtheiris wall. The playable wrapper is `scenes/ValtherianMines.tscn`; editable
terrain, continuous rock collision and individual props live in
`scenes/ValtherianMinesContent.tscn`.

The user's annotated image is preserved in
`art_sources/valtherian-mines/approved/user-ore-annotation-2026-10-28.png`.
There are exactly 29 canonical full ore props: Blackstone 12, Coal 7, Mithril 4,
Adamantite 2 and Iron 4. Grey means Coal; the user corrected their typo.
Dots denote visible sprite centers, not collider roots. Registration removes
the screenshot border/crop before mapping to the approved layout. Actual
placements and source registration are in `Assets/Maps/ValtherianMines/ore-markers.json`.
Only a genuine wall/peer collision permits a minimal correction.

The physical grid stays 32 world pixels at origin (0,0); the world is 6144×3328.
There are 5,498 authored floor cells. Main corridors retain six cells/192px;
branches retain four cells/128px. Geometry comes from the approved tile
contract, never from artwork colors. Whole canonical ore scenes keep their
native 96px canvas, scale 1 and anchor (48,72). The unchanged player has a 24px
body and the original peasant artwork.

Native floor uses sixty complete 128px atlas regions from the clean lower
portion of the approved material source, at 0.25 world pixels/source pixel.
The floor-only mirrored 12x5 macro repeat duplicates matching edge texels;
the original PNG is unchanged. Rock props are complete native wall objects
at 0.125 density, with explicit source canvases and foot anchors in
`Assets/Maps/ValtherianMines/wall-props.json`. Eight complete timber-and-lantern supports at 0.0625 density restore the warm back-wall detail. Their source/anchor contract is in `decor-props.json`. Low foreground wall caps meet
the floor edge, and whole props sort at their feet. The continuous
`CaveBoundary` owns wall physics; wall cladding does not stack duplicate bases.

Reusable ore props remain in `scenes/MapProps/OreNodes/` and the existing
`Assets/Tilesets/OreNodes.tres` palette. Six whole wall scenes and a timber/lantern support are
in `scenes/MapProps/ValtherianMines/`; `Assets/Tilesets/ValtherianMinesWalls.tres`
provides a separate 32px editor palette without changing existing source IDs.
When moving wall cladding, also author/validate its continuous boundary.

The entrance uses untouched native 256×192 PixelLab artwork with
anchor (147,139), at world (320,-1). Its approach is east of the mouth at (368,16),
and its overworld return is (400,16). The passive prop is part of the actual
`ValtheirisWorldContent.tscn`; the generic portal in `EastOutskirtsLayered.tscn`
is artless. Interior arrival/exit approach is (6032,2064). Existing Bracken,
Golem and Tavern portals retain their locations and behavior. Online servers
must run the updated `WorldProtocol` registry before admitting the new region.

This change supplies environment, placement and ordinary scene travel. Mining
rules, rewards, progression, smelting recipes and monster populations require
their own gameplay requirements.

Rebuild the geometry with `tools/build_valtherian_map.py` using the preserved
marker record, then run Godot with `--script res://scripts/dev_tools/build_valtherian_content.gd`.
Run `tools/worldbuilding.py` against
`godot_client/Assets/Maps/ValtherianMines/worldbuilding.json`. The focused
geometry, floor-seam and travel scripts are under `scripts/dev_tools/`.
Generated reports and screenshots stay outside Git in the matching supporting
map-planning task. Source provenance and acceptance statuses are recorded in
`art_sources/valtherian-mines/`; automatic checks, agent visual review, user
source approval and local installation remain separate.
