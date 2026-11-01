# Golem Titan physical spike - tick-paced review candidate

One pointed gray-stone spike for one 32-world-pixel affected cell. Red cracks
warn of the physical attack. The whole stone rises through the floor, reaches
its peak once and immediately retracts. No lingering spike/hazard phase.
Every tile uses the same atlas and has independent playback state. This revision
replaces the rejected fast pop with a full combat tick up and a full tick down.

## Native contract

- Canvas: 48x64; ground anchor: (24,52); density: 1 world pixel per texel.
- Affected ground cell: 32x32 centered on the root. Spike height may extend
  upward visually; its narrow base does not affect another gameplay cell.
- One whole PixelLab Pro spike, candidate 3, job
  `531dfe1b-6f27-4fb4-ba94-a17313f337ed`. Exact prompt/receipt and the approved
  Titan style-source hash are preserved in `generation.json`.
- `source-selected.png` is untouched service output. `master-spike.png` only
  translates it by integer pixels. No rescaling, warping or segmented animation.
- Red cracks are native pixel lines; six small impact chips are intentional.
  No floor square, terrain texture or character is baked into the effect.
- Lossless PNG source, binary alpha, nearest filtering, no mipmaps.

## Frames and timing

The 3408x64 atlas contains seventy-one 48x64 frames, left to right. The actual
combat tick is read from `scripts/game_tick_config.gd`: currently600ms. Visual
frames run between those gameplay ticks at20ms intervals (50fps), rather than
advancing just one picture per tick.

| Frames | Purpose | Duration |
| --- | --- | --- |
| 0-3 | Red warning intensifies | Engine-controlled; default two ticks/1200ms |
| 4-33 | Eased rise from floor to just below peak | One tick/600ms,30 steps |
| 34 | One exact51px peak frame; no added dwell |20ms |
| 35-63 | Immediate eased descent |580ms; peak and descent together one tick |
| 64-69 | Brief crack/debris cleanup; no stone |120ms total |
| 70 | Fully transparent inactive/end | Indefinite |

There is one full-height frame and no added peak dwell. Both phases use eased
integer-pixel travel, with no jump larger than3 native pixels. The last pixel
returns below the floor exactly two ticks/1200ms after eruption starts; cleanup
ends120ms later. Source stone and red-crack designs are unchanged.

Review timing: warning begins at0ms; the approved slam begins180ms later so its
unchanged1020ms fist contact lands at1200ms (two ticks). Spike reaches its peak
at1800ms (three ticks), then immediately descends; it is below floor at2400ms
(four ticks), with cleanup complete at2520ms. The approved slam's frames and
individual durations are untouched; only its start relative to the warning
changes. Boss damage timing remains the combat engine's responsibility.

## Godot use

Instantiate `res://scenes/Effects/TitanPhysicalSpike.tscn` once per authoritative
affected cell and position its root at that cell's world center. Add it to the
world's feet-sorted actor/effect container. Call
`sample_at_seconds(seconds_since_warning_started, warning_duration_seconds)`
from the encounter's shared clock. Defaults to two combat ticks/1.2seconds. It stays
hidden before/after the clip, does not autoplay or loop, and can be freed when
the returned phase is `complete`. All instances share one imported texture.

The effect has no collider, target selection, damage, health or boss logic.
The combat engine must supply the ten distinct scattered cells, include the
player's captured warning-start cell, retain an escape and own the eventual
damage timing. The preview fixture demonstrates that arrangement; it does not
implement the production selection algorithm or retarget a player who moves.

## Verification and status

`verify_assets.py` checks native sizes, binary alpha, atlas roundtrips, red
warnings, ground width, unchanged whole source at peak, immediate retraction,
lossless import settings and byte identity of the approved Titan neutral and
all eighteen slam frames. `res://scripts/dev_tools/titan_spike_test.gd` checks
timing, independent instances, hidden endpoints, engine-controlled warning
duration, exact tick boundaries, smooth small motion steps, native anchoring and
imported alpha/visible-pixel identity.

`res://scripts/dev_tools/titan_spike_review.gd` renders the exact authored
`titan_spike_world_review.tscn` with the unchanged Golem Kingdom and peasant at
runtime 0.75 scale. Ten unique 32px cells include the captured player cell; full
cell-floor checks, actual wall/body overlap queries and a 24px body-swept escape
are recorded outside Git. Artwork-only and cell-guide captures stay separate.
It samples3seconds at50fps: the complete slam at2x, a single tile beside the
player at4x and a normal1x view. Preview crops preserve actual GPU pixels and
sample durations.

The mandatory `worldbuilding.py` was run with `world-review-contract.json`
against this exact scripted development fixture. Its native-art gate passes;
its passive scene gate rejects the attached animation script as
`unsafe_resource_dependency`. This is an unsupported animated resource, not a
placement certificate. No validator was bypassed or unrelated passive prop
substituted. Production worldbuilding/encounter installation remains pending.

Artwork status: **candidate, pending user visual review**. Reusable effect is
installed in the project asset library; no live boss, map placement, collision,
damage balance, existing interface or actor catalog was changed. Approved
Titan idle/slam artwork remains unchanged. The old tiny Titan catalog entry is
untouched.

Rebuild: `py -3.13 art_sources/vfx/titan-physical-spike-v1/build_effect.py`, then
reimport the runtime atlas before running tests/review. Evidence and deliverable
previews live in the supporting workspace under
`work/character-animation/golem-titan-spike-v1/`. The current evidence and
deliverables use the `tick-paced` subdirectory; earlier fast previews are
superseded and retained only as history.
