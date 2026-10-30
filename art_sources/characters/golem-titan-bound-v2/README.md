# Bound Titan — rigid idle and grounded slam candidates

The previous body-breathing tests were rejected: they expanded the legs, and the generated final pose did not match the original first pose. These candidates share one complete neutral pose across idle, attack start and recovery. No production actor, map, collision, camera or gameplay data is changed.

## Current clips

- **Idle option:** rigid stone body with a chest-core light pulse. Nine native frames, 1.8-second cycle. Every alpha pixel and every pixel outside the core is identical; legs, pelvis, full hands, knees and magical bindings cannot deform. First and last frames match exactly. This is an assistant-prepared alternative awaiting user preference/artwork approval, not claimed as approved breathing.
- **Ground slam:** 18 complete frames, 2.31-second preview cycle. The upper body hinges forward and both complete fists reach the floor. No horizontal body strips, frozen knees or partially reused hands. Only measured opaque terrain-mat colors beneath the contact poses were removed from alpha; the articulated body poses remain intact.

Each clip has lossless `frames/*.png`, a horizontal PNG sprite sheet, a service `final-export.png` sheet and preview GIFs. `south.png` is the shared neutral pose. `animation-source.json` records whole-frame selection, exact generation settings and bounded pixel/color operations. Unmodified temporal generation sources are under `shockwave_slam/temporal_strike/raw` and `temporal_recovery/raw`. Rejected breathing/rig experiments are retained locally for comparison, not selected for playback.

## Review evidence and limits

Native canvas: 256 × 256; candidate density: 1 world pixel/source pixel; anchor: [128, 240]. The floor contact pose is checked against the unchanged Golem Kingdom paving and the actual peasant player at its unchanged 0.75 scale.

The dedicated review tool instantiates the actual content scene and candidate actor in memory. It samples the real floor/collision geometry for the temporary review position and captures every frame through an actual GPU Camera2D at zoom 1 and 4, plus normal 0.68 samples. No characters are baked into a map image. No production placement/collision acceptance is inferred from these screenshots or a proposed review footprint.

Final review run: 62 actual GPU captures, no reported capture failures. Both whole clips have clean canvas margins, complete hands in the reviewed poses and exact matching neutral endpoints. The idle has zero physical-body pixel movement. The first/last idle and slam frames share the same neutral image, removing the previous source-pose loop boundary. Lossless animated WebP evidence matches each actual Godot PNG exactly.

Evidence is outside Git in the supporting `work/character-animation/golem-titan-bound-v2/evidence/godot-rigid-idle-ground-slam` folder, including the actual map/player animations and per-frame 1×/4× renders. Earlier rejected research captures are separate. User artwork approval remains pending. Source candidates are not installed in the live catalog; gameplay, final Palace placement, collision bases and runtime acceptance remain pending.

Run the review from the active project with `res://scripts/dev_tools/golem_titan_animation_review.gd` and user arguments `--social-no-auto --asset-dir=<absolute candidate directory> --output=<absolute outside-repository evidence directory>`.
