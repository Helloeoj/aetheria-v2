# Original online fishing responsiveness

The original FishingPanel and its artwork, mouse/A-D/Space controls, fish catalog, rods, skill tuning, bait costs, pale and rewards remain in use.

The server prepares the complete pull/dart plan after choosing the fish at cast commitment. Durations use the same 60 Hz timing and original RNG distributions. Snapshots carry the bounded plan until the client acknowledges it, then omit repeated plan contents. Full numeric plans avoid relying on matching RNG implementations across client/server engine versions.

`fishing_motion.gd` owns only preparation and motion. The authority calls this math and then resolves catch/loss and inventory/XP. Remote Fish calls only the math, so local time or reconciliation cannot grant a catch or reward. It accepts terminal outcomes only from the server.

The client predicts each render frame, sends steering on keyboard changes and at most 20 Hz for changing analog steering, and refreshes held input at 10 Hz. Steering and plan receipts use the same reliable RPC/serial ordering as other fishing commands but bypass inventory persistence waits. Cast, release and hook remain discrete server actions. Immediate pending phase feedback is reconciled with action acknowledgements. Release sends the displayed meter phase; the server accepts it only within 250 ms of its phase and derives power itself.

An echoed random start token keeps old panel acknowledgements from interrupting a pending recast. Encounter IDs prevent old-cast commands and samples affecting a later cast. Sample IDs reject duplicate/out-of-order snapshots. Each snapshot carries its authoritative sample clock and held steering value. Replay uses recorded simulation-time intervals after that clock, even when the steering state has already been acknowledged; it is bounded to 250 ms and 64 entries. Display corrections for lateral position, velocity, strain, remaining distance and fight time are limited and decay between samples. These offsets are removed before shared motion and prepared-plan stepping. Prediction stops after 250 ms without a fresh sample and on terminal state, close, death, disconnect or activity removal. Pending actions revert after one second without confirmation.

Run `tools/test_networking.py --godot <Godot 4.5.1 console executable>` for the integrated regressions. `fishing_responsiveness_smoke.tscn` exercises first-frame feedback at 30/60/144 FPS, jitter/loss, real authority with delayed fake transport, action/encounter validation, prepared variation, no fight-time RNG and reward isolation. Its optional `--baseline=<archived fishing_session.gd>` additionally compares independent original motion and rewards; the original source is deliberately not embedded in production.

Controlled simulation establishes next-render-frame response, not an internet latency or human difficulty guarantee. A stalled connection intentionally stops prediction after the bounded window.
