# Sentinel development assistant

Open **Aetheria Sentinel → Development assistant**. If Sentinel was already
running when its source was updated, close and reopen it from the desktop
shortcut. The companion, incidents, live log, Explain & chat and roadmap remain
available. The development assistant uses the existing Python runtime and
installed Codex; it adds no package dependency or service.

## Ask a question

1. Open **Ask Sentinel**, type your question, then press **Enter** or select
   **Ask Sentinel**. Shift+Enter adds a line.
2. Sentinel connects to the installed Codex, loads its model catalog, retrieves
   relevant local source and sends a read-only question. No separate Connect,
   Prepare or Run step is needed. Sending a question uses your Codex allowance.
3. Read the streamed answer in the answer area. A progress indicator and status
   remain visible while it connects, reads or writes an answer. Errors and stop
   reasons appear in that same area; the Ask button becomes available to retry.

Questions cannot edit files or accept elevated permissions. **Stop** cancels a
pending connection before inference when possible, or interrupts a running job
while preserving its partial answer. If sign-in is needed, the visible error
points to **Advanced → Sign in** and the browser flow. No password/token copying
is needed. Model and budget controls are under **Advanced**, and local indexing
status stays on **Project memory** without replacing an answer or error.

## Review a coding task

1. Describe the task on **Ask Sentinel**, then open **Coding tasks & settings**
   (the **Advanced** tab). Choose `audit` for investigation or `implement` for
   one coding stage. Questions work directly on the first tab.
2. Select **Prepare locally**. Sentinel retrieves current relevant excerpts,
   approved rules and relevant prior checkpoints. Preparation makes no AI request.
   **Project memory → Search locally** searches the source without using Codex.
3. Use **Connect Codex** to load the installed app-server's account and model
   catalog. If needed, use **Sign in**, complete the official browser flow, then
   reconnect. This connection is distinct from the incident ChatGPT connection.
   It does not inspect passwords, browser cookies, identity files or other chats.
4. Prepare again after connecting. `Auto` recommends a catalog model and supported
   effort; you can select another. Review the request, snippets, suggested files,
   mode, token threshold and time limit, then **Review & run stage**.
5. Sentinel runs only this approved stage. Large migration/whole-game requests
   begin with a read-only audit. Read the result, choose validation if appropriate,
   and approve the next stage separately. There is no automatic expensive chain.

Codex jobs use the connected ChatGPT-backed Codex allowance. The assistant does
not select API-key billing automatically. Catalog discovery and thread creation
do not prove live model entitlement; a completed inference is needed for that.
The initial installation used synthetic inference; the question-flow fix below
also has a completed live inference and UI validation.

## Budgets and oversight

Defaults are 24,000 observed tokens and 600 seconds for a development stage.
The previous shipped 12,000-token preference is migrated to 24,000; other saved
custom thresholds remain unchanged. The installed Codex used 14,496 total tokens
for a tiny live probe, almost all startup input context. That exceeded the old
default before a one-line answer could finish. A character estimate of the task
alone cannot detect that overhead. This correction allows a request to start;
it does not claim to reduce the underlying harness input or guarantee a token cost.
Thresholds, mode and effort persist locally after preparing a task. Estimated
context tokens use a rough character heuristic and exclude Codex's own loaded
instructions and future tool output; they are not a usage quote. Image processing
adds usage beyond the text estimate. Too-small text thresholds are rejected before
launch. Standard service tier is requested, and delegation is disabled.

The local overseer counts command completions, changed files, cumulative reported
usage and elapsed time. It warns about repeated reads/searches on an unchanged
indexed source revision, three failures of the same test without a source change,
and possible scope expansion beyond the retrieved file list. These are evidence
leads: legitimate dependency work or reasoning can still be necessary. Only
Sentinel-owned jobs can be controlled; independently opened desktop chats are not
monitored or interrupted.

At the token/time threshold Sentinel requests an interrupt once. Usage events
arrive after computation, and cancellation takes time, so thresholds are **not
hard billing caps**. The user can also **Stop jobs**. A missing acknowledgement
or stopped server leaves an interrupted/disconnected receipt, not a success.
Closing Sentinel interrupts its jobs and closes their owned Windows process tree;
it leaves independently running Aetheria processes alone.

**Peer review** starts a separate read-only review of bounded task/diff evidence,
using the developer's selected model. It requires approval for a separate
24,000-token/120-second threshold, including harness input. The original 3,000
total-token limit was likewise below observed startup input. The higher review
threshold is displayed before its separate approval. There are at most two reviews per Sentinel
session; a second review needs new evidence. Read the findings and use **Send
correction** to steer the active developer turn. Corrections are explicit,
bounded to 2,000 characters and limited to three per developer job. Reviews and
corrections never start an autonomous back-and-forth debate.

If Codex requests a command/file approval, Sentinel displays the request and sends
the owner's decision for that request only. Unsupported requests are declined.
Questions, audits and reviews use Codex's read-only sandbox; implementation uses
workspace-write. These rely on the installed Codex sandbox support and do not
grant general Windows access or silently accept an escalation.

## Memory, evidence and evolving rules

The source index uses SQLite full-text search, symbols, source line numbers and
resource references. It watches eligible Git tracked/untracked text under
`godot_client`, `tools`, `docs`, plus root instructions/README. Refresh runs every
15 seconds on a worker and again before preparing/starting a job. Unchanged stat
records avoid file reads; hashes avoid unnecessary chunk rebuilding. Deleted,
unreadable or changed sources cannot supply stale citations. Gameplay searches
prefer implementation over test fixtures, while test-oriented queries can retrieve
tests. This is lexical retrieval, not a claim that Sentinel understands every
gameplay system or possesses general game-development expertise.

