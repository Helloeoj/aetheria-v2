# Titan dark magic - working visual candidates

Two presentation-ready spell scenes and a matching casting animation, reviewed
in the actual Golem Kingdom game alongside the unchanged player.

- **Void Bolt:** one captured target tile, purple warning, a black-cored violet
  projectile and a dark impact pulse. It travels to the captured tile, so a
  player who leaves it is not chased by the artwork.
- **Shadow Eruption:** one narrow dark-energy eruption per selected tile. The
  review demonstrates ten independent instances, including the player's captured
  tile. The engine supplies the tile set; there is no baked ten-tile sheet.
- **Casting:** he raises complete fists, lifts his head, opens his stone jaw and
  charges the hands/chest with violet energy. Original red eyes, planted legs,
  cyan restraints and ground anchors are retained.

## Timing and native scale

The shared combat tick is600ms. The warning uses the exact physical-warning
shapes/alpha with a purple palette. Warning tiles are captured at start and
never retarget. The cast winds up over two ticks/1200ms and recovers over the
next two. The bolt releases at1200ms, travels one tick and impacts at1800ms;
its locked marker remains visible during flight. AoE releases at1200ms, rises
over600ms and recedes over600ms. Visual timing does not decide damage.

Body source is the approved neutral256px Titan, not the rejected AI redraw.
A dedicated17-Bone2D skeleton supplies elbow/wrist/fist and jaw motion. The
source image is unchanged.120 native samples at20ms/50fps use a336x288 canvas,
foot anchor(168,256), padding(40,16) and density1 world pixel per native pixel.
That padding permits the outward arm arc without clipping or rescaling the
character. Isolated1-3pixel raster specks from rotating edges are cleaned in
the bake. All600 sampled lower-body region comparisons remain pixel exact.

Warning textures are48x64 with anchor(24,52). The orb is48x48 with center(24,24).
The eruption is48x72 with its ground root at(24,70). Gameplay footprint is one
32x32 cell; a few spectral wisps can extend visually outside it. Sources have
transparent backgrounds, no baked map floor, lossless import and no mipmaps.

## Reusable Godot scenes

- `res://scenes/Effects/TitanMagicCast.tscn`: root at the actor's existing feet.
  Temporarily hide its ordinary visual, sample this node from the encounter's
  clock, then restore ordinary idle when returned phase is `complete`.
- `res://scenes/Effects/TitanDarkBolt.tscn`: root at the captured target-cell
  center. Set `launch_point` in local coordinates, then sample the same clock.
- `res://scenes/Effects/TitanShadowEruption.tscn`: one root per captured cell.

All expose `sample_at_seconds(elapsed_since_warning_start)`. They stay hidden
before/after their own lifetime, have no damage authority or collision, and
share imported textures. The runtime cast uses the clean native bake; the
source rig remains available for editing and bone proof. Particle/aura overlays
follow the same wrist/fist kinematics.

## Status and verification

These are **working visual candidates awaiting artwork review**. Runtime
presentation scenes and native frames are installed in the asset library.
Production boss AI rotation, magic damage/accuracy rules and final encounter
placement are not installed by this source-art task. Existing combat stats,
approved idle/slam/spike, spawn controls, save data and maps are unchanged.

`titan_dark_magic_test.gd` passes40 checks covering the real17-bone hierarchy,
rigid hand/thumb transforms, stable body, independent jaw, runtime native
frames/tick timing, captured effect roots and hidden lifecycle endpoints.
`titan_magic_bake.gd` records120 GPU samples with zero protected-region or
endpoint failures. The delivered native frames also pass600 exact pinned-region
comparisons, binary alpha and exact approved neutral-pose checks.
`titan_dark_magic_review.gd` exercises these public scenes in the actual game:
one target versus ten clear floor cells, an escaping player and4x casting view.
No passive-prop placement certificate is claimed for scripted actor/VFX scenes.

Evidence stays outside Git under
`work/character-animation/golem-titan-dark-magic-v1/evidence/`. Rejected native
idle-mesh and temporal-generation attempts are retained there, excluded from
this release. Current actual renders use `actual-game-native`; unchanged
prefix frames are retained when checking the final return-to-idle tail.
