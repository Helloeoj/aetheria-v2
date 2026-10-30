# Bound Golem Titan — first animation candidates

This is the first south-facing animation batch for the crowned, red-eyed Titan with magical restraints around both lower legs. It is source artwork only: the live Titan, catalog, actor scale, collision, camera and boss mechanics are unchanged.

## Preview and source files

- `previews/idle-3x-dark.gif`: restrained idle, five playback frames, 1.32-second cycle.
- `previews/shockwave_slam-3x-dark.gif`: raised-fist windup, two-fist slam and recovery, nine playback frames, 1.71-second cycle.
- `idle/frames/` and `shockwave_slam/frames/`: corrected, lossless 256×256 RGBA frames, including exact closing poses.
- Each clip's horizontal PNG sprite sheet retains every corrected frame, including its closing pose. Use `manifest.json` for timing and playback order; the closing duplicate is omitted only from GIF playback.
- `raw/` keeps the unchanged PixelLab generation. `processed/frames.png` is the exact corrected PixelLab export. These are provenance sources, not runtime inputs.
- `source/` keeps the concept, isolated cutout and untouched native conversion. `generation.json` and `corrections.json` record generation and exact pixel-layer repairs.

## Candidate geometry and review

Native canvas: 256×256. Foot anchor: [128,240]. Candidate density: one world pixel per source pixel. Visible source extent: [7,23,244,241), approximately 218 world pixels tall at that density. This is a source-art proposal, not a changed actor scale or collision contract.

Frame checks passed for both corrected clips: consistent RGBA dimensions, binary alpha, no visible pixels at canvas edges, identical first/last pose, fixed foot-contact pixels and ground seals. PNG sprite-sheet extraction reproduces the source frames exactly. The idle's full lower-body layer stays fixed. Slam hands pass in front of the bindings, so hand occlusion is excluded from the fixed-foot/ground-seal comparison.

Every frame was inspected in contact sheets; the native lower-body joins were also inspected at nearest 4×. The motion is an early candidate: arm-to-binding overlap and impact timing remain subject to artwork review. Automatic checks do not grant visual approval.

Visual approval: pending. Runtime installation: not performed. No scene or placement contract exists for this candidate. Godot review at normal and 4× zoom, Palace framing, directional views and gameplay integration remain pending and must precede runtime acceptance. These source-only changes do not certify an installed worldbuilding scene.
