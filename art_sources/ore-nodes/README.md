# Canonical ore node props

The game's reusable ore library contains twenty native 96 x 96 RGBA sprites: full and depleted states for Copper, Tin, Iron, Coal, Silver, Gold, Mithril, Adamantite, Runite and Blackstone.

All ten now use **the same host-rock silhouette, stone pixels, foot anchor and depleted state**. Only the mineral streak colors distinguish the ores. Tin was revised at the user's request to match the shared shape, using dull pewter-gray streaks; the original different-shaped tin is archived under `history/` for provenance only. The initially bronze-labeled warm node was corrected to Copper because bronze is an alloy of copper and tin.

## Place the props

Open `godot_client/scenes/ValtheirisWorldContent.tscn` in Godot, select **Rocks** or **Props**, and choose **source 2 — Ore Nodes - Full and Depleted** in the TileMap palette. Choose a named ore/state and paint its complete prop. Right-click to erase, then save normally. Do not regenerate assets or run the world merger for ordinary placement.

For direct drag/drop, use the individual scenes in `godot_client/scenes/MapProps/OreNodes/`. Other maps can use `godot_client/Assets/Tilesets/OreNodes.tres`, which has the same stamps at source 0. Complete instructions: `godot_client/docs/OreNodes.md`.

Keep the 32 x 32 placement grid and native artwork scale 1. Start with 96 world pixels / three grid cells between centers in compact clusters; allow 128 pixels / four cells along walking routes. The shared image-space anchor is (48,72). Each prop includes two compact physical-base colliders, rather than a collider around the transparent canvas. Full and depleted state swaps keep the same base.

Whenever an ore node is requested, reference this library and reuse its named props. Do not paint substitute random rock clusters. The canonical runtime paths, adjacent scene IDs, anchors, footprints and spacing are recorded in `godot_client/Assets/MapTiles/OreNodes/manifest.json`. Runtime PNGs are byte-identical to the current source PNGs here.

## Pixel detail and provenance

PixelLab Pro Flash created the initial art. PixelLab's free exact pixel editor made the shared-shape mineral variants, changing only 25 mineral colors / 493 pixels in each full variant. Source alpha, silhouette, stone pixels and native grid stay unchanged. All ten depleted PNGs reuse the same approved bare host rock.

`provenance.json` preserves original generation prompts/settings and naming history. `expansion-provenance.json` records the first eight mineral edits. `tin-shared-shape-provenance.json` records the later Tin correction; archived Tin images are superseded and must not be used as current props.

Use nearest filtering, lossless imports and no mipmaps. Real Godot 4x verification uses the actual imported prop scenes alongside the current character, checks exact opaque source colors and uniform pixel blocks, and reviews ground placement. Machine-specific evidence stays in the supporting workspace.

## Scope

The user selected this family for reusable map placement. It is installed as a visual prop library with physical bases; no world nodes were placed by installation. Mining mechanics, interaction rules, skill levels, tools, drops, respawns, catalog definitions and smelting recipes remain unchanged. The separate PixelLab world-library generation hold remains in place.
