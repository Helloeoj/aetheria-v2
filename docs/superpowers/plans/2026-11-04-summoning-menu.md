# Summoning menu

Goal: Add a Summoning page alongside Spells in the existing in-game Journal.

Design: Reuse the Journal shell, card selection, scrolling and fantasy theme.
Show all seven existing summon concepts, their established attack descriptions,
and a native-pixel animated idle portrait. Preserve existing page IDs and key
bindings. Show Summon as unavailable because the previous scope was artwork
review; no summon authority, costs, unlocks or combat values exist yet.

Approaches: A separate window duplicates modal/input handling. A preview-page
addition does not meet the user's chosen in-game location. Use the Journal.
Implementation details are agent decisions under the standing execution rule;
the user selected an in-game menu alongside the spellbook.

Files: ui_inventory_menu.gd integrates the page; ui_summoning_page.gd owns its
content; ui_summon_portrait.gd draws anchored native frames; data/summons.json
contains menu descriptions and review-portrait references. Copy only the seven
south-east idle clips to Assets/Characters/SummonPortraits, with provenance.

- [x] Add a focused test proving the page is absent, then implement selection,
  seven portraits, unavailable action and no changes to player resources.
- [x] Keep existing page numeric IDs, verify native tab routing, page switching,
  selection persistence and small-window containment. Update the existing ledger
  tab-count expectation without changing ledger behavior.
- [x] Run the focused test, ledger test, editor parse and main startup. Open the
  actual world scene with the menu and inspect a real Godot screenshot.
- [ ] Review/stage only this task, commit and push codex/summoning-menu.

Constraints: No gameplay installation, new art generation, balance invention,
save changes, unrelated edits, isolated worktrees or subagents.

Validation: 87 focused menu checks and 43 existing ledger checks pass. Godot
editor import and main startup contain no script errors. Real world renders at
1280 and 1024 show the Journal above the HUD; added a dedicated layer 81 after
observing the chat layer 80 and food control covering the new page. Native tab
clicks, animated frame advancement and all 44 unchanged portrait imports pass.
