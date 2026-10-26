# Bronze and tin ore nodes

Four source PNGs generated with PixelLab Pro Flash for Aetheria on 2026-10-26.

| Ore | Full | Depleted |
| --- | --- | --- |
| Bronze | `bronze-ore-full-south.png` | `bronze-ore-depleted-south.png` |
| Tin | `tin-ore-full-south.png` | `tin-ore-depleted-south.png` |

All canvases are native 96 x 96 RGBA with true transparent backgrounds and one south-facing low top-down view. The existing overworld rock `godot_client/Assets/MapTiles/Objects/Outskirts_Rocks_015.png` guided the pixel detail, camera, materials and upper-left lighting. Each depleted image was edited from its corresponding full image, with matching visible bounds and no resampling.

These are candidate source assets; user visual approval is pending. They are saved here for reuse and are not connected to a runtime scene. No mining logic, controls, collision or existing artwork was changed. A future placement task must author a reviewed foot anchor and collision; the 96-pixel canvas does not set the gameplay footprint. Use nearest filtering and retain the native canvas/alpha.

`provenance.json` records the complete prompts, seeds, reference, generation settings, source IDs and downloads. Technical checks verified four 96 x 96 RGBA PNGs, binary alpha, transparent borders and matching full/depleted bounds per ore. Visual review used light, dark and current overworld grass backgrounds. Review images and machine-specific evidence stay in the supporting workspace.

The separate PixelLab world-library generation hold remains unchanged.
