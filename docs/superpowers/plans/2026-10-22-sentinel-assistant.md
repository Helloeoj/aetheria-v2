# Sentinel Assistant Implementation Plan

> Execute inline using superpowers:executing-plans and test-driven development.
> The owner authorizes routine implementation/testing/commit/push; no extra agents.

**Goal:** Install a useful local assistant with persistent memory and governed Codex execution.
**Architecture:** SQLite memory and pure context/governor models, an owned stdio
app-server transport/controller, and a worker-backed Tk panel in existing Sentinel.
**Tech stack:** Existing Python/Tk, SQLite, Git and installed Codex; standard library only.
**Spec:** ../specs/2026-10-22-sentinel-assistant-design.md

## Global constraints

- Preserve existing diagnostics/chat/roadmap and unrelated active working files.
- Local single-user state outside Git; no credential reads or automatic inference.
- Reviewed per-stage launch, finite budgets, no automatic AI review or extra agents.
- Observed source, approved intent and verified process evidence remain distinct.

## Review focus

- Ignored secrets, symlink escape, unreadable/deleted sources: excluded or invalidated.
- Changed files and rules after preview: require rebuilding before execution.
- Late/duplicate events and exhausted budget: interrupt once, never restart automatically.
- Failed validation, disconnected server and app close: preserve accurate unfinished receipt.
- Narrow windows, background workers and queued callbacks: remain responsive and close safely.

## Task 1: Persistent memory and rules

Files: tools/sentinel_memory.py, tools/test_sentinel_assistant.py.
Interfaces: ProjectMemory.refresh(), search(query, limit), context(query, max_chars),
propose_rule(key,text), approve_rule(id), rollback_rule(id), checkpoint(), history().
- [x] Write and run failing behavioral tests for refresh/deletion, privacy boundaries,
  bounded current citations, rule approval/supersession/rollback and test receipts.
- [x] Implement SQLite transactions, chunk index, current-source retrieval and receipts.
- [x] Run the memory tests with the bundled Python; expect all passing.

## Task 2: Context, usage governor and app-server

Files: tools/sentinel_assistant.py, tools/sentinel_codex.py, same test module.
Interfaces: build_task(memory,request,...), Governor.observe()/tick()/report(),
AppServer.request()/notify()/close(), AssistantController launch/interrupt/steer/review.
- [x] Write and run failing tests for compact tasks, catalog routing, repeated work,
  token/time ceilings, duplicate events, scope and a synthetic stdio server lifecycle.
- [x] Implement finite owned jobs, explicit approval, stream normalization and reports.
- [x] Verify the installed server handshake/account/catalog without starting inference.

## Task 3: Native assistant and integration

Files: tools/sentinel_assistant_panel.py, tools/sentinel.py, godot_client/docs/SentinelAssistant.md,
godot_client/docs/Sentinel.md and tools/test_sentinel_assistant.py.
- [x] Add failing Tk tests for local search/preview/rules and existing-tab preservation.
- [x] Implement background refresh, previews, budgets/model controls, owned-job live
  oversight, approval requests, finite review, corrections, history and close cleanup.
- [x] Run new suite plus existing Sentinel monitor/chat/roadmap/clear suites.
- [ ] Review explicit staged diff, commit and push the task branch; verify remote SHA (final completion step).

## Execution ledger

- Initial inspection: existing Sentinel is Python/Tk under tools/, not a separate repo.
- Installed Codex: 0.163.0-alpha.10.2; public JSON schema generated outside repo.
- Base: 38ec1f8; three existing local commits ahead of origin/main, preserved.
- Unrelated catacombs files present before this task; never stage them.

- Tasks 1–3 implementation and regression cycles completed inline. No extra AI agents or inference used.
- Review caught and fixed source/test retrieval ranking, validation child cleanup, duplicate usage records,
  JSON credential redaction, the installed collaboration-event name, and transport-loss receipts.
- Ruling: preserve the running user-controlled Sentinel window after native input reported user activity;
  updated source is installed and loads when the owner closes/reopens Sentinel.
- Native capture timed out twice. Tk control/layout tests cover the minimum window; no visual capture pass claimed.
- Repository base already contains three separate published feature commits ahead of main. Push this task
  branch and report its isolated commit; avoid opening a mixed-scope PR into main for those unrelated parent commits.
- Final evidence: 56 unittest-discovery tests (33 new assistant + 23 existing roadmap/clear),
  22 installed-Godot monitor checks, and 49 ChatGPT integration checks passed: 127 total.
- Real controller handshake/account/catalog succeeded; seven models. No paid/live inference was started.
