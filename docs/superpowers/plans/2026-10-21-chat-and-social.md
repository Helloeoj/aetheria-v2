# Chat and social implementation plan

Execution: native, continuous; the user explicitly instructed implementation without further approval stops and requires the active PC project to be updated along with GitHub.

Goal: working Local/Global/Private chat, persistent friends/blocks and a permanent transparent Godot panel.

1. Write/run failing Python behavior tests for durable profiles/lists, 20-tile area/instance routing, private isolation, blocking, malformed input and reconnects. Implement a focused SQLite social domain and an asyncio WebSocket server; run the tests green.
2. Write/run failing Godot integration coverage for a persistent panel, native keyboard focus, shortcut suppression and viewport fit. Implement the autoload client and separate panel; integrate narrow input/layout hooks into the active game's `main.gd` and `project.godot`. Run import, UI and real-server client tests.
3. Start the local server, verify the active game, review source/staged diffs, commit only this task's files, push the task branch to the verified v2 origin and create a PR. Preserve every unrelated local edit.

Ruling: implementation happens in the active project, on `codex/chat-and-social-live`, preserving its existing uncommitted files. The previous documentation-only worktree did not satisfy the user's requested installation.

Ruling: the shared Django/account/world backend is still a design. Deliver a standalone runnable Python/WebSocket service with durable SQLite social profiles and a replaceable identity boundary instead of blocking this feature on that separate project. Profiles use server-assigned IDs and random bearer credentials, with only credential digests stored server-side; no password subsystem or gameplay-save authority is introduced. The native development client stores its generated profile credential in `user://`, scoped to the endpoint. Plaintext transport is loopback-only; remote endpoints require TLS. Positions remain explicitly client-reported until the authoritative world backend exists. These are implementation adjustments to the proposed spec, not claims that shared accounts or authoritative world movement are implemented.

Review focus: stale area context during travel; P/K activity shortcuts while typing; queued private messages racing blocks; profile/endpoint changes leaking history; unavailable server leaving normal gameplay functional. Cover these through actual domain/socket and Godot input/UI tests.

Validation evidence belongs outside Git. Database, credentials, caches and diagnostic output are never staged. Installed Godot 4.5.1 and the existing bundled Python are used without engine upgrades.

Implementation record: completed server/domain and persistent active-game UI. Python behavior suite: 11 passing tests. Three separate Godot clients: 13 passing network checks. Persistent UI/native input: 19 passing checks. Inventory: 121 passing checks. All 12 cooking/fishing/food/skill regression scenes: 2,842 passing checks. Editor import/parse and original main-scene startup pass. A focused independent review found a duplicate-profile rename side effect and non-text-focus pointer exception; both have regression coverage and were corrected. Runtime checks first caught existing modal buttons underneath chat; pointer routing now preserves those controls while leaving chat visible. No unrelated maps/assets/crafting edits are staged.
