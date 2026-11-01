# Equipment direction and walking repair

Correct the existing peasant's equipment quality, hand contact and clipping in
eight directions, including every walking frame. Preserve the existing designs,
inventory, combat timing, UI, saves and world sorting.

The reproduced faults are upright blades crossing shoulders, foot anchors below
the source soles, ambiguous automatic boot tracking, and rear equipment relying
on the hidden original sprite instead of the replacement armor body. Rotating
and stretching tiny armor pieces directly at screen resolution also gives them a
different pixel density from the character.

The user clarified the required behavior during investigation: each equipped
piece replaces its body region completely. Platelegs become the animated legs;
they must not stretch to fit the bare character's legs. The same ownership
applies to the torso, arms and head.

Use complete native 80x80 authored chest/leg animation layers in all 72 existing
poses. Each slot removes the entire corresponding original region, including
empty space between limbs; no original limbs or procedural filler remain under
the armor. A replacement chest owns its hand tracks, and those drive held items.
The existing helmet independently replaces the original head. Preserve mixing
slots/materials and restore the original region immediately on unequip.

Repair body-relative ordering and outward weapon carry with the hilt fixed to
the active hand. Sample hand-item rotations once on the native pixel grid.
Keep source artwork and earlier reviewed poses on disk. New armor frames have
separate candidate, installation and visual-review statuses, and are never
marked user-approved by automatic tests.

Alternatives considered: replacing the complete character would break mixing
independent slots. Stretching static armor fragments onto the old limb estimates
is specifically rejected. Complete frame-based equipment layers preserve both
the armor's anatomy and the existing game's independent equipment slots.

Standing AGENTS.md authorization applies: implement in the active checkout,
validate, commit only this task, and push a codex development branch.
