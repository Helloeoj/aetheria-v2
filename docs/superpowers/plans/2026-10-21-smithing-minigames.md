# Smithing minigames implementation plan

> Implement inline with superpowers:executing-plans and test-driven-development.

**Goal:** Integrate the user's established smelting, forging and quenching design into the current stations.

**Architecture:** A reusable SmithingSession owns validation, heat/hammer state and atomic inventory settlement. SmithingRules loads configurable balance and category patterns. The existing CraftingPanel hosts a themed Smithing minigame and reusable workpiece/quench view.

**Tech stack:** Godot 4.5.1 GDScript, existing JSON catalogs and PlayerState skill curve.

**Spec:** User's implementation request and subsequent answers in this chat. One ore yields one ingot. Tier unlocks: 1/10/20/30/40/50/60. Starting heat widths: .30/.30/.25/.22/.20/.18/.16. XP per bar targets approximately 60 active gameplay hours to max Smithing. Other recipe quantities remain unchanged/pending.

## Constraints and review focus

- No cooling/reheating in forging, material loss for bad strikes, new tiers or unrelated skill changes.
- Furnace batches 1–10; width and overheat grace grow with relative proficiency; no burning at +30.
- Reserve inputs once, settle once, refund unfinished work once; inventory overflow must retain a claim instead of losing it.
- Test interrupted station use, cancellation while overheated, close/reopen during quench, duplicate finish calls, alias stacks, missing definitions and concurrent sessions.
- Timing/max heat width/target patterns remain configurable. Document the XP pacing reference and its limitations.

## Tasks

1. [x] Write and run failing Smithing smoke coverage, then implement rules, session, skill registration and transaction reuse. Test actual catalog recipes and backpack/XP effects.
2. [x] Write failing station/UI coverage, then integrate furnace/hammer controls, shaping stages, reusable quench animation and hiss. Update previous immediate-anvil tests to require the minigame.
3. [x] Calibrate and test XP reference progression, document configuration, run adjacent suites, editor import, rendered animation checks and main startup.
4. [x] Obtain independent code review and address findings with failing/passing regression tests.

Publication follows the authorized repository workflow: stage explicit paths, review the index, commit, push origin codex/smithing-minigames, create a PR into main and verify the remote hash. The final chat report carries the resulting commit/PR links.

## Execution record

- Baseline: clean main equals origin/main, correct v2 origin; crafting service 1199 checks passed.
- Started in the current checkout; a concurrent Cooking chat switched its branch. With user-authorized coordination, moved only Smithing work to a separate worktree on codex/smithing-minigames. Preserved the Cooking work and removed byte-verified Smithing edits from its checkout.
- User explicitly supplied the design and requested implementation; no redesign/approval cycle is needed.
- Rules/session: initial missing-feature test failed, then 155 core checks passed. Added overflow/hit-radius coverage, then 164 checks passed. The independent progression simulation reaches the existing XP cap in 60.02 reference hours.
- UI: initial test failed because the station panel had no Smithing view. Real GUI hammering, quench phases, actual sprites and hiss subsequently passed in headless and rendered runs. Set an explicit 1280x720 test viewport to avoid headless's 64px default.
- Independent review identified pending settlements lost on travel and a recoverably hot close retaining inputs. New lifecycle tests failed for both. Added persistent PlayerState settlement ownership with a weak reverse reference, and a latched cooldown/cancel request; core and actual scene recreation regressions passed.
- Review set aside unrelated Cooking work, subjective difficulty and visual polish. Scope remains Smithing; authored stage/quench captures were inspected, timing/patterns remain configurable, and import-only line-ending churn was removed without changing source settings.
- No deferred code-review findings remain. Higher equipment costs remain pending by the user's preserve-recipes requirement; the 60-hour figure is a reproducible balance reference, not a completed human playtest.
