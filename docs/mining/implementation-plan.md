# Mining Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. This request authorizes these documents only; gameplay implementation is a later task.

**Goal:** One configurable Mining implementation for levels 1–100, integrated with existing local/online play and character saves.

**Architecture:** `MiningDefinitions` validates activity metadata; `MiningService` owns attempts and shared deposits. A small controller and existing region/activity adapters supply player context and presentation. All ore types use the same code.

**Tech Stack:** Installed Godot 4.5.1/GDScript, JSON metadata, existing ENet/WorldHost and Django/PostgreSQL save service.

**Spec:** `docs/mining/design.md`; context: `docs/mining/discovery.md`.

## Global constraints

- Work in the active game repository; read its `AGENTS.md`. Preserve unrelated dirty files. Follow `docs/DevelopmentSync.md` for scoped commits/pushes on `codex/<task-name>`.
- No new item IDs, substitute tools, duplicate inventory/XP/item registries, unrelated refactors or changes to existing Fishing/Cooking interfaces.
- Production pickaxe definitions stay empty until real approved catalog items exist. Steel Ore 242 is excluded; Starforged Ore 256 remains Golem Titan-only.
- Values in the design are proposed tuning. Production ore rows, tool IDs and visual/placement bindings require content decisions before activation; infrastructure/tests can proceed first.
- Runtime deposits reset on host restart/region recreation; committed character inventory/XP persists. Cross-host/world-state persistence is outside V1.

## Review focus

- Duplicate/stale start after depletion or a newer movement intent must not grant ore or shorten attempts (tasks 3, 4).
- Two players completing on the same deposit must receive at most one combined reward per generation (tasks 3, 4).
- Uncertain save responses, frozen sessions and expired leases must not replay grants or accumulate instant attempts (tasks 1, 4, 7).
- A version-1 character must retain every old field; malformed fields must never become a fresh character (task 1).
- Late join, repeated snapshots, scene travel and missing art must not fabricate rewards, multiply animations or retain stale nodes (tasks 5, 6).

## Task 1 — Mining progression and compatible saves

**Modify:** `godot_client/scripts/skill_progression.gd`, `godot_client/scripts/player_state.gd`, `godot_client/network/character_codec.gd`, `backend/accounts/views.py`, `backend/accounts/tests.py`, `godot_client/scripts/dev_tools/character_persistence_smoke.gd`, `godot_client/scripts/dev_tools/skill_tools_smoke.gd`.

**Interfaces:** existing `PlayerState.get_skill_progress()` / `add_skill_experience()`; codec `encode()` emits version 2, `decode()` accepts 1/2 as specified. No new XP API.

- [ ] Extend persistence tests: v1 without Mining yields level 1/0 XP, all eight old XP totals/items/equipment unchanged; v2 round-trip preserves Mining; absent v2 Mining, malformed present v1 Mining and unknown version 999 reject. Add backend acceptance tests for 1/2 and keep malformed-state rejection.
- [ ] Run the tests and confirm failures expose the missing migration, then implement the registry/source text, defaults and narrow migration. Update backend's existing test that currently rejects version 2 to reject 999.
- [ ] Verify Mining clamps to 100/19,450,000 XP, does not change combat level, appears in journal/debug rows, and an old character can save and reconnect. Commit the passing migration as one coordinated change; deployment order is backend then matched host/client.

## Task 2 — Validated definitions, deposit contract and probability

**Create:** `godot_client/data/mining.json`, `godot_client/scripts/mining_definitions.gd`, `godot_client/scripts/dev_tools/mining_definitions_smoke.gd` and matching `godot_client/scenes/dev_tools/mining_definitions_smoke.tscn`.
Also create `godot_client/scripts/mining_deposit.gd` and `godot_client/scenes/gathering/mining_deposit.tscn` so later server discovery has its node contract.
**Modify:** `godot_client/scripts/acquisition_rules.gd`, `godot_client/tests/catalog_acquisition_smoke.gd`.

**Interfaces:** all `MiningDefinitions` and `MiningDeposit` methods plus `AcquisitionRules.can_mine(item)` from the design. Catalogs remain owned by `GameData`.

- [ ] Write failing assertions for unknown/duplicate IDs, invalid resource paths, noninteger/out-of-range levels, nonfinite probabilities/timers, interval bounds, and empty-tool unavailable results. Verify 242/256 reject and 235/329 are eligible candidates.
- [ ] Implement the loader/validator and pure formula. Test `p(1)=0.22`, `p(31)=0.68`, monotonic bounds, below-unlock rejection and requirement 100 without division by zero. Test independent ore requirements unrelated to tier.
- [ ] Implement the generic deposit wrapper and its visual-state application. Test stable IDs, approach point, hit area and missing/invalid visual references without production map placement.
- [ ] Test selection by ownership + Mining level, fastest interval then lowest ID, carried versus equipped eligibility. Pure tests may use isolated tool-resolution doubles; never write synthetic item records to `GameData` or production JSON. Keep actual `pickaxes: []` until the prerequisite is met.
- [ ] Run the definition and catalog acquisition suites; commit only after they pass. Adding a second definition must exercise the same formula/methods with no ore-name branches.

