# Valtherian Mines

The playable map retains the approved V3 layout and all 29 user-marked ore
positions. The rejected modular reconstruction is not used. The user approved
the fine-linework clarity reference and requested matching ore detail. Built-in
imagegen is permitted by the 2026-10-29 clarification; preserve generation holds
for other asset families and do not substitute generic wall/floor kits.

`scenes/ValtherianMinesContent.tscn` contains the registered backdrop, 92 foreground
depth bands, painted-floor collision and individual `Ores` instances. The original
1703×924 `Assets/Maps/ValtherianMines/Approved/approved-map-v3.png` remains unchanged
(SHA256 `8ddfeb0018110c36f3937592a09b378f61b9122d1d2f761eb4f6931dffedea90`).
The rendered restoration is `Detail/master-linework.png`, 8192×4438, covering the
same 6144×3328 world pixels at approximately 0.75 world pixels per source texel.
The original registration, 32px movement grid, 24px body, arrival, routes,
collision rectangles and ore roots/approaches are unchanged. `layout.approved_art`
records original provenance; `layout.detail_art` records the installed restoration.

The detail master restores overlapping original regions with saved affine
registration. Foreground RGB comes from that exact master, while the original
band geometry and sort feet remain unchanged. Lossless imports, nearest filtering,
no mipmaps and a map-only 64-colour lookup retain crisp detail at 4×. The player
and UI do not use this material. Native file dimensions alone are not approval:
inspect actual GPU renders for joins, wall cut-ins, contact and depth sorting.

`art_sources/valtherian-mines/detail-v1/` preserves raw generated regions, original
crops, exact prompts, the approved style reference and portable registration.
`python tools/build_valtherian_detail.py --bind` reproduces the saved master and
foreground without generation. `scripts/dev_tools/build_valtherian_content.gd`
exports the current scene and honours `detail_art`. Keep the original approved
image and annotation registration intact. Do not rerun the historical baseline
restoration as an alternative to the current detail pipeline.

The roster remains 12 Blackstone, 7 Coal, 4 Mithril, 2 Adamantite and 4 Iron.
Grey dots mean Coal. Reuse the canonical ore scenes/palette. Current art is
128×128 at Visual scale 0.75, preserving the 96px world canvas, world anchor
(48,72), root scale 1 and existing bases. Native image anchor is (64,96).
Marker coordinates, chosen roots and exact approaches are unchanged. Only a
genuine placement conflict permits a documented minimal move; this revision
moved no nodes. See `OreNodes.md` for all ten full/depleted pairs.

The east-facing overworld entrance remains at (320,-1), east approach (368,16),
return (400,16), and cave arrival/exit approach (6032,2064). The passive entrance
is in `ValtheirisWorldContent.tscn`; `EastOutskirtsLayered.tscn` owns the artless
interaction. The existing wrapper, player, interfaces and other portals remain.

Validation: run `tools/worldbuilding.py` with the actual `worldbuilding.json`,
`valtherian_mines_geometry.gd`, `valtherian_mines_travel.tscn` and the canonical
ore-library smoke. `valtherian_clarity_review.gd -- --output=<external-folder>`
captures all 29 actual 4× ore approaches, room physics views and ordinary zoom.
Historical original-source RGB checks cannot certify the deliberately restored
RGB. Instead retain original provenance, verify current source/import identity
and registration, and inspect the final renders. Reports/captures remain outside
Git under the supporting `2026-10-29-valtherian-resolution` task.

The user approved the clarity direction; final whole-map/ore artwork review and
local installation are recorded independently from automatic checks. This work
adds no mining/combat rules, recipes, progression, populations or rewards.
Git synchronization does not deploy the live server.
