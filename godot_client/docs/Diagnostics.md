# Aetheria Diagnostic Core (ADC)

ADC is installed as the **first autoload**, before GameData. It extends Godot's
native Logger stream and preserves native file logging. No network service,
API, subscription, AI call, engine upgrade, or gameplay refactor is involved.

For an interactive independent desktop window, open **Aetheria Sentinel** from
the Windows desktop shortcut. It watches while Godot is closed and survives a
game exit. See [Sentinel.md](Sentinel.md) for controls, limits and validation.

## Start debugging

From the repository root in PowerShell:

```powershell
./tools/adc.ps1 prepare # prints the newest unresolved compact report
./tools/adc.ps1 paths   # prints exact storage/report paths
./tools/adc.ps1 list    # lists open and resolved retained incidents
./tools/adc.ps1 test    # isolated headless regression suite
./tools/adc.ps1 run    # optional: start game with a unique attributable native log
```

The wrapper uses the bundled Python if present, otherwise `python`. For `run`
and `test`, it uses `$env:GODOT` or a running Godot executable. Set `$env:GODOT`
to your installed engine if necessary. It never downloads an engine.
Other platforms can use `python tools/adc.py`; engine-specific operations take
`--godot /path/to/godot` **before** the subcommand.

When asking Codex for help, say **“Debug Aetheria's latest ADC incident.”**
The repository's AGENTS.md tells the agent to read compact evidence first.

## Reports and evidence

Default storage for the current project name on this Windows installation:

```text
C:/Users/Riptide/AppData/Roaming/Godot/app_userdata/Aetheria (Arcade Test Client)/diagnostics/
```

Paths are derived from Godot's user directory; do not hard-code this user's
path into new code. `paths` discovers the local location. Environment variable
`AETHERIA_DIAGNOSTICS_DIR` overrides it for both ADC and the CLI. Python's
`--root <path>` affects the CLI; `run` forwards it to the child game.

| Path under diagnostics | Purpose |
| --- | --- |
| `latest.txt` | Single small entry point: newest unresolved compact report |
| `unresolved.txt` | Paths to all retained unresolved compact reports |
| `resolved.txt` | Resolved history index, rebuilt by `prepare` |
| `sessions/<session>/incidents/<incident>.txt` | Compact observed evidence and source leads |
| `sessions/<session>/incidents/<incident>.json` | Detailed v1 incident; full captured frames and context |
| `sessions/<session>/session.json` | Start, PID, context checkpoint, shutdown/recovery marker and overflow counts |
| `resolutions/<incident>.json` | Validation receipt; recurrence reopens the incident |
| `resolutions/<incident>.validation.log` | Recorded test command output |
| `catalog.json` | Prepared status, unreadable reports, cross-session matching fingerprints |
| `retention.json` | Most recent retention removal summary |
| `launches/` | Unique original native logs when using the optional `run` command |

Ordinary editor launches keep the complete native logs in
`user://logs/godot.log` and rotated siblings (**8 files**). ADC does not disable
native console output, engine warnings, the debugger, or the crash handler.
Custom `--log-file` is not exposed in Godot's retained argument list on this
build; set `AETHERIA_NATIVE_LOG` to the same file for accurate ADC references.
The `run` command does this automatically. No `.env` or credentials are read.

`prepare` recovers unclean sessions even without restarting the game. It does
not read raw logs for routine incidents; recovery only scans bounded 1 MiB
native tails for crash signatures. Shared rotated native logs are explicitly
labelled attribution candidates, not proof they belong to a particular session.
With the optional launcher, each session's native log is unambiguous. A found
crash tail is copied to the old session before it can rotate away.

For errors **before the autoload starts**, such as a startup/parser failure:

```powershell
./tools/adc.ps1 import-log 'C:/path/to/godot.log'
```