## Task 3 — Shared extraction and respawn engine

**Create:** `godot_client/scripts/mining_service.gd`, `godot_client/scripts/dev_tools/mining_service_smoke.gd` and matching `godot_client/scenes/dev_tools/mining_service_smoke.tscn`.

**Interfaces:** consume task 2 definitions; implement the service methods and trusted `context`/post-grant `reward` callbacks specified in the design. Use injected RNG/clock advancement; actual grants use existing `PlayerState` methods.

- [ ] Write deterministic tests using small simulation steps: interval 2.4 yields no roll at elapsed 2.39, one at 2.4; forced miss gives no item/XP and repeats; forced hit grants exactly one ID-235 item plus 35 XP, depletes for 12.0 seconds, then increments generation on respawn. Use isolated tool-resolution doubles while real pickaxes are absent.
- [ ] Implement deposits/sessions/deadlines and synchronous claim→item→XP→close→callback ordering. Sort due attempts by deadline, shuffle ties with server RNG, and process active sessions/depleted deposits only.
- [ ] Add assertions: two miners/one hit gives one combined item and XP award; repeated start leaves deadline intact; stale generation rejects; click spam, zero/NaN delta and long stalls cannot accelerate. Stack at `MAX_COUNT` does not consume the deposit; XP at cap remains capped.
- [ ] Test interruption by movement, damage (including same-step healing), death, tool loss, combat/casting, another activity and disconnect. Freeze prevents rolls despite temporary actor removal; resume requires a full interval. Duplicate IDs/missing context fail closed. Run suite and commit.

## Task 4 — Online authority and persistence adapter

**Modify:** `godot_client/network/authoritative_region.gd`, `godot_client/network/region_activities.gd`, `godot_client/network/world_host.gd`, `godot_client/scripts/dev_tools/world_host_persistence_smoke.gd`, `godot_client/scripts/dev_tools/region_freeze_smoke.gd`.
**Create:** `godot_client/scripts/dev_tools/mining_authority_smoke.gd` and matching `godot_client/scenes/dev_tools/mining_authority_smoke.tscn`.

**Interfaces:** `mine_start {deposit_id, deposit_generation}`, `mine_stop {}`; one service per region; `active/close/submit/snapshot` bridge to it. Add integer validation, trusted geometry lookup, and the deposit/actor/private snapshot fields from the design.

- [ ] Write rejection tests for client-supplied rewards/timing/tool stats, fractional generation, unknown/wrong-region deposit, insufficient ore/tool level and out-of-range/blocked approach. Confirm missing real tool still rejects in production context.
- [ ] Implement discovery, once-per-region-step advance, dirty notification, mutual activity exclusion and public/private snapshots. Accepted starts call the existing activity `_stop_movement()` helper. Add start to host movement ordering; a newer move defeats a queued old start. Disconnect cancels immediately despite the existing 30-second actor grace period.
- [ ] Exercise two player sessions, equal-time claims, generation replay, late joins and freezes. Host tests simulate a committed save with lost acknowledgment: retry the same operation, preserve one reward, do not roll while frozen, cancel on expired lease. Retain existing ground-item transaction behavior.
- [ ] Run authority/freeze/persistence tests and original online minigame regressions; commit when passing. No per-attempt RPC and no client-granted item/XP.

## Task 5 — Interaction and local adapter

**Create:** `godot_client/scripts/mining_controller.gd`, `godot_client/scripts/dev_tools/mining_interaction_smoke.gd` and matching `godot_client/scenes/dev_tools/mining_interaction_smoke.tscn`.
**Modify:** `godot_client/scripts/world_interaction.gd`, `godot_client/scripts/main.gd`, `godot_client/scripts/cooking_controller.gd`, `godot_client/scripts/skill_training_session.gd`, `godot_client/network/online_world_view.gd`.

**Interfaces:** use task 2 node and design controller methods; add `SkillTrainingSession.record_committed_total(skill: String, total: int) -> void` and pending Mining to existing walk cancellation/approach processing. Reuse `Network.send_action()` as-is unless its validation needs a narrowly tested extension.

- [ ] Test left-click and Mine context action, reachable approach, blocked route, cancellation on new intent/travel, stale/freed node, and modal input exclusion. Use an isolated test scene; do not place deposits in production maps yet.
- [ ] Connect the generic deposit wrapper, cached ID→node lookup and controller. Offline advances the same service once; online sends intent only and starts after authoritative state. World actions stop Mining before opening Fishing/Cooking; do not duplicate their UI.
- [ ] Test full snapshot recovery for available/depleted deposits and duplicate/old snapshot rejection. Local/server map coordinate conversion must agree. Local reward callbacks record session XP; online records committed XP deltas after baseline. Test a late grant across travel counts once, duplicates count zero and login historical XP counts zero.
- [ ] Run interaction + Fishing/Cooking input regressions; confirm local/online parity with the same scripted RNG/context fixtures, then commit.

