# Golem Titan - finalized animation set

Approved by the user on 2026-10-31. The exact corrected idle and fluid ground slam are finalized together. The artwork is frozen from revision `95abdca9e2842e33e88d56d8cfc12dc7a91da1cc`; finalization changes approval and packaging records only.

## Approved animations

- **Idle:** live Godot Skeleton2D with 25 Bone2Ds, 11,931 mesh vertices and 22,722 triangles. The 2.4-second cycle includes independent spine, neck, shoulder, elbow and wrist motion. Both complete fists and thumbs retain their volumes. The right hand and its touching magical binding use separate UV surface vertices within one source-textured mesh. Pelvis, knees, feet, leg bindings and anchors stay fixed. Forty-eight lossless native samples at 50ms are supplied alongside the live rig.
- **Ground slam:** 18 complete frames, 2.31 seconds. The torso bends forward and both complete fists meet the paving. Contact is frame 09, beginning at 1020ms and held for 260ms. All approved slam pixels and timing are unchanged.

Both animations share `south.png` as their exact neutral pose. Native canvas: 256 x 256. Foot anchor: [128,240]. Density: one world pixel per source pixel. Use nearest filtering and no mipmaps. The original crown, red eyes, stone/gold/cyan design, perspective and leg bindings are preserved.

## Source and integration contract

`approved-release.json` records approval, timing, the native contract and SHA-256 checksums of every packaged file. `manifest.json` contains the selected clips. `animation-source.json` records the rig, generation provenance, bounded slam cleanup and superseded experiments. Selected frame PNGs, horizontal PNG sheets, final grid sheets and GIF previews are supplied for both clips. Rejected local experiments are excluded from the release.

The live rig is `godot_client/scripts/dev_tools/golem_titan_skeleton_rig.gd` (repository-relative). Its unchanged whole texture is `godot_client/Assets/Characters/GolemTitanBoundCandidate/south.png`. Place the visual at world anchor minus [128,240] and call `sample_at_seconds(t)` for the idle. The caller owns playback; the rig does not start gameplay. `set_debug_skeleton(true)` shows its actual bones. `get_rig_report()` exposes hierarchy, weights and fixed supports. The package preserves the repository paths required by the rig and review scripts.

The approved source set is ready for boss integration. The existing production sprite catalog, game scenes, collision, controls and combat behavior are unchanged. Final world placement, collision and boss mechanics are separate integration work, rather than outstanding artwork approval. The earlier review footprint does not certify final placement.

## Verification

The corrected hand regression passes, including the actual right-thumb points [182,180], [184,188] and [186,184]. It reproduced 1.548 native pixels of relative stretching before correction; final numerical spacing error is below 0.000023px. Rest UV coverage, source palette, binary alpha, connected native silhouettes, PNG-sheet round trips and exact neutral/full-cycle poses pass.

The latest review contains 105 actual GPU captures from the unchanged Golem Kingdom content, with the actual peasant player at its unchanged 0.75 visual scale. All 48 idle poses were captured at Camera2D zoom 1 and 4. Every pixel outside the right-hand neighborhood, including the approved left hand, matches the preceding revision in all 48 native and actual 4x poses. All 2,045 checked binding pixels remain exact. The approved slam retains its actual-map review and all 18 unchanged frames.

Supporting evidence stays outside Git under `work/character-animation/golem-titan-bound-v2/evidence/right-hand-repair`: `native-bake` contains native samples and structural proof; `live-map` contains the final map/player renders, wider animated hand close-ups and lossless preview QA. The slam evidence is in `evidence/godot-rigid-idle-ground-slam`. Animated WebP frames and their 2400ms idle timing decode exactly against the actual Godot captures.

Run `res://scripts/dev_tools/golem_titan_hand_rig_test.gd` with `--headless` and `-- --social-no-auto` for the hand regression. Run `golem_titan_skeleton_bake.gd` graphically with `-- --social-no-auto --output=<absolute outside-repository evidence directory>` for native samples. Run `golem_titan_skeleton_review.gd` graphically with `-- --social-no-auto --asset-dir=<absolute source directory> --output=<absolute outside-repository evidence directory> --clip=idle` for the live rig beside the map/player. `golem_titan_animation_review.gd` reviews the baked clips and grounded slam.
