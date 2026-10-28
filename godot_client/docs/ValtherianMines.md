# Valtherian Mines

The playable map uses the exact approved V3 image the user marked with ore dots. The modular reconstruction was rejected. Preserve the approved room outlines, stone, lighting, lanterns, crystals and floor. New artwork generation is PixelLab-only; this restoration uses existing files without generation calls.

`scenes/ValtherianMinesContent.tscn` contains `ApprovedMap`, exact-pixel foreground wall bands, actual painted-floor collision and individual `Ores` instances. `scenes/ValtherianMines.tscn` supplies the existing player/UI, arrival and generic exit. The backdrop source is `Assets/Maps/ValtherianMines/Approved/approved-map-v3.png`: the original1703x924 PNG, unchanged. Its registration covers6144x3328world pixels. The movement grid remains32px, origin(0,0), with the real24px body. Artwork cells and visible room shapes are independent of that movement grid.

The preserved annotation and measured registration are under `art_sources/valtherian-mines/` and runtime `ore-markers.json`. The29 nodes are12Blackstone,7Coal,4Mithril,2Adamantite,4Iron. Grey is Coal. Dots specify visible sprite centers, and user-marked positions override default snapping. Reuse `scenes/MapProps/OreNodes/` and the existing `Assets/Tilesets/OreNodes.tres`; keep96px native sources, scale1 and anchor(48,72). Only genuine wall/peer conflicts permit a documented minimal shift.

The existing east-facing mine entrance remains atworld(320,-1), with east approach(368,16) and overworld return(400,16). Arrival/exit approach inside is(6032,2064). The passive entrance is in `ValtheirisWorldContent.tscn`; `EastOutskirtsLayered.tscn` owns the artless interaction. Bracken/Golem/Tavern portals remain intact.

Use the authored approved-image geometry and `scripts/dev_tools/build_valtherian_content.gd` to export the actual scene. `scripts/dev_tools/valtherian_approved_layers.gd` copies exact source pixels for foreground ordering. Run the actual worldbuilding contract plus approved-image physics/travel checks. `scripts/dev_tools/valtherian_approved_review.gd` captures source identity, marked ore placement and actual1x/4x player views. Full reports and captures stay outside Git in the supporting `approved-restoration/` evidence folder.

The complete original remains unchanged beneath foreground overlays, and a source-resolution GPU capture must match all original RGB pixels. This verifies preservation, without claiming extra detail beyond the existing source resolution. Automatic tests do not substitute for the user's visual approval. Earlier modular-scene reports are historical and cannot certify this restoration.

The map adds no mining/combat rules, recipes, progression, monster populations or reward changes. Online travel still requires an updated server region registry; local tests do not deploy servers or exercise live account persistence.