## Task 6 — Gathering animation presentation

**Modify:** `godot_client/scripts/actor_sprite.gd`, `godot_client/scripts/character_sprite_library.gd`, `godot_client/scripts/character_attachment_rig.gd`, `godot_client/network/online_world_view.gd`, `godot_client/scripts/mining_controller.gd`.
**Create:** `godot_client/scripts/dev_tools/mining_presentation_smoke.gd` and matching `godot_client/scenes/dev_tools/mining_presentation_smoke.tscn`.

**Interfaces:** `ActorSprite.set_gathering(action, direction, interval_seconds, tool_item_id)` / `clear_gathering()` with design types. Public actor gathering fields synchronize nearby miners; service deadlines alone control rewards.

- [ ] Test directional facing, cadence, repeated snapshot stability and cancellation. Missing `mine` art must show idle/facing without triggering attack, attack sounds, combat events or reward callbacks.
- [ ] Implement optional animation and temporary attachment support while preserving saved equipment and existing movement/combat animation priority. Use existing socket libraries; actual asset references are supplied during content binding.
- [ ] Run presentation and existing sprite/attachment regressions, then commit. Add approved resources to `godot_client/data/character_sprites.json`, `godot_client/data/character_attachments.json` and `godot_client/data/equipment_visuals.json` only if supplied; no generated art in this implementation task.

## Task 7 — Content activation and end-to-end checks

**Modify after content prerequisites:** `godot_client/data/mining.json`; approved map scene path selected from actual authored placement (none is authorized by this plan). **Create:** `godot_client/docs/Mining.md`. **Extend:** `godot_client/scripts/dev_tools/online_concurrency_smoke.gd`, `godot_client/scripts/dev_tools/character_persistence_smoke.gd`, `tools/test_online_concurrency.py` only as needed for Mining coverage.

- [ ] Bind real existing pickaxe IDs, finalized ore rows and approved available/depleted visuals. Validate every resource/ID and ensure 242/256 remain excluded. If the catalog is still missing pickaxes, report that content blocker; do not mark Mining playable.
- [ ] With real tools, run two actual clients against one deposit: one winner, shared depletion/respawn, no duplicate grants, committed item/XP survive logout/login, and a reconnect cannot resume an old attempt. Verify restart deliberately resets deposits but preserves committed characters.
- [ ] Prove data-only extension by adding/removing a second approved ore definition in a test fixture with no mining-code changes. Measure attempt throughput/XP rate with seeded trials and document proposed tuning versus observed results.
- [ ] Run relevant suites below, editor parse/import and main-scene startup. Inspect logs for errors, review exact staged files and retain `.uid`/source `.import` files. Commit/push only completed work, verify remote hash; preserve unrelated edits and keep generated evidence outside Git.

## Verification commands for later implementation

Use the installed Godot executable in `$env:GODOT`; the new test scenes above follow the existing Node smoke-test pattern, print checks/failures and exit nonzero on failure. Run each relevant command once after its owning task; expect zero failures and no script/parser errors.

```powershell
# Replace <suite> with definitions, service, authority, interaction or presentation.
& $env:GODOT --headless --path godot_client res://scenes/dev_tools/mining_<suite>_smoke.tscn
& $env:GODOT --headless --path godot_client res://scenes/dev_tools/character_persistence_smoke.tscn
& $env:GODOT --headless --path godot_client res://scenes/dev_tools/skill_tools_smoke.tscn
& $env:GODOT --headless --path godot_client res://scenes/dev_tools/catalog_acquisition_smoke.tscn
& $env:GODOT --headless --path godot_client res://scenes/dev_tools/region_freeze_smoke.tscn
& $env:GODOT --headless --path godot_client res://scenes/dev_tools/world_host_persistence_smoke.tscn
& $env:GODOT --headless --path godot_client res://scenes/dev_tools/original_online_minigames_smoke.tscn
& $env:GODOT --headless --path godot_client res://scenes/dev_tools/fishing_input_smoke.tscn
& $env:GODOT --headless --path godot_client res://scenes/dev_tools/cooking_ui_smoke.tscn
python tools/test_inventory_items.py --godot $env:GODOT
python tools/test_cooking.py --godot $env:GODOT
& $env:GODOT --headless --path godot_client --script res://scripts/dev_tools/sprite_integration_smoke.gd
& $env:GODOT --headless --path godot_client --script res://scripts/dev_tools/attachment_smoke.gd
./tools/test_accounts.ps1 -Integration
& "$env:LOCALAPPDATA/Aetheria/online/venv/Scripts/python.exe" tools/test_online_concurrency.py --godot $env:GODOT
& $env:GODOT --headless --editor --path godot_client --quit
& $env:GODOT --headless --path godot_client --quit-after 120
```

Live concurrency requires running services; use isolated test accounts and never expire real-user leases. Read existing test scripts before execution and route logs/screenshots outside Git. This document records planned validation, not tests run during design.