This explicitly imports/group errors with only locations present in the native
text. Import timestamps are labelled import time; unavailable context stays
unavailable. Reimporting an unchanged file is idempotent. The optional launcher
imports early errors automatically when ADC never initialized. Original logs
remain unchanged. Editor-only errors need this import or the editor debugger:
the game autoload cannot observe errors inside a separate editor process.

## What is captured

Native `_log_error` covers reported GDScript/runtime, invalid/freed-object,
resource, shader, rendering, collision/physics and other engine errors, with
available GDScript frames and the engine origin kept separately. `printerr`
messages are captured with source marked unavailable. Ordinary `print` output
stays in native logs; warnings are excluded from incidents by default.

Explicit breadcrumbs currently cover JSON resource loading; character startup,
monster spawn/despawn; backpack adds/removes; equip/unequip; and ground item
spawn/pickup/drop. Unknown equipment items and unknown spawn templates are
explicitly reported. Expected game-rule rejections (such as a two-handed weapon
blocking a shield) are ordinary breadcrumbs, not stability errors.

The main game supplies scene, map, stable player/target IDs and simulation
position through a direct callable. There are **no scene-tree searches**.
Context is sampled on initialization/scene changes and every 2 seconds, so
position may be up to one interval old. Breadcrumb snapshots are taken at
error time. Providers are never called on logger worker threads or after
their scene leaves the tree.

No completed networking exists: the dormant NetworkManager is a placeholder,
and server scripts are local demos. ADC does not invent connection telemetry.

## Implementation and limits

The installed engine was verified as **4.5.1.stable.official.f62fdbde1** and
the active game uses GDScript. Python is legacy gameplay/offline tooling; no C#
or GDExtension implementation was found. Existing development checks are
lightweight Godot smoke scenes/scripts; no third-party test framework is added.
Before ADC, logging was native `print`/`push_error`, without custom crash
reports. GameData was the sole active autoload and the main scene was
`EastOutskirtsLayered.tscn`, which initializes the existing gameplay adapter.
The scene-transition helper is available for future use; current gameplay has
no scene-transition service to replace. No assets/maps were changed.

* Logger callbacks do no I/O, scene access, gameplay callbacks, or printing.
  A mutex protects the bounded pending map, circular event history and copied
  primitive context. No game Objects or captured local variables are retained.
* A deterministic SHA-256 groups by category, system, message, code, source,
  engine origin and up to eight call frames. Explicit timestamps, pointer
  addresses and labelled instance IDs are normalized; resource names, item
  numbers and distinct source locations are preserved. Incidents are per
  session; `catalog.json` relates matching fingerprints across sessions.
* Counts and first/last occurrence times are preserved. Each incident retains
  the first error snapshot, latest context/events, and up to four changing
  samples across flushes. Within a batch, first/latest snapshots are kept.
  Routine reports aim for 1–3k characters; long evidence references can expand
  them. Captured messages/code are bounded; native originals remain available.
* Default history: 64 events (configurable 8–256). Pending/stored incident
  count: 128 each (8–256 configurable). Excess unique errors increment an
  explicit `dropped_occurrences` counter; originals remain in native logs.
  Event payloads/keys/strings/depth and backtraces are bounded. Oversized
  context is labelled truncated. No per-frame diagnostic processing is added.
* Flushes are batched every 2 seconds; quiet-session context checkpoints are
  every 10 seconds. Errors trigger a checkpoint at flush. Sudden termination
  can lose the pending interval. Start markers and flushed files improve
  recovery but cannot guarantee writes survive power loss or disk failure.
* Reports use same-directory temporary files plus replace, with flush/close.
  Invalid JSON is skipped without overwriting its evidence. Storage faults
  latch into bounded in-memory capture instead of repeatedly failing writes.
* Defaults retain 16 sessions with a 64 MiB ADC session-data target. Startup,
  and error flushes at most once per 30 seconds, prune oldest closed/recovered
  sessions. Live sessions are protected, so this byte target is **soft while
  live sessions need the space**. Retention expires old evidence; copy an
  incident outside managed storage before keeping it permanently.
