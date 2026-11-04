# Pickaxe sprite artwork plan

**Goal:** Create reusable pickaxe artwork matching the existing peasant and
equipment, ready for subsequent mining-animation work.

**Scope:** Seven existing equipment materials: Bronze, Iron, Steel, Blacksteel,
Mithril, Adamantite and Runite. One consistent wooden shaft and pick-head design;
material palettes distinguish tiers. No new catalog IDs, stats, skill rules,
mining behavior or animation implementation. User selected held sprites first. Require eight directional held views per material, calibrated grip points,
real CharacterAttachmentRig registration and F7 access. Mining swing animation
frames and inventory icons remain outside this step.

**Art:** Use built-in imagegen with actual peasant/equipment references. Make
one complete transparent master first; inspect silhouette, material planes and
grip. Rasterize once to the chosen native detail scale, use lossless alpha,
nearest filtering and no mipmaps. Do not enlarge coarse source pixels and call
the result higher detail. Preserve untouched generated inputs and exact prompts.

- [x] Inspect existing equipment/native density and make the Iron reference.
- [x] Finish the selected deliverable set using the same shape/palette family.
- [x] Save reusable runtime assets and source/provenance in the active project;
      inspect light/dark backgrounds and real Godot 4x beside the unchanged player.
- [x] Keep artwork approval distinct from import checks and installation;
      validate and commit/push only this asset task, preserving other local work.

Mining animations follow this static-art task. Do not infer permission to
activate production Mining or populate its empty pickaxe catalog.

## Completion pass — 2026-11-03

Recovered the completed 56 directional runtime views and seven registered scenes.
The later character-rig commit already supplies pickaxe-family/support-hand motion;
preserve it. Corrected the saved exporter to reproduce those current scenes rather
than remove their motion bindings. Its regression first failed on that omission,
then passed for all seven scenes and 56 images. Source and operation provenance
are documented in `art_sources/pickaxes/held-v1/README.md`.

Fresh checks: 1,548 attachment assertions, 56 real Godot 4x registered views with
lossless imports and zero primary-grip drift, captured F7 selection, and one actual
East Outskirts Iron/south-east case using real Main movement (zero failures).
Inspected all facing/material renders and actual-world idle/walk screenshots.
Evidence: supporting workspace `work/pickaxe-sprites/completion-2026-11-03/`.
No new artwork generation or gameplay changes. Final user art approval is pending.

## User correction — 2026-11-01

The user likes the generated designs but requires usable eight-directional held
objects, not only front-view PNGs. Preserve design; use PixelLab existing-image
rotations, reuse the eight views for material variants, and bind the existing
EquipmentVisual2D directional textures/pivots to right_hand through the actual
CharacterAttachmentRig registry. Verify all56material/facing combinations at4x
and through existing idle/walk sockets. No fabricated inventory item definitions.
