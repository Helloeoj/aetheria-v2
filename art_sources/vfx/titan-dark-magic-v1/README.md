# Titan dark magic visuals

Two spell presentation scenes and the user-selected raised-fist roar, installed
in the asset library. Live boss rotation, damage and projectile homing remain
outside this artwork task.

- **Void Bolt:** preserved black-cored violet projectile, trail and dark impact.
  No ground indicator. The preview supplies a fixed endpoint; the user will add
  player-homing magic-missile behavior in a later coding pass.
- **Shadow Eruption:** unchanged purple warning and one dark-energy eruption per
  selected tile. The actual-game review shows ten independent instances.
- **Casting:** the exact33 original PNGs from PixelLab job
  `5475c253-5959-4b0f-85e1-a39452d7ea28`, selected by the user from the contact
  sheet. Raised fists and open-mouth roar replace the previous17-bone rotation
  bake. No limb warping or added hand-ring kinematics are used at runtime.
  A temporary shader turns upper crystals violet; red eyes and cyan bindings
  retain their source colors. Source PNG bytes are unchanged. Runtime transparency
  removes only the large connected flat brown floor oval from generated frames;
  small stone shading regions with the same palette color are preserved.
  The flat grey-green and neutral-grey background mattes beneath the waist
  armor are also keyed out. Transparent tongue holes in source frames3,11,18 use only missing
  interior mouth pixels from intact adjacent poses2,10,17. Opaque artwork is
  preserved; the chosen motion and purple crystal shader are unchanged.

## Timing and native scale

Shared tick600ms. Cast duration2400ms, uniform source-frame sampling at2400/33ms,
release1200ms. Source frames stay in their original order. Native256x256 canvas,
foot anchor(128,240), density1 world pixel per source pixel, nearest filtering
and no mipmaps. The normal idle is restored when the cast completes.

Only AoE uses the physical attack's two-tick warning, palette-mapped purple.
AoE rises600ms and recedes600ms. The bolt releases1200ms, travels600ms in this
preview and impacts1800ms. No combat/damage authority is implied by that clock.

Warnings48x64 anchor(24,52); orb48x48 center(24,24); eruption48x72 root(24,70).
Original projectile and eruption textures are unchanged.

## Reusable scenes

- `res://scenes/Effects/TitanMagicCast.tscn`: root at actor feet. Hide ordinary
  actor art during the cast, then restore it when returned phase is `complete`.
- `res://scenes/Effects/TitanDarkBolt.tscn`: preview root at supplied endpoint;
  `launch_point` in local coordinates. No ground marker or homing implementation.
- `res://scenes/Effects/TitanShadowEruption.tscn`: one root per captured cell.

All expose `sample_at_seconds(elapsed_since_cast_start)`, hide outside their
lifetime, and have no collision or damage. Old skeletal editing scripts are
historical source tools and do not supply this runtime cast.

## Status and verification

The user selected the33-frame casting source and likes both spell effects.
The revised combination remains available for visual review. Active-game
`GolemKingdom.tscn` captures include the real player, a marker-free bolt, ten AoE
instances and a4x caster view. Native asset SHA checks preserve all33 selected
PNGs and the original projectile/eruption. No passive static-prop placement
certificate is claimed for these scripted actor/VFX scenes.

Existing stats, idle, slam, physical spikes, spawn controls, saves and maps are
unchanged. Tests and review output stay outside Git in supporting workspace
`work/character-animation/golem-titan-dark-magic-v1/evidence/` under the
`revision-*` logs and `actual-game-selected-cast` captures.
