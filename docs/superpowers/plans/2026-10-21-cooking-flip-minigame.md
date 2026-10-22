# Cooking Flip Minigame Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline with test-first steps.

**Goal:** Replace automatic RNG cooking with one manual flip per fish in the existing stove interface.
**Architecture:** CookingSession owns timing, validation and atomic item/XP exchange. CookingController owns synchronized world state and result recording. CookingPanel and a reusable pan view display session state and forward player input.
**Tech Stack:** Godot 4.5.1, GDScript, existing Python smoke runners.
**Spec:** User-provided “AETHERIA V2 — IMPLEMENT THE COOKING MINIGAME” request, 2026-10-21.

## Global Constraints

- MIN_FLIP_WINDOW = 0.8 seconds; MAX_FINITE_FLIP_WINDOW = 2.5 seconds.
- Read required/mastery levels from existing recipe data; no new mastery thresholds.
- Unlimited prompts at mastery still require a manual flip. Successful flips have no RNG.
- Preserve recipes, cooking intervals, XP, item IDs, inventory behavior, stations and unrelated work.
- Commit and push only validated Cooking changes to origin codex/cooking-flip-minigame; never force push.

## Review Focus

- Rapid input must not resolve twice or skip a batch fish.
- Cancellation/reopening during a prompt must not reset risk without consuming food.
- World interruption must be validated on input as well as on timer advancement.
- Long frames must not spend a new prompt's reaction window before it is shown.
- Scene teardown must release locks and never grant delayed animation rewards.

## Task 1: Session timing and transactions

**Files:** scripts under godot_client: cooking_session.gd, dev_tools/cooking_smoke.gd, dev_tools/food_input_smoke.gd.
**Interfaces:** reaction_window(level, recipe) -> float; is_active() -> bool; flip() -> Array[Dictionary]; advance(delta) -> Array[Dictionary]. COOKING -> FLIP_PENDING -> FEEDBACK -> next fish/FINISHED. Existing close() cancels the batch.

- [x] Extend the real smoke suite for windows at all recipe levels, short ranges, manual mastery, deterministic success/failure, timing boundaries, batches, repeated input, cancellation, abandonment, interruptions and XP caps. Replace automatic cooking in the food fixture with manual flips.
- [x] Run the new tests and confirm the missing minigame fails.
- [x] Implement recipe-driven windows and one guarded transaction per resolved attempt. Reserve the raw fish when the prompt appears; closing a live prompt burns that reserved fish. Partial heat-up cancellation preserves raw food. Feedback takes 0.65 seconds and never gates rewards behind a tween callback.
- [x] Run cooking_smoke and adjacent food tests; expect zero failures.

## Task 2: Actual stove interface and validation

**Files:** cooking_controller.gd, ui_cooking.gd, main.gd (Cooking input branch only), new ui_cooking_pan.gd; dev_tools/cooking_ui_smoke.gd and scene; dev_tools/tavern_integration.gd; tools/test_cooking.py; godot_client/docs/Cooking.md.
**Interfaces:** controller.flip() synchronizes world conditions, calls session.flip(), records XP once, and refreshes. panel.handle_key(event) handles Space/Enter without repeats; button calls the same controller path. Pan view consumes session state only.

- [x] Add real tavern UI tests for click/key input, disabled early/repeated input, finite timer and burn, untimed mastery, batch flips, training XP, close/reopen, damage, travel and teardown. Run before interface changes; expect missing flip UI to fail.
- [x] Integrate the shared pan and food icon with short heat, flip, success and smoke animation; show numeric countdown, prominent FLIP button and safe mastery text. Preserve existing theme and recipe selection.
- [x] Update old tavern/food fixtures to explicitly flip every fish; document the new rules and local authority boundary.
- [x] Run complete cooking and inventory suites, crafting regressions, tavern integration, editor parse/import and main startup. Inspect outputs for errors, and render/inspect real UI screenshots outside the repository.
- [x] Review diff, obtain independent code review, fix significant findings with regressions, stage explicit files including UIDs, commit, push and verify remote SHA. Open a PR into main.

## Execution Notes

User explicitly requested implementation without another design approval; proceed inline. Existing checkout contains unrelated untracked Smithing files; preserve them. Baseline cooking suite: 9 adjacent suites pass; cooking_smoke fails only its stale exact-eight-skills assertion. Replace that assertion with Cooking registration coverage. Work in the active checkout on the task branch to preserve the user's current playable project location.


## Verification Ledger

- Task 1: RED: missing recipe-driven flip-window API. GREEN: cooking_smoke 1,631 checks and food_input_smoke 30 checks, zero failures.
- Task 2: RED: real Cooking panel missing FLIP control. GREEN: actual button/Space/Enter, timing, burn, mastery, training XP, close/reopen, live timer, damage, teardown and tavern travel tests pass.
- Final review: independent reviewer found physics catch-up could spend 0.116667s of an unseen prompt. Regression failed against physics timing, then passed after switching the controller clock to process/render frames. No other findings.
- Final validation: all 12 scenes in tools/test_cooking.py pass, 2,942 checks. Inventory: 121 checks. Crafting acquisition/service/UI: 1,062 / 1,199 / 17 checks. Total: 5,341 checks, zero failures. Rendered UI run: 28 checks, zero failures, four screenshots inspected. Godot editor import/parse and main startup passed with no script errors.
- Task scope: preserve unrelated untracked Smithing work; its owner migrated it to a separate worktree during execution. No Smithing implementation is included here.
