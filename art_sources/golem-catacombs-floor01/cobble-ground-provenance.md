# Cobble ground material candidate

- Method: one built-in image_gen call, opaque output.
- Request: one 1024 × 1024 seamless irregular cobble material, using the approved Catacombs floor overview as material/style reference only.
- Exact prompt: `cobble-ground-prompt.txt`.
- Input reference: approved 1422 × 1106 Catacombs overview, also preserved here as `overview-approved.png`.
- Generation output identifier: `exec-2eefd5c3-10e0-4726-b573-09a20981c238.png`.
- Selected unmodified output: `cobble-ground.png`.
- Actual measured dimensions: **1254 × 1254**, despite the prompt requesting 1024 × 1024. No resizing or post-processing applied.
- Alpha: fully opaque at every pixel.
- Visual review: crisp irregular warm tan and muted gray cobbles, no props/actors/lava, no obvious straight grid rows or cross-jointed brick lattice. Cobble scale is broader than the requested 8–16 pixels, with many stones about 15–45 pixels across. Gray stone groups are more extensive than the requested small sparse patches.
- Repeat review: the 2×2 preview avoids the conspicuous small quilt pattern of the earlier 128-square crops, but opposite texture edges do **not** strictly match individual stone shapes. Unmodified repeated placement has abrupt cut stones at tile boundaries and should not be called intrinsically seamless.
- Raw seam check: horizontal/vertical wrap mean absolute RGB differences 26.913 / 27.015; normal internal adjacent-pixel differences 10.224 / 10.851 (ratios 2.632 / 2.490). Raw validation evidence is retained in the supporting workspace.
- Status: material candidate for parent integration with boundary handling or non-repeating mapping; not yet approved or installed by this subtask.
- One call only, as authorized; no further generation performed.

Supporting review images: `work/map-planning/golem-catacombs/floor01-v5-worldscale/pillar-removal/cobble-ground-repeat-preview.png` and `cobble-ground-wrap-center-preview.png` in the supporting workspace.

## Installed derivation

The builder preserves this raw source, reduces it to627×627 with exact half-size
nearest sampling to bring the stones to character scale, then makes a512×512
periodic atlas using native-pixel minimum-error overlap cuts. It uses the extra
115 pixels in each axis as the continuation across each repeat boundary.
No enlarged overview texture is used for gameplay. The runtime atlas has nearest
filtering, no mipmaps, lossless import and the existing Golem Kingdom crisp
rendering material. The source remains unmodified for future local repairs.
