# Equipment direction and walking repair plan

> Execute inline under superpowers:executing-plans; standing workspace instructions waive routine approval gates and require installation in this checkout.

**Goal:** Keep equipment attached, correctly occluded and crisp throughout the existing eight-direction idle/walk cycle.

**Architecture:** CharacterAttachmentRig masks complete body regions and orders replacement layers. FittedEquipmentVisual selects complete native equipment frames; the equipped torso owns hand tracks. Held items use native-pixel carry fitting. Gameplay and the original player remain intact.

**Tech Stack:** Godot 4.5.1, GDScript, existing PNG/JSON equipment pack.

**Spec:** docs/superpowers/specs/2026-10-31-equipment-direction-walk-design.md

## Constraints and review focus

- Preserve user changes elsewhere in the active checkout; push only to Helloeoj/aetheria-v2.
- Keep original art, independent equipment slots, actor world Z, hit tint and attack lunge.
- Test rear equipment with partial armor, removing armor, supported/unsupported skins, and refreshed equipment every tick.
- Review all eight facings, all eight walk frames, native pixel density, foot contact, hand contact, swords and bulky weapons.

## Task 1: Reproduce and repair equipment poses

- [x] Add a real ActorSprite regression test and a 4x Godot review renderer.
- [x] Run the regression against the current pipeline and confirm the reproduced failures.
- [x] Implement complete native chest/leg slot replacements, matching hand tracks, body ordering and weapon carry.
- [x] Run the targeted regression and existing attachment, shield, fitted and sprite integration tests.

## Task 2: Review and synchronize

- [x] Capture and inspect 4x Godot idle/walk sheets and all equipped weapons in eight directions.
- [x] Run editor import/parse and main-scene startup; inspect output, not only exit codes.
- [ ] Review the task diff, stage explicit paths, commit and push the task branch; verify remote hash.

## Execution ledger

- Investigation: latest compact ADC report contains only an unrelated missing shutdown marker; no evidence connects it to equipment. Kept unresolved.
- Baseline: actual existing-game F7 captures reproduced the visual faults; evidence is outside this repository under the supporting workspace's work/equipment-fit-2026-10-31 directory.
- Ruling: work in the active checkout on codex/equipment-direction-walk-fix per the user's standing instruction; preserve all unrelated dirty files.
- User clarification: armor becomes each corresponding animated body part; stop stretching armor over the original limbs. Replaced the original joint-fit proposal with authored native slot frames.
- Regression RED: initial root-cause test reported 1,129 failures; clarified replacement-slot test reported 4,710 failures before installing the new slot frames.
- First GREEN: complete replacement frames passed 3,252 checks across all tiers and poses. Captured real Godot 4x sheets for armor and every weapon with/without armor. Final review and verification remain pending.
- Final review: independent read-only reviewer found partial chest hand leakage. Fixed with original-hand masking; added a failing pixel regression, then verified green. Also found and fixed shared CPU source-image mutation during mask creation (72 failing source-integrity checks before the private-copy fix), and preserved bare hands above leg-only replacements.
- Final visual correction: reused complete broad-side blade/staff art for profiles, carried crossbows clear of the ground, and tilted side-profile staff gems clear of helmets. Gem/head regression failed before correcting carry and passed afterward. A far-hand shaft may be naturally occluded by the helmet; the focal gem must remain clear.
- Final tests: equipment poses 3,560; attachment 1,403; shield 630; fitted 19,446 covering 3,456 item poses/51 items; sprites 5,451; bronze combat 3,040. All pass. Editor import and main startup exit 0 without script errors. Native PNG check: 504 files at 80x80, binary alpha, no rescaling.
- Final collar review: restored one clipped row of the original generated collar in nine north/north-west poses across three materials. Exact PixelLab edits retain native pixels; head/collar contact regression went from 27 failures to green without stretching or drawing substitute neck pieces.
- Validation fixture maintenance: grant required skill levels in isolated test players, compare canonical item aliases, and honor existing direction-specific animation rates. No gameplay restrictions or catalog stats changed. Stop writing fitted validation output into tracked source data.
- Ruling: original existing art and earlier poses stay on disk; new native body layers are installed candidates, awaiting user visual approval. Cost if the look is rejected: change the layer selection/artwork while retaining the verified replacement pipeline.
- Ruling: merge timing remains with the existing development workflow; push this task's commit on its descriptive codex branch. The parent branch is already ahead of main, so do not merge other completed branches or unrelated working-tree changes as part of this repair.
