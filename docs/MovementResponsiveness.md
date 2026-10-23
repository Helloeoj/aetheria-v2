# Online movement responsiveness

The local character predicts keyboard movement each rendered frame using the
existing map collision and four-tile/second speed. Server-owned actor/player
coordinates, combat and saves remain authoritative. Key changes send immediately;
held input still refreshes at 30 Hz. The world remains at 30 Hz and snapshots at
10 Hz. Gameplay tick timing and existing controls are unchanged.

Each snapshot includes simulation time, its publication interval, the latest
accepted movement sequence and how long that direction has been installed.
The client restores the live actor position and replays only pending frame time,
not a full input lifetime per refresh. It also preserves pending frames when a
snapshot predates the first acknowledgement. Small corrections ease visually;
large corrections, death, freeze and new map views reset prediction. Without
fresh snapshots speculation stops after 250 ms. Durable checkpoints are never
used as live movement positions.

Other actors interpolate between timestamped snapshots, one snapshot interval
behind the latest timeline. Missing packets hold their latest known position.
The local character uses immediate reconciliation smoothing for server-driven
click walking/chase, without the remote interpolation delay. Click destinations
and chase are still server-driven; this change does not add offline path routing
or predict combat outcomes.

Accepted movement-affecting commands have a separate monotonic sequence boundary
across reliable actions and unreliable keyboard input. An old click cannot
override newer keyboard input after an awaited save. Travel cannot lower that
boundary while loading a destination. Inventory commands retain their own
reliable ordering. Ordinary autosaves do not disable prediction; an actual
persistence or ownership freeze does.

## Validation on October 22, 2026

- `tools/test_movement.py --godot <Godot-4.5.1-console>`: three focused tests,
  73 checks, zero failures. Covers next-frame input/release, replay, missing
  acknowledgements, collision, speed, freezes, keyboard-to-click transitions,
  server ordering and remote packet gaps/teleports.
- Deterministic one-second 60 FPS / 10 Hz comparison: snapshot-only positions
  changed on 9 frames; predicted movement changed on all 60. First response is
  one 60 Hz frame (16.67 ms) in that controlled test.
- Real local ENet/account/PostgreSQL round trip: first rendered input responses
  of 13.37 ms and 13.31 ms in two sessions; 24 session checks passed. Logout and
  login restored the same character, progression and final position.
- Existing networking suite: 11 tests passed, including collision/speed,
  persistence, freeze, region travel, snapshot assembly and original minigames.
- Headless editor import and normal main-scene startup passed.

These timings measure local input-to-sprite response in headless test sessions,
not monitor presentation latency or remote Internet latency. Public networking
and player-capacity testing remain separate work. Evidence stays outside Git.
