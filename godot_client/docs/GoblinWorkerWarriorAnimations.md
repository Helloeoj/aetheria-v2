# Goblin Worker and Warrior animation runtime test

On 2026-10-30 the user authorized installing the current generated Worker and
Warrior artwork for local runtime animation and combat testing. This
authorization does not grant final visual artwork approval. Both packs retain the status
`runtime_test_authorized_visual_approval_pending`; future artwork review remains
separate from automatic checks and installation.

Each complete pack has eight distinct authored facings: south, south-east, east,
north-east, north, north-west, west and south-west. No missing facing is borrowed
from another direction or mirrored. All selected RGBA PNGs are copied unchanged,
including their native density and original transparent padding.

| Action | Frames per facing | Total per character | FPS | Loop |
| --- | ---: | ---: | ---: | --- |
| Idle | 5 | 40 | 6 | Yes |
| Walk | 8 | 64 | 9 | Yes |
| Attack | 12 | 96 | 10 | No |

Worker keeps its original 56x56 base canvas, display height 44 and feet anchor
[28,53]. Warrior keeps its original 56x56 base canvas, display height 46 and feet
anchor [28,52]. ActorSprite retains its existing centered-frame handling,
respective scales 44/56 and 46/56, offsets (0,-25) and (0,-24), nearest filtering,
collision bodies and feet-based sorting. Frame dimensions in each runtime pack
record the actual source PNG canvases; they do not replace these base dimensions.
Texture imports remain lossless with no mipmaps.

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
`-- --capture-dir=ABSOLUTE_DIRECTORY` records real Godot player/actor lab renders
for 4x review; these renders do not approve world placements or final artwork.

Installation verification on 2026-10-30: editor import and the configured Login
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

The previously documented broader sprite fixture Window/Node2D type error and
obsolete Crystalcore importer mapping remain outside this installation. See
`GoblinScoutAnimations.md` for that baseline evidence.
