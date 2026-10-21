# Aetheria Sentinel — independent desktop companion

**Open it:** double-click **Aetheria Sentinel** on your Windows desktop.
You can also run `./tools/sentinel.ps1` from the active game repository.
The shortcut starts a separate Python desktop application, without a terminal
or a running Godot editor. It uses the Python/Tk runtime already on this machine.
It is not a separately packaged `.exe`. Monitoring uses the existing runtime;
optional ChatGPT sign-in uses a per-user JWT verification dependency.

**Explain & chat** now offers plain-English local explanations and an optional
personal ChatGPT connection. See [SentinelChatGPT.md](SentinelChatGPT.md) for
sign-in, shared plan limits, data sent on request, and validation status.

## What you can do

* **Launch Aetheria** starts the installed game engine against this project,
  creates an attributable native log and watches the actual game process.
  The official Godot console forwarding wrapper is bypassed so it cannot be
  mistaken for an extra game process.
* The **Companion** tab shows live game status, unresolved incident count,
  the last observed exit, and a bounded activity timeline.
* **Incidents** leads with an everyday-language explanation and friendly issue
  names. **Technical details** reveals the original compact evidence. **Copy for
  Codex** always copies that precise evidence for investigation. Checked fixes
  show their recorded explanation and validation limits; new occurrences reopen
  the issue. **Explain latest** opens the newest report even after a fix.
  **Clear results** resets the current incident list and issues counter to zero.
  The list defaults to **Unresolved**. Clearing is saved across restarts;
  **All retained** still shows the original reports with a **Cleared** label.
  New incidents and new occurrences of a cleared report appear automatically.
  Clearing applies to the occurrences visible when you clicked, so an error
  arriving during the operation remains visible. Original evidence, native
  logs, and validated fix receipts are preserved. Clearing records your manual
  acknowledgement; verified resolutions still use the ADC validation workflow.
  **Open JSON** opens the full saved evidence.
* **Live log** follows native output incrementally, including errors before ADC
  has flushed an incident. It retains 400 lines, reads at most 64 KiB per poll,
  and labels skipped bursts. **Import this log** explicitly converts raw log
  errors to grouped incidents when needed.
* **Background** minimizes to the Windows taskbar and keeps watching.
  Restore Sentinel from the taskbar. This version does not use a system tray
  icon. Closing the Sentinel window exits the companion, leaving the game alone.
* **Choose Godot…** selects an existing engine executable if automatic local
  detection cannot find it. No engine is downloaded or upgraded.
* **Roadmap** preserves the gameplay brainstorm inside Sentinel. Switch between
  **Missing loops**, **Core mechanics**, and **Build next**. All six loop
  explanations, the existing foundations, and the proposed Roadside Job remain
  available without this chat or an internet connection. **Full brainstorm**
  opens [Roadmap.md](Roadmap.md) for the complete design notes and evidence.
  Check off work in any view; the same task stays synchronized across views.
  The overall counter counts each of the 18 tasks once, and individual loops
  and build stages show their related completion counts. Uncheck to reopen.
  Changes save immediately and the selected view/loop is remembered on restart.
  These are your manual completion records, not automatic code verification;
  the October 19 starting snapshot remains labeled separately.

You can leave Sentinel open all day with no game/editor running. It polls
locally once a second. Game termination does not terminate Sentinel. There is
no always-on AI model, voice service, automatic fix or recurring Sentinel
subscription. Monitoring never automatically uploads reports. Optional ChatGPT
analysis sends selected evidence only on request; sign-in briefly opens a
loopback callback listener. It uses your authorized ChatGPT plan allowance.

## Observation and limits

Sentinel observes ADC session markers, changed incident files, native log tails
and Windows process lifetime. It retains a handle to the original process to
read its exit code, rather than interpreting PID existence alone as a clean exit.
Native callbacks still live in ADC, inside the game; Sentinel itself does not
depend on the Godot scripting runtime. It does not inject a debugger, read game
memory, intercept all operating-system faults or guarantee a native crash cause.

Game launches from the editor are detected through ADC markers. For startup
failures before ADC starts, Windows Godot process discovery checks `--path`
against this specific project and excludes editor/project-manager processes.
Process command lines are inspected only when a Godot PID appears, discarded
after matching, and not persisted. Other applications are not monitored.
Exported games using a different executable name need a future explicit
executable integration.

**Use Sentinel's Launch Aetheria button for the strongest startup observation.**
A very short process launched elsewhere can start and disappear between polls.
Shared editor-launch native logs have weaker attribution than unique logs from
Sentinel. An observed missing shutdown marker is a suspected abnormal stop,
including deliberate forced stops; it is not proof of a native crash.

