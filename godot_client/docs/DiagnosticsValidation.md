# ADC implementation validation — 2026-10-19

Engine: **Godot 4.5.1.stable.official.f62fdbde1**, Windows, headless.
Existing main-scene baseline passed before integration. No engine upgrade.

| Validation | Result |
| --- | --- |
| ADC end-to-end suite (`tools/adc.py --godot <installed-engine> test`) | **24/24 checks passed**, including a 20-assertion runtime scene |
| Existing `world_interaction_smoke.gd` | **58 checks, 0 failures** |
| Existing `check_camera_controls.gd` | **38 checks, 0 failures** |
| Existing `scenes/dev_tools/bronze_combat_smoke.tscn` | **2,558 checks, 0 failures** |
| Installed-engine editor scan and actual game startup/shutdown | Passed; no parser/runtime errors in ordinary main-scene run |
| PowerShell launcher with `run -- --headless --quit-after 20` | Passed; unique native log and clean session marker |
| Python tool compilation and relevant tracked-file whitespace checks | Passed |

ADC checks cover native runtime errors, freed references, missing resources,
worker-thread errors, 500-to-1 deduplication with exact count, bounded circular
history, source/backtrace capture, redaction/object omission, JSON/compact
report persistence, offline preparation, schema fields, killed-process and
post-restart/offline recovery, live-process exclusion, failed disk access,
disabled mode, failed scene changes, overflow accounting, count/byte retention,
native crash-signature preservation from a **labelled fake fixture**, early
startup log import/idempotence, damaged evidence and validation-gated
resolution/reopening. Synthetic incidents were isolated from normal reports.

The first test pass exposed shutdown-provider and storage-fault edge cases;
both were fixed, and the revised suite passed. The PowerShell launcher's
argument forwarding was also corrected and verified using a real game run.
An early command-line test harness loading PlayerState before autoloads was
replaced by a proper test scene. Those development failures remain in the
local test evidence; they are not hidden or represented as successful runs.

No actual fatal native crash, power-loss scenario, GPU/shader/physics fault,
multiplayer connection, or exported release build was tested. Native crash
handling is therefore validated only through safe process termination and
labelled log-signature fixtures. No resolved gameplay bug is claimed: the
resolution test exercises workflow mechanics using explicitly synthetic
incidents; relevant regression commands remain the fixing agent's responsibility.

Full local test evidence is in the task workspace's ignored
`work/diagnostics/validation-final/validation.json` and adjacent native/console
logs. Separate interaction, camera, and bronze-combat logs are in that same
`work/diagnostics/` parent. Use the task's `CRASH_HANDLER.md` to find it.
