# Valtherian Mines: approved-image restoration

The user explicitly requested the exact map they painted with dots on2026-10-28. The replacement modular floor/wall assembly is rejected and disabled. New map/environment generation must use PixelLab; this correction reuses existing files and makes no image-generation or service calls.

Visual authority: `unapproved/whole-map-v3.png`, native1703x924, SHA2568ddfeb0018110c36f3937592a09b378f61b9122d1d2f761eb4f6931dffedea90. The historical folder name is preserved. Runtime `Assets/Maps/ValtherianMines/Approved/approved-map-v3.png` is byte-identical. Keep the original room outlines, walls, lanterns, floor, crystals, lighting and dark background. Godot renders the approved source without actors at its original sampling with0changedRGBpixels.

The existing registration maps that exact image to6144x3328world pixels and the same hidden32px movement grid. It removes the painted screenshot's border/crop/watermark. User artwork coordinates control placement; the movement grid does not redraw or square off the image. Original image resolution is retained; no new high-resolution detail is claimed.

Exactly29 canonical ore props remain separate:12Blackstone,7Coal,4Mithril,2Adamantite,4Iron. Grey means Coal. The original annotation is `approved/user-ore-annotation-2026-10-28.png`; registered targets are in runtime `ore-markers.json`. Move only genuine wall/peer conflicts minimally. Preserve the canonical96px art and anchors.

Collision follows the reviewed painted floor. Foreground walls use exact source-pixel overlays with floor-side sorting anchors; the complete original stays underneath. No hidden floor or new wall art is invented. Exact source-pixel equality, ore/full-silhouette clearance, actual24px body/shared32px grid, paths, portal travel and real4x renders require separate verification.

The existing east-facing PixelLab entrance and ordinary scene travel are retained. No mining rules, progression, recipes, rewards, enemies, interfaces or saved-character behavior changes.

Current implementation: `godot_client/scenes/ValtherianMinesContent.tscn`. Contracts: `godot_client/Assets/Maps/ValtherianMines/`. Historical rejected implementation/checks: `rejected-native-assembly.md` and earlier commits. Restoration evidence stays outside Git under the supporting task's `approved-restoration/` folder.

Restoration validation:0changed background RGB pixels;29nodes with0moves;2,077actualphysics checks and821worldbuilding checks pass;154travel checks pass. All3,470physically clear grid centers connect. Original artwork resolution is preserved; no new high-resolution detail is claimed at4x. New-generation and PixelLab service calls for this correction:0.
