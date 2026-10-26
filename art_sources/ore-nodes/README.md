# Ore node source sprites

Twenty native96x96 RGBA source PNGs: a full and depleted state for each of ten south-facing low top-down ore/catalyst designs.

| Sprite | Full | Depleted |
| --- | --- | --- |
| Copper | `copper-ore-full-south.png` | `copper-ore-depleted-south.png` |
| Tin | `tin-ore-full-south.png` | `tin-ore-depleted-south.png` |
| Iron | `iron-ore-full-south.png` | `iron-ore-depleted-south.png` |
| Coal | `coal-full-south.png` | `coal-depleted-south.png` |
| Silver | `silver-ore-full-south.png` | `silver-ore-depleted-south.png` |
| Gold | `gold-ore-full-south.png` | `gold-ore-depleted-south.png` |
| Mithril | `mithril-ore-full-south.png` | `mithril-ore-depleted-south.png` |
| Adamantite | `adamantite-ore-full-south.png` | `adamantite-ore-depleted-south.png` |
| Runite | `runite-ore-full-south.png` | `runite-ore-depleted-south.png` |
| Blackstone catalyst | `blackstone-full-south.png` | `blackstone-depleted-south.png` |

The user approved the original artwork on2026-10-26, then corrected its initially bronze-labeled warm node to Copper: bronze is smelted from copper and tin and is not mined. The original pixels and generation prompts remain unchanged; only sprite filenames and labels were corrected. The eight additional designs remain candidates for user visual review. Blackstone is the user's catalyst art concept.

This is a sprite task only. No mining skill mechanics, progression, drops, interaction behavior, item/catalog definitions, smelting recipes or world placements were implemented. Gameplay changes explored during the task were removed after the user's explicit scope correction. Future implementation requires the user's gameplay requirements; art/material discussions do not authorize it.

PixelLab Pro Flash made the original four sprites. With PixelLab's AI allowance exhausted, the eight new full sprites were made in PixelLab's free exact pixel editor from the approved copper host rock. Only25 mineral colors (493pixels per image) change; all other stone pixels, the silhouette, native grid and alpha remain exact. Each matching depleted variant reuses the approved copper depleted image. `provenance.json` preserves original prompts/settings and naming history; `expansion-provenance.json` preserves the exact pixel-editor operations and service results.

All sprites/objects/props must stay as crisp as the character at maximum Camera2D4x zoom. The only runtime setting changed by this task is the requested nearest-filter default, matching the actor's existing filter. Keep native canvases, lossless import, no mipmaps and nearest filtering. Real Godot4.5.1 GPU checks verified all20 PNGs at4x against explicit nearest references and the current peasant frame: zero differing pixels, zero nonuniform source-pixel blocks, exact opaque source RGB colors. This contained image/filter test does not assert that every existing world material or placement was tested.

Source approval, runtime installation and physical footprint remain separate. No sprite is bound to a mining scene here; author reviewed anchors/collision only when placement is requested. Machine-specific render/validation evidence remains in the supporting workspace. The separate PixelLab world-library generation hold is unchanged.
