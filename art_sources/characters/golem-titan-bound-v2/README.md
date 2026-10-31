# Bound Titan — chest and arm idle, grounded slam candidates

The user selected subtle chest and arm movement. The selected idle now uses anatomical waist and shoulder joints while keeping the pelvis, legs and magical bindings fixed. The previous generated breathing tests deformed the legs and ended on a different pose; those tests are not selected. These candidates share one complete neutral pose across idle, attack start and recovery. No production actor, map, collision, camera or gameplay data is changed.

## Current clips

- **Idle:** 12 native frames, 2.4-second cycle. The chest, head and shoulder plates rise by up to two source pixels. Both complete arms rotate subtly around their shoulders, carrying every elbow, wrist and knuckle together. Native nearest sampling preserves the source palette. Original source underlap exists only at the actual waist and shoulder joints. The pelvis, knees, feet, leg bindings and ground anchors remain pixel-exact across the cycle. First and last frames match the complete neutral pose exactly. User artwork approval remains pending.
- **Ground slam:** 18 complete frames, 2.31-second preview cycle. The upper body hinges forward and both complete fists reach the floor. No horizontal body strips, frozen knees or partially reused hands. Only measured opaque terrain-mat colors beneath the contact poses were removed from alpha; the articulated body poses remain intact.

Each clip has lossless `frames/*.png`, a horizontal PNG sprite sheet, a service `final-export.png` sheet and preview GIFs. `south.png` is the shared neutral pose. `animation-source.json` records the selected joint motion, whole slam frame selection and bounded cleanup operations. It retains the unselected rigid core-pulse alternative separately. Unmodified temporal generation sources are under `shockwave_slam/temporal_strike/raw` and `temporal_recovery/raw`. Rejected experiments are retained locally for comparison, not selected for playback.

`idle/joint-rig.json` is the exact normalized PixelLab drawing recipe, including source-part ownership, protected areas, underlap, pivots and motion tracks. `idle/rig/full.png` and `layers.npz` retain its exported sheet and editable layer source. Blue/white binding pixels and the adjacent original shadow pixel at [64, 196] belong to the fixed restraints, rather than a moving fist.

## Review evidence and limits

Native canvas: 256 × 256; candidate density: 1 world pixel/source pixel; anchor: [128, 240]. The floor contact pose is checked against the unchanged Golem Kingdom paving and the actual peasant player at its unchanged 0.75 scale.

The dedicated review tool instantiates the actual content scene and candidate actor in memory. It samples the real floor/collision geometry for the temporary review position and captures every frame through an actual GPU Camera2D at zoom 1 and 4, plus normal 0.68 samples. No characters are baked into a map image. No production placement/collision acceptance is inferred from these screenshots or a proposed review footprint.

The selected joint idle has 29 actual GPU captures with zero capture failures: all 12 poses at Camera2D zoom 1 and 4, plus context/guide captures. All 12 actual 4× poses were inspected for complete fists, wrist and shoulder joins, waist overlap, stationary knees/restraints and map clipping. No detached outline seam, knee shear or exposed waist cut was observed. Native checks confirm fixed lower-body/anchor pixels, one connected silhouette per idle frame, matching neutral endpoints and lossless PNG-sheet round trips. Lossless animated WebP playback reproduces the actual Godot images and their durations exactly; identical consecutive poses may be combined by the encoder.

The grounded slam retains its prior actual-map review from the 62-capture run. Both clips have clean canvas margins and share identical complete neutral endpoints.

Evidence is outside Git under the supporting `work/character-animation/golem-titan-bound-v2/evidence` folder: `godot-joint-idle` contains the selected idle renders, inspection and animated-preview QA; `godot-rigid-idle-ground-slam` contains the retained slam renders and animation. Earlier rigid-idle imagery is an unselected alternative. User artwork approval remains pending. Source candidates are not installed in the live catalog; gameplay, final Palace placement, collision bases and runtime acceptance remain pending.

Run the review from the active project with `res://scripts/dev_tools/golem_titan_animation_review.gd` and user arguments `--social-no-auto --asset-dir=<absolute candidate directory> --output=<absolute outside-repository evidence directory>`. Add `--clip=idle` to review only the selected idle.
