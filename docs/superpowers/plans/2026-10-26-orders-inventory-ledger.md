# Physical Orders and Captain's Ledger Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans for inline execution.

**Goal:** Read physical, nonstacking Orders from inventory and use the Ledger as
a durable collection log with current-task and per-tier inventory summaries.

**Architecture:** Reuse the existing backpack, Orders instance IDs, authoritative
service, save codec and native UI. Add tier-specific opened catalog items and a
reader; persist collection/completion totals in the private Orders book.

**Tech Stack:** Godot 4.5.1/GDScript, JSON catalog, existing Django save storage.

**Spec:** `docs/superpowers/specs/2026-10-26-orders-inventory-ledger-design.md`

## Global Constraints

- Implement directly in the active project; preserve unrelated local changes.
- Production Orders stay disabled; no invented world/reward content or rates.
- Preserve existing inventory, journal pages, game mechanics, login and saves.
- Commit/push verified task changes to Helloeoj/aetheria-v2 on this task branch.

## Review Focus

- Old active v3 saves receive one physical item without rerolling; repeated loads
  and current-schema missing/duplicate items do not grant replacements.
- Public client projections with opened items load without private task details.
- Delayed activation acknowledgements open the reader for the matching tier only.
- Failed/duplicate cache claims leave collection counts and inventory unchanged.
- Opened items cannot escape through offline/online generic drop paths.

### Task 1: Physical lifecycle, persistence and collection accounting

**Files:** catalog/items, inventory_system, Orders book/service/definitions,
player_state, character_codec, authoritative_region, main, backend save validator;
Orders rules/persistence/authority tests.

**Interfaces:** Tier-to-opened-item names/IDs derive from the Orders book;
`inventory_valid(player)` validates active book/item consistency. Book v2 adds
bounded collection item counts and four tier completion counts. Save v4 migrates
v1–v3 without resetting malformed existing data. Claims log only catalog items
explicitly marked `orders_exclusive`.

- [x] Write lifecycle, nonstacking, migration, ownership and collection regressions.
- [x] Run targeted suites and observe expected missing-behavior failures.
- [x] Implement atomic sealed-to-opened transformation, ownership checks,
  terminal item removal, bounded logs, schema migration and safe drop rejection.
- [x] Run Orders rules, codec and authority suites; expected positive checks,
  zero failures and no script/native errors.

### Task 2: Inventory reader and Ledger collection view

**Files:** Orders reader/ledger, controller, ui_inventory_menu and UI smoke tests.

**Interfaces:** Reader consumes the same acknowledged public `controller.view()`
as the Ledger. Inventory click/Read addresses a tier and its current order ID;
activation waits for the acknowledged opened item. Ledger displays counts from
the actual backpack plus durable collection/completion fields.

- [x] Add failing real UI regressions for inventory click, reread, hidden content,
  collection summaries and tier counts, including delayed activation.
- [x] Implement a scrollable native reader and keep original journal controls.
- [x] Run UI smoke tests; expected positive checks and zero failures/errors.

### Task 3: Verify, document, review and synchronize

- [x] Run all Orders, existing networking, inventory and isolated backend suites.
- [x] Validate editor import/startup and inspect the rendered reader/ledger.
- [x] Obtain an independent code review and fix any substantive findings.
- [x] Update the completion report with actual completed/deferred content and tests.
- [ ] Review/stage only task changes, commit, verify origin and push this branch.

## Execution record

Implemented inline in the active project on `codex/orders-inventory-ledger`.
The native backpack plus one active instance per tier supplies physical identity;
no separate general inventory was introduced. Production content remains disabled.

Initial physical-item tests failed on stacking and the absent opened catalog items;
the first reader tests failed on inventory activation. Review regressions then
reproduced actual-game Escape, resize, failed activation and stale duplicate reply
problems, all corrected. Existing reliable result envelopes gained `sequence` and
`ok` so Orders activation errors can be correlated without using status text as a
protocol. Confirmed saved ownership outranks a stale duplicate rejection.

All nine Orders suites pass, including 40,000 generated Orders, 34 physical-item
checks and a final 35-check reader run. All 13 existing networking suites and 130
inventory checks pass. Isolated backend tests: 28 OK, three PostgreSQL-only skips.
Editor import, Login startup and the real rendered reader/collection capture pass.
Independent read-only review reports no remaining substantive findings.

Another chat's Tavern fix was committed in the shared checkout during this task;
that existing commit and all unrelated working-tree changes are preserved. Only the
Orders task paths are included in its completion commit. Final reply reports the
actual commit and verified push; no live service deployment or database rewrite is
claimed.
