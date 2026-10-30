# Goblin Scout animations

The complete eight-direction Scout set was visually approved for temporary use
on 2026-10-30: "we can use this for now." The installed PNGs preserve all 200
approved source files byte for byte. No frames were resized, recolored or repaired.

Some accepted attack frames contain an arrow and others do not. The user dislikes
the baked-in arrow. **Future Scout attack artwork must contain no arrow in any
frame; the game should render its projectile separately.** Keep this temporary
set as accepted; do not spend generations correcting it without a new request.
This installation does not change projectile rendering or combat rules.

| Action | Frames per facing | Total | FPS | Loop | Native PNG canvas |
| --- | ---: | ---: | ---: | --- | --- |
| Idle | 5 | 40 | 6 | Yes | South 72x72; NE/N/NW 76x76; other facings 80x80 |
| Walk | 8 | 64 | 9 | Yes | 80x80 |
| Attack | 12 | 96 | 10 | No | 80x80 |

Each action has south, south-east, east, north-east, north, north-west, west and
south-west clips. The larger animation canvases add symmetric transparent
padding at the original pixel density. Scout's original 60x60 base canvas,
display height 44 and feet anchor [30,55] remain unchanged. Existing ActorSprite
centering, scale 44/60, offset (0,-25), nearest filtering, collision body and
feet-based sorting remain in effect. Lossless texture imports have no mipmaps.

`data/goblin_scout_animations.json` is a small, fixed Scout-only runtime overlay.
CharacterSpriteLibrary loads it once after the original catalog and applies only
Scout's action definitions, additional frame sizes and animated direction coverage.
Original rotations, monster/player mappings and every other skin are unchanged.
`data/character_sprites.json` and its importer still describe the original export;
their import summary does not count these later 200 frames. Do not regenerate
the base catalog from a Scout-only export.

`art_sources/goblin-scout-animations/manifest.json` records the ordered source and
installed paths, native dimensions, approval, generation groups and SHA256 for
every PNG. The runtime overlay records hashes of that manifest and the selected
source list. Idle uses group `10cc346b-69bd-4141-98e7-8b865f75bb3a`; walk uses
`4c5d7552-e748-4a7a-86dd-879f7747cf41`, with east/north-east from the forward-carry
repair `92b4ce6a-ab67-4087-a235-37e5a9694e2f`; attack uses
`e981c773-0df7-4201-a806-2f3eeabbddeb`.

Use the game's existing F7 sprite viewer to select Goblin Scout and inspect
idle/walk/attack facings, or the existing F5 developer monster menu to spawn it
for local play. No new world spawns or map placements are installed.

Import first, then run the focused regression and existing integration smoke:

```powershell
& $env:GODOT --headless --editor --path godot_client --import --quit
& $env:GODOT --headless --path godot_client --script res://scripts/dev_tools/goblin_scout_animation_smoke.gd
& $env:GODOT --headless --path godot_client --script res://scripts/dev_tools/sprite_integration_smoke.gd
```

The focused smoke checks preservation against the original base catalog, all
24 clips/200 frames, import dimensions/alpha/mipmaps, ordered paths, playback,
attack completion and original actor scale/anchor/collision. A graphical run
with `-- --capture-dir=ABSOLUTE_DIRECTORY` captures the real player and all
eight Scout facings at camera zoom 1 and 4 for three samples of each action.
Keep screenshots and logs outside Git. These are actor lab captures; they do
not approve new map placements or alter combat timing beyond the existing
actor's authored-animation playback.

Installation verification on 2026-10-30: the focused smoke passed 2142 checks;
the graphical run passed 2181 and produced 18 captures. All nine zoom-4
captures (three samples per action, each with player and eight Scout facings)
were inspected for crispness, clipping and actor anchoring. Editor import and
the configured project startup completed without script errors.

Two existing validation limitations remain separate from this installation.
The original importer `--check` rejects the obsolete `Golem Crystalcore`
mapping; neither importer nor base catalog was changed. All 436 PNGs referenced
by the current base catalog still match their export originals byte for byte.
The broader sprite integration smoke passes 4357 assertions but logs a
`tile_commands.gd:24` Window/Node2D type error when its legacy main-scene fixture
loads directly. An independent process using only the original catalog
reproduced that same error. The broader run is therefore not an error-free
validation result; it does exercise Scout spawning and the existing combat/drop
path, with no gameplay changes made here.