Ignored files, assets/binaries, legacy trees, generated diagnostics, dot-directories,
credential filenames, credential-like source, symlinks and paths outside the project
are excluded. Files above 512 KB and projects above 12,000 eligible files are
bounded. Thus source fingerprints and validation freshness apply to the **indexed
source**, not every asset, service or external dependency. Stat-cache limitations
also apply if content is altered while preserving its size and modification time.

**Add evidence…** selects up to five compact text files or screenshots for the
next stage. Duplicate content is removed. Text must be UTF-8, under 64 KB each
and 6,000 characters combined; supported images are PNG, JPEG and WebP under
10 MB each. Credential-like text is rejected. Review screenshots for private
content yourself. Evidence is sent only with a reviewed job. Changed evidence,
source or approved rules invalidate its prepared preview. Raw native logs and
all game source are never uploaded automatically.

Under **Rules & decisions**, propose a topic and intended design, review it, then
**Approve selected**. Proposals stay separate from approved intent. A newly approved
version supersedes the previous version of the same topic; **Restore old version**
appends a restoration while retaining history. Rules change task preparation, not
the game implementation. No feature becomes implemented just because a rule says
it should exist. Sentinel does not rewrite its own code or promote unreviewed
proposals. Existing project AGENTS.md instructions still apply to Codex jobs.

## Validation and efficiency history

An optional reviewed validation command is a JSON array of executable and
arguments, run directly without a shell. For example, to validate the assistant:

```json
["C:/path/to/python.exe", "tools/test_sentinel_assistant.py", "-q"]
```

After a completed job, **Run validation** shows and runs that command locally.
Validation has a maximum 120 seconds in this UI, retains an 8,000-character output
tail and terminates its owned subprocess tree on timeout or cancellation. Use a
check relevant to the task, then inspect its result. An exit code alone cannot
prove every aspect of a feature, especially a Godot process that logs script errors.

**History & efficiency** retains job status, model/effort, usage when available,
repeat warnings, answer, failures, interruption and the selected command receipt.
A validation badge requires an actual locally recorded successful command with
matching source before/after; agent prose never earns that badge. Later indexed
source changes invalidate current-source verification, while historical receipts
remain. Running records without completion are unfinished checkpoints, not proof
of an active job after restarting Sentinel. Relevant checkpoints enter later task
previews to reduce repeated investigation.

After at least three measured successful selected validations in the same broad
routine/complex task category, the model advisor can recommend an available model
with lower average observed tokens. Any failed/unverified measured sample prevents
that candidate's promotion. This is a small local heuristic, not a learned code
model, a pricing calculation, or evidence of actual quota savings. The proposed
model is visible before every launch; no automatic escalation or extra AI occurs.

Local state lives at
`%LOCALAPPDATA%/AetheriaSentinel/projects/<project-path-hash>/memory.sqlite3`
(plus SQLite WAL/SHM files), outside the repository and diagnostic retention.
It contains source excerpts, decisions and development receipts; normal Windows
user-directory access controls apply. Credentials remain managed by Codex itself.
The core modules are independent of Tk for future shared hosting, but this release
has no online team synchronization, voice interface or multi-user authorization.

## Validation status — October 22, 2026

New regressions cover incremental source retrieval, rules/rollback, privacy filters,
attachments/stale previews, checkpoints/actual validation, timeout child cleanup,
catalog routing/advisor, cumulative usage/repeats, scope/time limits, owned-job
lifecycle, peer-review approval and native Tk integration. Tests use isolated
temporary projects and synthetic app-server replies, including a real stdio child
process. Existing Sentinel suites are also required.

Final validation: **33 assistant regressions, 23 roadmap/clear tests, 22 monitor
checks and 49 ChatGPT integration checks passed (127 total)**. Generated reports
remain in the supporting workspace rather than source control.

Question-flow correction: **71 automated model/Tk tests, 22 monitor checks and
49 ChatGPT integration checks passed (142 total)**. This adds nine backend and
six question-interface regressions, including a one-click read-only launch,
visible connection failure/retry, streaming, cancellation before launch, and
coverage for the measured startup-context budget defect.

The installed Codex 0.163.0-alpha.10.2 completed the real initialization handshake,
reported a ChatGPT-backed account, returned seven catalog models and accepted a
read-only thread configuration. The corrected one-button UI was then tested live
on this project with catalog-selected GPT-6 Luna, medium effort and standard tier:
the answer appeared in the answer area and the job completed at **17,729 observed
tokens**, with **zero commands, file changes or interruptions**. A first tiny
probe at the old 12k limit received an answer but was interrupted at 14,496 tokens,
reproducing the budget defect. No live paid peer review or measured token savings
are claimed. Native Windows screen capture timed out
after an activation retry; automated Tk layout/control checks passed, and no
screenshot-based visual pass is claimed.

Run the assistant regressions with the installed Python:

```powershell
python tools/test_sentinel_assistant.py -q
```

Protocol: [official Codex app-server documentation](https://learn.chatgpt.com/docs/app-server).
Implementation: `tools/sentinel_memory.py`, `sentinel_assistant.py`,
`sentinel_codex.py`, `sentinel_process.py`, `sentinel_assistant_panel.py` and the
existing `sentinel.py`. The installed binary's generated public JSON schema was
used to validate wire names; machine-specific evidence remains outside Git.
