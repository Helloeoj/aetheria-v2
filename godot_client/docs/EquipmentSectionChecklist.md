# Equipment body-section checklist

User correction: preserve the approved chest/arm and leg/foot artwork, but keep
the original character head complete. The earlier neck-height crop cut the chin
off several source frames, then exposed a different generated face recolored as
metal. Passing placement/contact tests did not detect that visual defect.

## Native contract

- 80x80 native pose canvas, one source pixel per character source pixel.
- Centered padded source frame and existing player feet anchor; no change to
  actor/world scale, collisions, maps, controls, inventory or saves.
- Three independent source sections: head; chest and arms; legs and feet.
- `replacement-v1/body-sections.json` records per-pose head outline spans.
  These follow native pixel contours rather than a rectangular chin cutoff.
- Remove the generated source head from chest art. Armor always excludes the
  complete original head outline, including ears and chin. Copy original head
  RGBA unchanged. Reuse the existing material's complete native gorget behind
  the chest to cover empty neck space; it may fill the erased generated-head
  area outside the actual original head. It never paints over the real head.
- Bare arms retain their hands and dark outlines across the waist boundary. The three source
  sections partition every opaque source pixel exactly once.
- The accepted leg/foot PNGs remain byte-identical; this fix changes compositing
  and outline masks, not those images. Preserve existing source art and candidates.

## Required review

- [x] Reproduce the reported chin pixel loss before fixing it.
- [x] Verify all 72 source poses retain exact original head/face pixels.
- [x] Verify disjoint source section ownership and armor exclusion of head pixels.
- [x] Check head/chest/legs independently equipped, mixed tiers and removal.
- [x] Inspect close-up native/4x face crops and complete 4x Godot walk sequences,
  including unhelmeted and helmeted characters in all eight directions.
- [x] Check approved chest/arm and leg/foot details have not changed.
- [x] Run body-section, equipment, attachment, shield and sprite regressions;
  import/parse and start the active project. Inspect actual logs.
- [x] Keep automatic checks, local installation and user visual approval separate.

The map worldbuilding checklist applies to environment props and placements.
This character correction makes no world placement/collision changes; its
corresponding visual gate is this section checklist and actual player rendering.
New composite output remains under visual review until accepted by the user.

Regression evidence: the initial test failed for missing chin/source body nodes.
An independent source-color/anatomical face check caught omitted ear pixels;
these are now included in the traced outlines. A separate low-hand ink fixture
failed before assigning skin-adjacent dark outlines to the upper section, then
passed. All 216 accepted leg/foot PNG hashes are unchanged. No PNG is repainted.

Validation: body-section regression 580,721 checks; equipment poses 3,560;
attachments 1,403; shields 630; fitted equipment 19,446 across 51 items/3,456
item poses; sprites 5,451. All passed. Editor import and main startup passed.
Real Godot 4x screenshots cover all 72 poses, individual/mixed/full equipment,
and weapons. Human visual approval of the corrected composite remains pending.