* Native original logs have engine file-count retention, **no Godot 4.5
  per-file byte cap**. An error spam can still enlarge a native log: ADC groups
  reports without suppressing the engine's only original evidence. Launcher
  logs and validation receipts are preserved until deliberately archived or
  removed. `storage_limit_mb` governs session data, not those originals.
* A missing clean marker means **suspected abnormal termination**, including
  forced stops/editor stop/power loss. Live PIDs are skipped; PID reuse may
  conservatively delay recovery. Parallel sessions have separate markers.
* GDScript cannot catch a fatal native crash after its runtime has stopped.
  Godot records native evidence when possible; official binaries lack native
  debugging symbols. Release backtraces require
  `debug/settings/gdscript/always_track_call_stacks=true`. ADC defaults on in
  development and off for release; opt in deliberately for release diagnostics.
* Named sensitive payload keys and credential assignments are redacted. ADC
  records no environment dump, variables, authentication details or personal
  profile. Existing raw game/engine prints are original evidence and are not
  retroactively sanitized. Do not add credentials to gameplay events/prints.

Configuration is under `aetheria/diagnostics/*` in Project Settings:
`enabled`, `event_history`, `max_incidents`, `flush_seconds`,
`retained_sessions`, `storage_limit_mb`, `include_warnings`.
`AETHERIA_DIAGNOSTICS=off` guarantees no-op gameplay hooks and no ADC output;
`on` explicitly enables it. This does not switch off Godot's own logging.

Verified API references:
[Godot 4.5 logging](https://docs.godotengine.org/en/4.5/tutorials/scripting/logging.html),
[Logger](https://docs.godotengine.org/en/4.5/classes/class_logger.html),
[ScriptBacktrace](https://docs.godotengine.org/en/4.5/classes/class_scriptbacktrace.html).

## Add useful context without expensive instrumentation

```gdscript
AetheriaDiagnostics.event("Equipment", "equip item", {"item_id": item_id, "slot": slot})
AetheriaDiagnostics.report("Equipment", "Invalid equipment state", {"item_id": item_id})
# For a future scene transition, prefer the checked helper:
var result := DiagnosticCore.change_scene("res://scenes/SomeActualScene.tscn")
```

Record a short stable identifier and operation before an important action.
Do not log every movement/frame, whole item dictionaries, game Objects, player
names, credentials, or network messages. The next useful integrations are
actual networking failure boundaries when networking exists, explicit failed
animation/resource-result checks, and future scene-transition call sites.

## Regression and resolution

```powershell
# After writing and running a relevant reproducer/regression test:
python tools/adc.py resolve ADC-... --note 'Reproduced and fixed the reported failure' --test /path/to/godot --headless --path godot_client res://path/to/relevant_test.tscn
```

The command must succeed; failed validation leaves the incident unresolved.
Resolution receipts preserve the executed command and output. The CLI cannot
prove a chosen test is meaningful: the fixing agent must confirm it covers the
failure. A recurrence beyond the verified occurrence count reopens the report.
Resolved history is retained with the corresponding evidence under the session
retention policy. A new session's recurrence starts a new linked incident.

The ADC suite includes real controlled runtime/freed-object/resource/thread
errors, 500-error deduplication, context/source/JSON/compact verification,
equipment ownership and two-handed shield rules, normal and killed-process
shutdown/recovery, live-process exclusion, offline recovery, bounded overflow,
session/byte retention, unavailable storage, disabled hooks, failed scene
transitions, malformed evidence and validation-gated resolution/recurrence.
It uses isolated output, not real game incident storage. A native fatal crash,
power loss, GPU failure, actual shader/physics faults and release exports were
not induced/tested. Native crash-signature parsing can be tested using a
labelled text fixture; it is not evidence of a real native crash.
