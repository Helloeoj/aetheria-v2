# Sentinel development assistant

Source: the owner's [shared design conversation](https://chatgpt.com/share/6ad99c1c-dc34-83e9-b354-df3105715064).
The current instruction authorizes implementation; repository AGENTS.md overrides
routine skill approval gates. Work in the active installation, preserve unrelated
catacombs work, validate and push a dedicated branch to Helloeoj/aetheria-v2.

## Outcome and scope

Extend the existing Python/Tk Sentinel, preserving diagnostics, incident chat and
roadmap. Optimize successful development per token. Local indexing, retrieval,
rules, checkpoints and oversight must require no inference or new dependencies.
Keep the core UI-independent for an eventual shared service; this release is local
and single-user. Voice and online multi-user hosting are future work.

## Memory and evolving intent

Use a project-specific SQLite database outside the repository and diagnostic
retention. Index eligible Git tracked/untracked source files, bounded text chunks,
symbols and resource relationships. Skip ignored/generated/binary/credential files,
symlinks and external paths. Stat caching avoids rereading unchanged files; content
hashes avoid rebuilding unchanged chunks. Handle deletion and unreadable files.
Periodic refresh runs on a worker, never on Tk's thread. Queries return bounded,
ranked, current source citations; indexed source is observed, never proof of a test.

Persist decisions as proposals and approved versioned rules, with supersession,
rollback and history. Only approved current rules enter task instructions. Source
changes invalidate verification receipts; stale citations must not be reused.
Record attempts, actual process validation receipts, unfinished tasks and usage.
Never call a feature verified merely because an agent says it passed.

## Assistant and budget

Natural-language requests produce local search answers and a compact task preview:
request, relevant snippets/paths, approved rules, one stopping point, validation
command, model/effort and time/token budgets. Large requests start with a focused
read-only audit; implementation stages require their own approval. Show estimated
context size separately from observed model usage. Route routine tasks toward
catalog-advertised Luna and complex tasks toward Sol, with compatible effort and
manual override; do not assert prices, entitlement or exact quota savings.

Connect to the installed Codex app-server over owned stdio using its public
protocol. Use its supported sign-in/account flow; never read credentials, cookies
or another app's private transcript/database. Discover model/effort capabilities.
Starting a reviewed task is explicit approval and may consume the existing Codex
allowance. No automatic paid continuation, model escalation or extra agents.
Use read-only sandbox for questions/audits/reviews and workspace-write for approved
implementation. Handle server approval requests in the UI; decline unsupported
requests, never silently grant them. Fail closed on transport/account errors.

## Overseer and review

Observe only Sentinel-owned jobs. Count cumulative token updates, commands, file
changes, repeat unchanged reads/failed tests, scope expansion and elapsed time.
Local warnings are evidence leads, not conclusions. Interrupt once at token/time
threshold; usage events are delayed, so this is not a hard billing cap. Persist a
bounded efficiency report after completion, cancellation, disconnect or timeout.

User-requested peer review runs in a separate read-only job with its own small
budget and bounded relevant diff/evidence. Show findings; allow a short explicit
correction to the active developer turn. Limit repeated reviews/corrections and
require new evidence. Do not start an autonomous AI debate. Closing Sentinel must
interrupt its active jobs and release its app-server, leaving Godot alone.

## Validation and limits

Test incremental indexing/deletion/secret exclusion, bounded retrieval, stale
source, version transitions and rollback, persistence/corruption, usage duplicate
events, repeat operations with actual file changes, scope, timeout/interrupt,
review budget/approval, cancellation/transport errors and real Tk integration.
Exercise the installed app-server handshake/catalog without paid inference.
Run existing Sentinel suites. Live model execution is reported separately from
synthetic protocol tests. Do not claim actual token savings before measuring them.
