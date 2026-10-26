# Part 5: Orders generation selection

> **For agentic workers:** Use superpowers:executing-plans inline and test-driven-development.

**Goal:** Improve the existing authored-template generator without enabling hunts.

**Architecture:** A small shared selection helper builds eligible cache/template
pools for both validation and the generator. Keep all generated instructions in the
existing persistent book, and leave the inventory, UI and world unchanged.

**Tech Stack:** Godot 4.5.1, GDScript, existing JSON configuration and smoke runner.

**Spec:** Supplied Dead Man's Orders Part 5 and Part 7 tier constraints. The user
explicitly reaffirmed that locations and NPCs stay deferred on 2026-10-26.

## Global constraints

- No live anchors, NPCs, clues, rates, rewards or encounter content are invented.
- Production remains disabled. Preserve existing Orders and all unrelated work.
- Work in the active PC project, then commit/push verified task paths only.
- No new dependencies, save format, networking architecture or gameplay mechanics.

## Design decisions

Disabled templates are excluded before reading their future target fields. Optional
`family_weights` selects a task kind before that kind's authored template weights;
omitted families retain neutral weight 1 and weight 0 excludes a family. No live
weight values are added. Unknown families or nonfinite/negative weights fail validation.

Different template IDs/texts for an identical objective binding are alternatives,
not extra objectives in one Order. Objective identity includes kind, anchor, target,
skill/level, item and normalized cipher answer. Selecting one removes its alternatives.
Validate distinct ordinary objectives after excluding each candidate final cache.

Roll gates once per Order. Prefer an otherwise eligible cache supporting the requested
gate when one exists. With no eligible gates, use ordinary objectives; with fewer
gates than the rolled maximum, use the available number. Never force gates just to
fill an Order. Prefer another kind when selecting the next task if available, and
arrange the chosen reveal order to minimize adjacent identical kinds with random ties.

Apply tier skill ranges and gate limits to every enabled template, including riddles
carrying skill requirements. Deckhand stays ungated. Reject inconsistent slots and
requirements before content enters selection.

World travel/access validation, backtracking budgets, equipment/contact/combat/cursed
content and their distributions remain deferred to their respective sections. This
is the Part 5 selection pass, not a claim that all world-dependent constraints exist.

## Review focus

- No eligible gated family after filtering: opening must succeed without item loss.
- Alternate text/IDs must not inflate distinct objectives or bypass gate limits.
- All-zero usable families or all ordinary targets at the cache: fail configuration.
- Disabled future templates must never become live, and malformed enabled flags fail.
- Weighted family choice must not become dominated by the number of text variants.

### Task 1: Regression tests

**Files:** new `orders_generation_smoke.gd`/scene, `tools/test_orders.py`, existing
generation simulation in `orders_rules_smoke.gd`.

- [x] Add tests for unavailable/undersupplied gates, disabled templates, family
  filtering/weighting, duplicate bindings, cache feasibility and tier validation.
- [x] Observe missing behavior failures before implementing.

### Task 2: Shared validation and selection

**Files:** new `scripts/orders/orders_selection.gd`, existing definitions/service.
**Interfaces:** helper exposes objective key, positive family weight, distinct count,
and per-tier cache pools. Service caches pools when configuring definitions.

- [x] Implement pool validation and weighted distinct selection.
- [x] Implement safe gate fallback and varied reveal order.
- [x] Run targeted regressions and existing 40,000-order generation suite; verify
  gate frequency/counts, valid revealed slots and no duplicate objective bindings.

### Task 3: Verify and complete

- [x] Run all Orders suites, review the scoped diff and request independent review.
- [x] Fix substantive findings with regressions; update the feature status report.
- [ ] Commit and push the verified task branch; report completed and deferred scope.

## Execution record

Implemented inline in the active project, branch `codex/orders-part5-generation`,
based on `19e66b1`. User scope confirmation keeps locations and NPCs deferred.

Initial generation regressions reported 14 missing-behavior failures. The neutral
family-frequency fixture initially assumed three Deckhand families although the
existing fixture had two; the test-only fixture now explicitly permits existing
cipher bindings to test three families. No production tier content was changed.

Malformed requirement and tier-count casts were identified during implementation
and independent review, guarded with numeric validation, and given regressions.
Targeted results: 28 generation checks and 43 lifecycle/rules checks, including
40,000 generated Orders. Independent review reports no remaining scoped findings.
Editor import and Login startup pass without script/native errors. Full regression
run: all ten Orders suites passed, with no script/native errors. The generation
suite reports 28 checks and the lifecycle/rules suite reports 43 checks plus 40,000
generated Orders. The completion commit/push is reported in the final response.
