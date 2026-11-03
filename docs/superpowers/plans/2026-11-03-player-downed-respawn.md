# Player downed state and respawn plan
Goal: lethal damage downs players for 30 seconds, allowing revival in place before forced respawn at the existing Valtheris outskirts spawn.
Design: share recovery rules between offline/server simulation. Persist elapsed downed time, publish snapshots, add a countdown and reuse scene travel/region transfer. Full health on respawn, no equipment, inventory, gold or XP loss. A trusted revival method accepts caller-selected HP; the resurrection spell remains future work.
Approach: PlayerState stores the timer; existing authority and travel own transitions. Client-only timing loses reconnect state; editing each damage source duplicates death handling.
Constraints: active installation, preserve unrelated dirty work, no agents, two failed fixes maximum per problem. No prop or map changes.
- [x] Failing regression: timing, revival, repeated death, saved timer and server simulation.
- [x] Implement rules, HUD, offline travel and authoritative transfer.
- [x] Focused regression, editor/startup checks and actual game captures; self-review task diff, commit and push.
Review focus: reconnect timer, stale inputs/attacks, deadline race, same-region respawn, failed destination.

Validation: recovery rule/codec/region smoke and actual rendered game smoke both report zero failures. Editor import and main startup emitted no script errors. Real 4x downed/respawn captures inspected. Actual host geometry transfer tested with persistence stubbed; no live account-service deployment was performed. Final review performed by the author under the no-subagent requirement. Existing unrelated work is excluded from staging.

## Immediate respawn follow-up
Add a Respawn now button below the existing countdown. Offline uses the existing recovery travel. Online submits a schema-validated respawn intent accepted only for a downed actor; it expires the revival window and the existing host transfer/persistence handles arrival. Keep automatic timeout and revival unchanged. Verify actual button activation, retained progression and server rejection while alive using the existing rendered game smoke, then commit/push only this delta.
