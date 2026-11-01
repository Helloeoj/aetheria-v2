# Equipment body replacement

Bronze, iron and steel platebodies/platelegs now replace the corresponding body
part completely. Armor supplies its own animated anatomy; it is never stretched
over the bare peasant's legs or arms. Each slot has an idle pose and eight walk
frames in all eight directions, at a native 80x80 canvas. The original character,
earlier equipment art, independent slots, inventory requirements and combat
behavior remain available.

- Platelegs remove the entire original lower-body region, including the empty
  spaces between the old legs. Complete armored legs and boots animate instead.
- Platebodies remove the original torso and arms, including a hand swinging below
  the waist. The replacement owns its hands and the weapon attachment track.
- Helmets retain their existing independent head replacement. Removing a piece
  immediately restores that original body region. Materials and slots can mix.
- Rear weapons/shields/capes sort against the actual replacement body at the
  actor's existing world Z. Native hand-item fitting retains exact hilt contact
  and source pixel density during carry rotations. Side-facing blades/staves use
  an existing complete broad face; the original edge-on art remains on disk.
- Body masks edit private image copies, preserving shared source pixels when
  changing gear or rendering another actor. Bare hands remain above replacement
  leg layers when a platebody is not equipped.

The active pack is `Assets/Equipment/fitted_bronze_iron/replacement-v1/`.
`manifest.json` records source PixelLab jobs, exact layer-export operations,
native size, anchors, hashes and separate artwork/installation statuses.
`poses.json` stores the shared per-frame hand tracks. There are 432 independent
slot frames across three materials and 72 preserved source frames. The standard
equipment registry and existing F6 inventory/F7 preview use them directly.

This is an installed correction for visual review, **not a record of user artwork
approval**. No map, balance, character save, movement control or interface was
replaced. The peasant's existing attack lunge remains; these are idle/walk frames.

## Verification

```text
Godot --headless --path godot_client --script res://scripts/dev_tools/equipment_pose_regression.gd
Godot --headless --path godot_client --script res://scripts/dev_tools/attachment_smoke.gd
Godot --headless --path godot_client --script res://scripts/dev_tools/shield_attachment_smoke.gd
Godot --headless --path godot_client --script res://scripts/dev_tools/fitted_equipment_smoke.gd
Godot --headless --path godot_client --script res://scripts/dev_tools/sprite_integration_smoke.gd
Godot --path godot_client --script res://scripts/dev_tools/equipment_pose_review.gd -- --pose-output=<absolute evidence directory>
```

The review renderer uses the actual game's ActorSprite and textures, at 4x zoom.
It captures every idle/walk pose for individual slots, complete/mixed armor and
every weapon with/without armor. Source previews and headless results do not
substitute for inspecting those renders or for user artwork approval.

Tests print results and leave generated evidence outside the source tree. When
running engine processes concurrently, assign a separate
`AETHERIA_DIAGNOSTICS_DIR` and native `--log-file` to each process so diagnostics
retention does not compete over the same session directories.

## F7 frame inspection

The existing sprite viewer now has Pause/Resume, Previous/Next frame, a frame
counter and 1x/3x/4x zoom. Stepping pauses both the actor's action clock and the
sprite; it synchronizes equipment to the selected frame. Direction/action
changes restart at frame zero while paused. Equipment changes retain the pose.
Missing authored attacks are explicitly marked as fallback poses.

Enable **Original body beside gear** to compare the same original skin and
animation frame at the same foot anchor. This is a reference, not an assertion
that armor should stretch to the original body. Head, torso/arms and legs/feet
must retain complete silhouettes and believable connections independently.

**Save PNG + pose** freezes the current pose and saves a lossless Godot render
with JSON identifying the actual equipment, animation, frame, zoom and anchors
in `user://equipment-review/`. The status line shows the full output path.
Large sprites scroll within the preview; exports include the entire canvas.
The viewer renders above chat and closing F7 restores the normal game view.

Before sharing candidate artwork, examine individual 1x and 4x renders and
adjacent frames for neck/waist seams, limb continuity, face/skin color changes,
foot placement, weapon grips and rear/profile occlusion. Inspect each changed
direction, action, equipment slot and material. Do not use GIF playback or a
passing automated suite as visual approval. A separate reviewer must inspect
the actual PNG evidence as well as the code when reviewing a visual change.

On 2026-11-01, the rejected body-section contour patch remained reverted.
Visual inspection of the restored Iron chest/legs through all 64 walk poses
still found a shortened chin/metal collar boundary, questionable rear hip/leg
connections and profile leg overlap. These remain unresolved, unapproved art;
this inspection-tool change does not modify body masks or armor textures.

```text
Godot --headless --path godot_client --script res://scripts/dev_tools/equipment_inspection_smoke.gd -- --social-no-auto
Godot --path godot_client --script res://scripts/dev_tools/equipment_inspection_smoke.gd -- --social-no-auto --inspection-output=<absolute evidence directory>
```

The second command exercises pointer controls and exports all eight Iron walk
frames in all eight directions at both zooms, plus the large-sprite export case.
