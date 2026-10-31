# Goblin idle animation review checklist

Status: source motion, installation and runtime review completed on 2026-10-31.
The user then requested finalizing these sets for the game; current Worker and
Warrior packs are `finalized_for_game_use`. This authorization is separate from
the automatic and internal visual checks below.

The 2026-10-30 review found that different PNG hashes and advancing frame
indices did not establish readable animation. Worker north was static;
all eight Warrior idles were static, too slight, or held one changed pose
and snapped on the loop. Seven readable Worker idles are retained.

For future animation work, complete this checklist before presenting a result.
Automatic checks, internal visual review, installation and user artwork approval
must be recorded separately.

- [x] Inspect all source frames and the last-to-first transition for every facing.
- [x] Reproduce actual spawned idle with normal game physics; distinguish source
  motion from playback/reset problems. The original clips advanced normally.
- [x] Show deliberate head, shoulder and torso motion through multiple poses.
  Palette shimmer, gear-only redraws and a first-frame pose pop do not pass.
- [x] Inspect breathing/weight timing and the seam at normal playback speed.
- [x] Keep feet planted and the complete tool/weapon attached to the correct
  hand; preserve the original face, helmet/hat, clothes and proportions.
- [x] Inspect every pixel frame for clipping, stray effects, halos and damage.
- [x] Inspect at least two actual Godot playback loops for every facing at
  normal scale and 4x, with the player alongside. A static contact sheet alone
  cannot establish good playback.
- [x] Confirm lossless native RGBA, nearest filtering, no mipmaps and original
  display scales, anchors, offsets, collisions and feet sorting.
- [x] Verify every walk/attack frame, seven retained Worker idles and all Scout
  assets/data against the pre-repair preservation hashes.
- [x] Run fresh import, focused runtime and Scout regression; inspect errors.
- [x] Complete independent source/code reviews and independently verify the
  installed source hashes, preservation fixtures and recorded runtime playback.

## Per-facing motion review

| Character | Facing | Source review | Two loops at normal/4x |
| --- | --- | --- | --- |
| Worker | south | Retained, readable | Pass: two or more cycles at both zooms |
| Worker | south-east | Retained, readable | Pass: two or more cycles at both zooms |
| Worker | east | Retained, readable | Pass: two or more cycles at both zooms |
| Worker | north-east | Retained, readable | Pass: two or more cycles at both zooms |
| Worker | north | New eight-pose body cycle; minor toe-outline redraw; fixed ground contact | Pass: two or more cycles at both zooms |
| Worker | north-west | Retained, readable broad arm sway | Pass: two or more cycles at both zooms |
| Worker | west | Retained, readable | Pass: two or more cycles at both zooms |
| Worker | south-west | Retained, readable | Pass: two or more cycles at both zooms |
| Warrior | south | New eight-pose body cycle | Pass: two or more cycles at both zooms |
| Warrior | south-east | New eight-pose body cycle | Pass: two or more cycles at both zooms |
| Warrior | east | New eight-pose body cycle; minor toe-outline redraw; fixed ground contact | Pass: two or more cycles at both zooms |
| Warrior | north-east | New eight-pose body cycle | Pass: two or more cycles at both zooms |
| Warrior | north | New eight-pose body cycle | Pass: two or more cycles at both zooms |
| Warrior | north-west | New eight-pose body cycle | Pass: two or more cycles at both zooms |
| Warrior | west | New body cycle with eased opening poses | Pass: two or more cycles at both zooms |
| Warrior | south-west | New eight-pose body cycle | Pass: two or more cycles at both zooms |

Repair design: eight-frame replacement cycles at 4 fps (two seconds). Worker
retains role-wide 6 fps for its seven untouched idles and uses
`idle.fps_by_direction.north = 4` for the repair. Warrior uses role-wide 4 fps.
Missing directional FPS entries keep the existing role FPS unchanged.

Native source, padding and frame dimensions are preserved. Original Worker
display 44/56, foot [28,53], offset [0,-25]; Warrior display 46/56, foot [28,52],
offset [0,-24]. No world props, placements, spawns or collision contracts change.
Source IDs and hashes belong in the two provenance manifests. Generated review
captures and diagnostic logs remain outside Git.

Prompting note: the rejected skeleton clip moved the pelvis only 0.002-0.003
of its box while fixing the head/chest. Those offsets were too small to produce
readable native pixel motion. Author an actual body cycle; do not freeze the
whole figure to suppress an unrelated light/effect defect. Inspect the returned
pixels rather than assuming that the word "breathing" produced breathing.

## Completed evidence

All nine replacement clips show a deliberate two-second body cycle. The small
Worker north and Warrior east toe-outline redraws do not move their ground
baselines or introduce a walking step. Warrior west eases through two similar
opening poses, then clearly lowers and recovers. Gear occlusion in east,
north-west and west matches the original rotations.

Fresh combined runtime regression: 4243 checks; Scout regression: 2206 checks.
The graphical temporal run passed 4702 checks and recorded 172 untouched
1600x1000 PNGs over four 4.12-4.16 second sequences: both characters at zoom 1
and zoom 4, each with the player and all eight facings. Every facing visited
every authored frame and looped at least twice with engine/sprite speed 1.
Matching poses repeat pixel-identically across the recorded cycles.

All source frames and recorded pose transitions were reviewed, including the
last-to-first transition, alongside exact normal-scale crops and actual 4x
Godot renders. Four normal-speed lossless WebP previews preserve the exact
render colors/pixels and four-second duration. Preview composition does not
change the source artwork.

All 427 installed PNGs match ordered source/provenance hashes, native dimensions
and lossless import settings. All 1161 protected files remain unchanged,
including walking, attack, seven retained Worker idles and Scout.

Supporting evidence remains outside Git in the Aetheria workspace's
`work/goblin-idle-repair/`: `SOURCE-MOTION-CHECKLIST.md`,
`runtime/root-final-independent-audit.json`, `runtime/resume-final-*.log`,
`runtime/godot-temporal/*-frames.json` and `runtime/godot-temporal/review/`.
The delivery message records the scoped commit and verified remote push.
