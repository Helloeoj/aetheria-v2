# Equipment body replacement

**Body-section correction:** the bare character is now three independent native
layers: head; chest/arms; legs/feet. Per-pose outline masks preserve the complete
original ears, jaw and chin, and remove the generated head from chest armor.
The accepted leg/foot images are unchanged. See
[Equipment section checklist](EquipmentSectionChecklist.md) for the contract,
failure evidence and visual gates.

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
