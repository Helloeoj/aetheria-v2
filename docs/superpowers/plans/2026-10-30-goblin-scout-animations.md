# Goblin Scout animation installation

2026-10-30. Implement the user-approved temporary eight-direction Scout set in
the active game, preserving unrelated local work and existing gameplay.

## Design

- Install 200 original lossless RGBA PNGs: 5 idle, 8 walk and 12 attack frames
  per facing. Use 6/9/10 FPS; idle/walk loop, attack does not.
- Preserve original rotations, Scout size [60,60], display height 44 and anchor
  [30,55]. Keep existing ActorSprite scaling, collision and action routing.
- Preserve the generated base catalog/importer and their reproducible original
  export summary. Apply a fixed `goblin_scout_animations.json` overlay once for
  Scout animations, frame sizes and action coverage only.
- Record per-frame source/destination/hash/native-size provenance and user
  temporary acceptance. Future Scout attack art must have no baked-in arrow;
  retain the accepted inconsistent set now and leave projectile logic unchanged.
- Reuse existing F5/F7 development tools; add no world placement, spawn, loot,
  combat-stat, player or control changes.

## Implementation and verification

1. Run the focused Scout smoke against the existing static Scout before runtime
   edits; retain the expected missing-animation failure outside Git.
2. Copy source bytes, create the fixed pack and provenance manifest, and load
   only the three allowed Scout fields after the original catalog.
3. Import in Godot 4.5.1, then run the focused Scout smoke, existing sprite
   integration smoke, original importer `--check` and main startup.
4. Capture and inspect actual Godot zoom-4 player/Scout renders for all actions.
   No static prop/world contract is changed, so map placement validation is
   outside this installation's scope.
5. Review the exact changed paths and hand them to the coordinating agent for
   explicit staging, commit and push on `codex/goblin-scout-animations`.

Artwork approval, installed status, automatic checks and actual runtime visual
review are separate evidence. Generated logs and captures remain outside Git.
