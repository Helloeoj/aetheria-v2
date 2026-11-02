# Restore Smithing minigames in the active game

**Goal:** Furnace/anvil recipe buttons open the approved heat/hammering games,
followed by the original barrel dip, steam, hiss and finished-item reveal.
**Spec:** User's AETHERIA V2 Smithing design and approved unlocks/widths/60h XP
target in this chat; retain current recipe data including Iron Ore + Coal Steel.
**Architecture:** Reuse the original Smithing rule/session/UI/workpiece scripts
from commit 50dc598, adapting integration to the active authoritative game.
Extend the existing CraftingPanel rather than replace it. Keep login, saves,
other skills, current equipment, interfaces, controls, art and unrelated work.
**Tech:** Existing Godot 4.5.1, GDScript, JSON and test runners.

- [ ] Reproduce absent minigame with existing Smithing regression in active game.
- [ ] Restore session/rules/workpiece/view and register Smithing on existing XP
  curve; split exchange validation from immediate craft and reject bypasses.
- [ ] Embed minigame in furnace/anvil panels; 1-10 bars, one forged workpiece,
  configured patterns/stages, exactly-once item/XP after quenching.
- [ ] Server owns clock/material reservations/hits/rewards. Commands carry
  encounter/action/target identities, finite coordinates and expiring bellows.
  Existing activity busy checks/freeze/scene departure apply.
- [ ] Migrate absent Smithing XP from older saves. Persist reserved-material
  settlement separately from backpack; real reload settles it once, live
  projections do not refund or grant early. Quench completion cannot be replayed.
- [ ] Validate all batches/tiers, +29/+30 immunity, missing alloy ingredient,
  wrong/missed/replayed hammer inputs, animation phases/audio/finished textures,
  interruptions, close/reopen, saves, overflow and authoritative commands.
- [ ] Update affected instant-craft regressions to follow the new workflow;
  run relevant crafting/networking/inventory/cooking tests, editor import,
  login startup and real rendered UI checks. Independent review, scoped commit
  and push to origin/codex/restore-smithing-minigames; preserve unrelated changes.

No new world props or placement changes are needed: the barrel/anvil are the
existing approved minigame presentation, not replacements for world artwork.
Timings/max heat width remain configurable. Sixty hours is a progression model,
not a claim of sixty hours of human playtesting.

## Implementation and validation

Installed the original session/rules/workpiece/UI in the active project with
authoritative online sessions and schema-5 settlement recovery. Current item
definitions and recipe JSON are unchanged. The newer Starforged drop-only rule
is retained; six manufacturable tiers determine the 60.09-hour XP reference.

Verified 185 Smithing rule checks, 23 real station/animation UI checks (headless
and rendered), 60 authoritative/remote/persistence checks, 246 Bronze recipe
checks, 714 catalog/menu checks, 1118 crafting checks, 19 crafting UI checks and
1080 acquisition checks. All 13 networking suites, 12 cooking/fishing suites,
29 PostgreSQL account tests and 130 inventory checks passed. The focused
Starforged acquisition regression passed 881 checks; adjacent equipment/Mining
suites also passed. Editor import/parse and main login startup passed.

Review identified blocked claims after travel and dropped/delayed lifecycle
requests during server persistence pauses. Added reproductions, fixed claim
retry and same-token start/cancel retries, and verified the actual host freeze
gates and delayed rejection correlation. Final focused review found no blockers.

Evidence and rendered phase captures are outside the repository. No live remote
account-server session or human 60-hour playtest is claimed. Online client/world/
account service must all load the updated code; existing processes need restart.
