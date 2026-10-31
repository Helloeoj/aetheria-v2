# Goblin Worker and Warrior animation runtime test

On 2026-10-30 the user authorized installing the current generated Worker and
Warrior artwork for local runtime animation and combat testing. This
authorization does not grant final visual artwork approval. Both packs retain the status
`runtime_test_authorized_visual_approval_pending`; future artwork review remains
separate from automatic checks and installation.

The current idle repair replaces all eight Warrior idles and Worker north with
eight-frame, two-second cycles at 4 FPS. The replacement sources passed internal
frame, body-motion, held-gear and loop-seam review before installation for runtime
QA. This source pass does not grant final user artwork approval. The seven other
Worker idles and every walk/attack PNG remain unchanged. Worker now has 203
animation frames; Warrior has 224. Scout's temporarily accepted set is unchanged.

Each complete pack has eight distinct authored facings: south, south-east, east,
north-east, north, north-west, west and south-west. No missing facing is borrowed
from another direction or mirrored. All selected RGBA PNGs are copied unchanged,
including their native density and original transparent padding.

| Character/action | Frames per facing | Action total | FPS | Loop |
| --- | ---: | ---: | ---: | --- |
| Worker idle | North 8; other facings 5 | 43 | North 4; other facings 6 | Yes |
| Warrior idle | 8 | 64 | 4 | Yes |
| Either character walk | 8 | 64 | 9 | Yes |
| Either character attack | 12 | 96 | 10 | No |

Worker keeps its original 56x56 base canvas, display height 44 and feet anchor
[28,53]. Warrior keeps its original 56x56 base canvas, display height 46 and feet
anchor [28,52]. ActorSprite retains its existing centered-frame handling,
respective scales 44/56 and 46/56, offsets (0,-25) and (0,-24), nearest filtering,
collision bodies and feet-based sorting. Frame dimensions in each runtime pack
record the actual source PNG canvases; they do not replace these base dimensions.
All 72 replacement idle PNGs have native 80x80 canvases, including their original
transparent padding. Texture imports remain lossless with no mipmaps.

An action's optional `fps_by_direction` value overrides its default `fps` only
for the named facing. Worker idle retains default 6 FPS with `north: 4`; Warrior
idle uses default 4 FPS. Missing overrides keep the existing action FPS, including
Scout and all unchanged walk/attack clips. This changes animation playback only.

CharacterSpriteLibrary applies three fixed known overlays after loading the
original catalog: Scout, Worker and Warrior. Each overlay changes only its skin's
animations, additional frame sizes and animated-direction coverage. The original
catalog, importer, rotations, defaults, monster mappings, other characters and
Scout's temporarily approved artwork are preserved. No world spawns, map
placements, collision changes, drops or combat rules are added by these packs.

`data/goblin_worker_animations.json` and `data/goblin_warrior_animations.json`
contain ordered runtime clips and provenance hashes.
`art_sources/goblin-worker-animations/manifest.json` and
`art_sources/goblin-warrior-animations/manifest.json` record the selected source
paths, installed paths, native dimensions, generation groups, authorization
status and SHA256 of every source PNG. The overlays also record their manifest
hashes. Keep candidate artwork, runtime-test authorization, automatic validation
and final visual artwork approval as separate statuses.

The replacement Warrior idle source group is
`614d0222-feb8-4d86-bf4f-f5f8e491d69c`; Worker north uses
`382723a3-b257-4e13-a0fa-765d30e77494`. Per-direction provenance records each
group, frame count, FPS, exact source URL/hash and source-review evidence. The
manifests retain the superseded group/selection hashes and previous frame records.
Exact old runtime packs, manifests, complete source selections, 45 replaced PNGs
and their import settings remain in external repair evidence; they are not
generated Git artifacts.

The catalog and SpriteFrames resources are cached once per Godot process. Exit
and restart the game after installation; an already running process retains its
previous static catalog. In a fresh game process, use the existing F7 sprite
viewer to select Goblin Worker or Goblin Warrior and inspect idle, walk and
attack in each facing. The existing F5 developer monster menu can spawn either
for local play.

Import before running the focused regression:

```powershell
& $env:GODOT --headless --editor --path godot_client --import --quit
& $env:GODOT --headless --path godot_client --script res://scripts/dev_tools/goblin_worker_warrior_animation_smoke.gd
& $env:GODOT --headless --path godot_client --script res://scripts/dev_tools/goblin_scout_animation_smoke.gd
```

Keep graphical captures and logs outside Git. A graphical focused-test run with
`-- --idle-capture-dir=ABSOLUTE_DIRECTORY` records normal-speed idle cycles at
normal scale and 4x, with elapsed times, actual frame indices and observed loops.
The older `-- --capture-dir=ABSOLUTE_DIRECTORY` mode records static action
keyframes. These renders do not approve world placements or final artwork.

Historical initial-install verification on 2026-10-30, before the idle repair:
editor import and the configured Login
main-scene startup both exited 0 without script errors. The combined headless
smoke passed 3985 checks, including 16 live actors, actual EastOutskirts public
spawns, the position-to-animation bridge and real combat attack events. Scout's
regression passed 2206 checks. The graphical combined run passed 4060 checks and
produced 36 captures. All 18 zoom-4 captures (three samples per action for each
character, each with the player and eight facings) were inspected for crispness,
clipping and actor anchoring. No runtime filtering, canvas-clipping or unintended
origin-shift defect was observed. A separate source/provenance check confirmed
that all 400 installed PNGs remain byte-identical RGBA at their native dimensions,
with matching manifest hashes and lossless imports without mipmaps. Final
artwork approval remains pending.

Current idle-repair verification: the exact nine-clip selection and bounded
installation plan were hash-checked, editor import exited 0 without script
errors, and all 427 installed animation frames match their provenance and native
RGBA dimensions with lossless imports and no mipmaps. All 1161 preservation
baseline files remain unchanged, including the retained Worker idles and all
walk/attack artwork. Fresh verification completed on 2026-10-31: the combined runtime regression
passed 4243 checks and Scout passed 2206. The normal-speed graphical run passed
4702 checks, recording 172 real Godot PNGs across both characters at normal
scale and 4x. All eight facings completed at least two cycles at each zoom.
Source and rendered pose transitions, normal-scale views, full cycles and loop
seams were reviewed beside the player. Worker north and Warrior east retain
small toe-outline redraws with fixed ground baselines; no foot sliding was
observed. `GoblinIdleAnimationChecklist.md` records the completed internal
review. Final user artwork approval remains separate and pending; frame
advancement or distinct hashes alone never establish readable body motion.

The previously documented broader sprite fixture Window/Node2D type error and
obsolete Crystalcore importer mapping remain outside this installation. See
`GoblinScoutAnimations.md` for that baseline evidence.
