# Equipment frame inspection implementation plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline.

**Goal:** Inspect real F7 equipment poses without relying on animated GIFs.
**Architecture:** Extend SpritePreview only; reuse ActorSprite and its rig.
**Tech stack:** Godot 4.5.1 / GDScript.
**Spec:** ../specs/2026-11-01-equipment-frame-inspection-design.md

## Constraints

Work in the active checkout on a codex branch per AGENTS. Preserve dirty work,
all existing viewer controls, gameplay and artwork. No map/prop changes.

## Task 1: Inspection controls and evidence

Files: scripts/sprite_preview.gd; scripts/dev_tools/equipment_inspection_smoke.gd;
scripts/dev_tools/equipment_visual_audit.gd; docs/EquipmentBodyReplacement.md
(all under godot_client).

- [x] Write and run a failing viewer integration test for missing review API.
- [x] Implement `_set_review_paused(bool)`, `_step_review_frame(int)`,
  `_change_review_zoom(int)`, `_set_reference_visible(bool)`, and async
  `capture_review_frame(String) -> Error` with controls in the existing viewer.
- [x] Verify pause beyond a walk-hold interval, forward/back wrap, paused skin,
  direction/action changes, frame-preserving equipment changes, reference sync,
  resume, idle/attack fallback and authored attack, 1x/4x scale, PNG/JSON export.
- [x] Run existing sprite integration and equipment pose regressions.
- [x] Capture actual rendered 1x/4x poses through the viewer, inspect individual
  and adjacent frames, record defects separately from technical pass status.
- [x] Fresh code/visual review and scoped diff inspection; commit/push after final verification.

## Execution record

Implemented inline in the active checkout as required by AGENTS. Missing review
API, unflushed export metadata, overlay ordering and large-skin bounds each had
an observed failing regression before its correction. Pointer clicks are tested
through the root viewport. Headless and real OpenGL inspection runs passed.
The existing game sprite integration and pose regressions passed; the updated
visual audit also captured the real game's existing F7 widget successfully.

Independent read-only code and image review found the 4x Titan clipping issue.
Ruling: use a scrollable native-size SubViewport canvas and export its full
texture, preserving zoom while fitting the controls on screen. Covered by a
large-skin bounds regression, narrower-window control check and rendered export.
The audit tool now reads its actor's viewport to preserve its crop behavior.

The reviewer set aside artwork approval and unrelated dirty work; both remain
outside this tool patch. Parent inspection covered all 64 Iron walk poses in
adjacent-frame pages; art remains pending for the visible defects documented in
EquipmentBodyReplacement.md. No minor code findings were deferred.

## Review focus

Small-window layout and clipped 4x sprites; stale reference after skin change;
walk clock overriding a pause; attack fallback mislabeled as authored frames;
exporting a different pose than its metadata. Exercise these in the smoke test
and actual rendered evidence. No test grants artwork approval.
