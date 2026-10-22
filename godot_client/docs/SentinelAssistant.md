# Sentinel development assistant

Open **Aetheria Sentinel → Development assistant**. If Sentinel was already
running when its source was updated, close and reopen it from the desktop
shortcut. The companion, incidents, live log, Explain & chat and roadmap remain
available. The native conversation view uses an owned ChatGPT website session. Codex is a
separate implementation route with a reviewed credit budget.

## Discuss the game in ChatGPT

1. Open **Conversation → ChatGPT conversation**. Its native question box,
   Send/Stop controls and answer area match the Codex implementation layout.
2. Type a question in the top box and select **Send to ChatGPT**, or press Enter.
   Shift+Enter adds a line. The owned browser submits that explicit question on
   the normal ChatGPT website; rendered replies stream into the native answer
   area. This route does not call Codex or a consumer private API. ChatGPT's own
   account limits still apply. Failed sends retain your question for review;
   Sentinel does not automatically resubmit it.
3. Use **ChatGPT sign-in / website** when account sign-in or browser verification
   is needed. This opens a separate Sentinel-owned website window; closing that
   window hides it while preserving the session. The main question and answer
   boxes remain visible regardless of browser display problems.
4. **Add game context** adds local excerpts and decisions to the native question
   draft. Review it before sending. **Stop** requests the website's Stop action
   and retains partial answers. **Use this conversation in Codex**, or typing
   **let's implement the changes**, transfers the website conversation into a
   reviewed Codex task without starting a paid job.

The browser has its own persistent WebView2 profile under the project's local
Sentinel state directory. Its website sign-in is separate from the desktop
browser and the Codex connection. Sentinel reads rendered conversation turns
for handoff; it does not extract cookies, passwords or authentication tokens.
The existing **Explain & chat** tab keeps local incident explanations and routes
**Discuss in ChatGPT** and follow-up messages into this same draft flow.

When ready to implement, select **Use this conversation in Codex**, or send the
exact instruction **let's implement the changes** on the ChatGPT page. The
phrase is recognized only following a trusted composer interaction; loading an
old conversation does not trigger a handoff. A handoff copies the currently
rendered user/assistant conversation as reference evidence, bounded to the last
7,000 characters with an omission marker when needed. Earlier or unloaded
messages may be absent. Review and restore missing requirements before running.
It switches to **Codex implementation** and fills the task; it never launches a
paid job. You can also switch manually and type a coding task.

## Embedded browser setup

The pane requires the existing Sentinel Python runtime, **pywebview 6.1** and the
Microsoft Edge **WebView2** runtime on Windows. The browser dependency was
installed in the local bundled Python runtime during this upgrade. For another
machine, run `tools/setup_sentinel_browser.ps1` with the existing runtime and
install the Microsoft WebView2 runtime if absent. The renderer is an owned child
process, and closing Sentinel closes its browser process tree. A failed or closed
renderer can be retried without starting Codex.

## Review a coding task

1. On **Conversation → Codex implementation**, enter or bring over one task and
   choose a positive **Credits per stage** budget. Choose `audit` under
   **Advanced** for investigation or `implement` for one coding stage.
2. Select **Prepare Codex task**. Sentinel loads the installed Codex catalog and
   retrieves current relevant excerpts, approved rules and relevant prior
   checkpoints. Preparation makes no inference request. **Advanced → Prepare
   locally** also builds a preview without launching a job.
   **Project memory → Search locally** searches the source without using Codex.
3. If needed, use **Advanced → Connect Codex / Sign in**, complete the official
   browser flow, then reconnect and prepare again. This sign-in is independent
   of the embedded ChatGPT page. `Auto` recommends an available catalog model and
   supported effort; you can select another in Advanced.
4. Review the request, snippets, suggested files, model, mode, credit threshold
   and time limit. Select **Review & run stage** and confirm that specific stage.
5. Sentinel runs only this approved stage. Large migration/whole-game requests
   begin with a read-only audit. Read the result, choose validation if appropriate,
   and approve the next stage separately. There is no automatic expensive chain.

Codex jobs use the connected ChatGPT-backed Codex allowance. The assistant does
not select API-key billing automatically. Catalog discovery and thread creation
do not prove live model entitlement; a completed inference is needed for that.
Previous live model checks do not prove the current account can use every
catalog model. No inference is required to connect, prepare or inspect a preview.

## Budgets and oversight

The user chooses a positive **Codex credit** threshold for each paid stage.
No default spending budget is assumed. The time limit defaults to 600 seconds.
Credits and model text tokens are different units: the earlier 24,000-token
default addressed a text-context limit and did not control purchased credits.
That token-default claim has been corrected. Raw token counts remain technical
diagnostics; the current UI uses credits for the budget and does not install a
default text-token stopping limit. Credit/time preferences persist locally after
preparation. Standard service tier is requested, and delegation is disabled.

`account/rateLimits/read` supplies the account's purchased credit balance and
`ordinaryUsageAllowed` permission when available. The balance is account-wide:
other chats may spend it, so balance changes are never attributed to this job.
Missing balance or permission values are shown as unavailable, not zero.