After a process exits, Sentinel preserves its last displayed native tail and
prepares/recover reports immediately, without waiting for a game restart. It
continues watching for the next launch. Startup failures without any ADC marker
can be imported or recorded as external process-exit evidence. It reports the
observed exit code and available logs, never an invented root cause.

GUI operations stay on Tk's main thread. File/process monitoring and report
preparation run on a separate bounded-queue worker. Incident JSON is cached by
modification time; normal polling does not repeatedly parse unchanged reports.
The activity ring holds 200 entries. Existing ADC/native retention limitations
remain documented in `Diagnostics.md`; original native logs are not truncated.

No Windows service, scheduled task or automatic login startup was installed.
To start minimized manually: `./tools/sentinel.ps1 -Background`.
Launching the desktop shortcut again restores the existing default window
instead of spawning another default companion.

## Local files

Sentinel uses the same `user://diagnostics` root as ADC. Additional local state:

| File under diagnostics | Purpose |
| --- | --- |
| `companion/activity.json` | Bounded activity history |
| `companion/last-exit.json` | Last externally observed exit and clean-marker status |
| `companion/last-log-tail.txt` | Last displayed native tail preserved after exit |
| `companion/settings.json` | Optional chosen Godot executable |
| `companion/roadmap-progress.json` | Manual roadmap completion timestamps and last selected view/loop |
| `companion/cleared-incidents.json` | Manually cleared occurrence counts/timestamps; new occurrences reappear |
| `companion/sentinel.ico` | Locally generated application/shortcut icon |
| `launches/sentinel-*.log` | Complete attributable original logs for companion launches |

Important code: `tools/sentinel.py` (GUI), `sentinel_monitor.py` (observer),
`sentinel_windows.py` (small Windows helpers), `sentinel.ps1` (launcher),
`install_sentinel.ps1` (desktop shortcut), and `test_sentinel.py` (regressions).
Use `./tools/install_sentinel.ps1` to recreate the shortcut after moving files.
The shortcut depends on the current repository and Python runtime paths.

Roadmap implementation: `tools/sentinel_roadmap.py` (content/state),
`tools/roadmap/loops.json` (the original six explanations), and
`tools/sentinel_roadmap_panel.py` (native interface). There are no additional
runtime dependencies. Progress writes are atomic; failed writes undo the
unsaved checkbox change and show an error. Invalid saved progress is preserved
and cannot be silently overwritten. Progress is stored locally outside source
control and is independent of ChatGPT sign-in and the running game.

Roadmap validation (2026-10-19): **10/10** new model/Tk tests, **22/22** existing
Sentinel checks and **49/49** chat integration checks passed. This includes
actual window close/reopen persistence, shared checkbox state, all six loops,
three views, minimum-window scrolling, write-failure rollback, corrupt-file
protection and continued monitoring/chat behavior. Windows screen capture
failed after retry (`window capture timed out: timed out waiting on channel`);
no screenshot-based visual pass is claimed. Run `python tools/test_sentinel_roadmap.py`
for the roadmap tests. `python tools/sentinel.py --roadmap` selects Roadmap when
starting a new Sentinel process; an already-running instance must be reopened
after installing updated source.

## Validation — 2026-10-19

**22/22 automated checks passed** with the installed Godot 4.5.1 engine.
Tests cover incremental/partial/burst/truncated logs, project/editor filtering,
normal launch and exact exit code, live native errors, forced test termination,
offline recovery, preserved tails, actual Tk rendering/model updates, incident
selection/filter/copy, background minimization, leaving a game alive when the
companion closes, and an actual standalone GUI process surviving an externally
launched test game's termination. All synthetic failures used isolated storage.

The initial pass exposed Godot's console-wrapper/child-PID distinction; the
launcher was corrected and all 22 checks then passed. Fatal native crashes
were not induced. OS screenshot inspection could not complete: the capture
helper returned `window capture timed out: timed out waiting on channel` after
a selection/activation retry. The real window and controls were exercised by
automated Tk tests; no visual screenshot pass is claimed.

Run the suite:

```powershell
python tools/test_sentinel.py --godot 'C:/path/to/installed/Godot.exe'
```

Local implementation evidence is in the task workspace's ignored
`work/diagnostics/sentinel-validation-v2/validation.json`.

Platform references:
[Godot crash evidence limits](https://docs.godotengine.org/en/4.5/tutorials/scripting/logging.html),
[Python Tk event/thread model](https://docs.python.org/3/library/tkinter.html),
[Windows process lifetime and exit codes](https://learn.microsoft.com/en-us/windows/win32/procthread/terminating-a-process).