For an owned job, Sentinel prefers `account/usage/read` with its `threadId` and
converts `threadUsage.estimatedUsageCreditsMicros` using one million micros per
credit. It polls while the job runs. New threads can legitimately lack a usage
report. For known standard-speed models, the fallback uses the published
[Codex credit rates](https://learn.chatgpt.com/docs/pricing), verified October 22,
2026: uncached input, cached input and output are priced separately. Reasoning
tokens are already included in output and are not counted twice. The UI labels
server estimates, published-rate estimates and reports still awaiting usage.
An unknown model without a matching server estimate is blocked before inference.
Missing token components do not become an invented zero-credit estimate.

The local overseer counts command completions, changed files, cumulative reported
usage and elapsed time. It warns about repeated reads/searches on an unchanged
indexed source revision, three failures of the same test without a source change,
and possible scope expansion beyond the retrieved file list. These are evidence
leads: legitimate dependency work or reasoning can still be necessary. Only
Sentinel-owned jobs can be controlled; independently opened desktop chats are not
monitored or interrupted.

At the credit/time threshold Sentinel requests an interrupt once. Usage events
arrive after computation, and cancellation takes time, so thresholds are **not
hard billing caps**. The user can also **Stop jobs**. A missing acknowledgement
or stopped server leaves an interrupted/disconnected receipt, not a success.
Closing Sentinel interrupts its jobs and closes their owned Windows process tree;
it leaves independently running Aetheria processes alone.

**Peer review** starts a separate read-only review of bounded task/diff evidence,
using the developer's selected model. It requires approval for a separately
chosen positive credit threshold and a 120-second time limit. There are at most
two reviews per Sentinel
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
user-directory access controls apply. Codex manages its own credentials; the
embedded browser separately manages its website session in its browser profile.
The core modules are independent of Tk for future shared hosting, but this release
has no online team synchronization, voice interface or multi-user authorization.

## Validation status — October 22, 2026

The signed-out official ChatGPT page was loaded in the embedded Windows pane.
The live page accepted a local draft without sending it. Its responsive mobile
composer is supported alongside the desktop composer; draft and trusted-submit
scripts also have execution-based regressions.
The user's authenticated website sign-in and conversation have not been verified.
No model inference was run for this conversation/credit-routing correction, and
no credit purchase or usage reset was performed. Earlier model probes belong to
the superseded direct-Codex question flow and do not validate this new route.

Automated checks use isolated temporary state, fake account/app-server replies
and local child processes. Browser scripts are executed against a fake DOM to
check valid JavaScript, draft preservation, origin restrictions and the absence
of Send/handoff side effects. Tests cover old-message loading, browser retry
cleanup, explicit handoff, credit arithmetic and missing estimates, review
approval, streamed results, cancellation and native Tk state. Credit thresholds
and account display are tested with synthetic reports; live billing enforcement
and paid peer review are unverified. Generated evidence remains outside source control.

Final validation: **100 automated assistant/Tk/browser tests, 49 diagnostic-chat
checks and 22 monitor checks passed (171 total)**. No model inference was used
for these checks. The normal website loaded and accepted a draft in a live
embedded pane; no message was submitted by the test.

Browser recovery correction: the live browser previously ignored retry while
its process was alive. Explicit retry now resizes/shows the browser, navigates
back to ChatGPT and checks page readiness. Automatic tab display and draft
insertion do not navigate. A live isolated test started at the OpenAI Help Center,
retried the same running renderer, and detected ChatGPT's composer within the
visible 1,024 × 255 viewport. No message was sent. The current workspace's full
automated Sentinel suite passed **114 tests**, including recovery/readiness
regressions. Native screenshot capture timed out, so no screenshot-based visual
verification is claimed. Authenticated chat remains a user sign-in check.

An initial monitor smoke run transiently failed its synthetic clean-shutdown-
marker assertion; a fresh run passed it. Another run exposed concurrent game
sessions overwriting the monitor test's last-exit receipt. The test now also
accepts retained activity for the exact test PID, preserving the requirement
that the companion stays running and observes that process's unexpected exit.
The complete monitor suite then passed all 22 checks. ADC and monitor production
code were not changed; no gameplay incident is marked resolved here.

Run the assistant regressions with the installed Python:

```powershell
python tools/test_sentinel_assistant.py -q
```

Protocol: [official Codex app-server documentation](https://learn.chatgpt.com/docs/app-server).
Implementation: `tools/sentinel_memory.py`, `sentinel_assistant.py`,
`sentinel_codex.py`, `sentinel_process.py`, `sentinel_chatgpt_pane.py`,
`sentinel_assistant_panel.py`, `sentinel_chat_panel.py` and the
existing `sentinel.py`. The installed binary's generated public JSON schema was
used to validate wire names; machine-specific evidence remains outside Git.

Native chat layout correction: question, send/stop and answer controls are now
Tk widgets matching the coding view. The website is reserved for sign-in and
session controls. Native layout/send/error/partial-answer/handoff tests and
JavaScript send/stop tests use fakes without inference. A live signed-out website
loaded behind the native interface with both text areas visible and zero Codex
jobs. Authenticated message submission and response extraction remain unverified
against the user's session; website changes may require updating the DOM bridge.
