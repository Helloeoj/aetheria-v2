# Mineable placed ore nodes

Goal: left click mines; right click offers Mine. Use the shared MiningService
for real ore/XP, depletion, respawn, level/tool/range checks and authority.
Execution is in the active project, without subagents or extra approval gates.

Decisions: activate the 15 Bracken and 29 Valtherian placements, retaining every
root transform, both colliders, native 128px art, 0.75 density and world anchor
(48,72). Add a nonphysical MiningDeposit child using each saved exact approach.
Bind existing aligned full/depleted textures. Reuse saved mining tuning for
Iron/Coal/Mithril/Adamantite and the Blacksteel-stage Blackstone resource;
Copper and Tin share the existing level-1 tuning. These are initial settings,
not a new 65-hour balancing pass.

Add Copper Ore, Tin Ore, Blackstone and one Bronze Pickaxe to the item catalog
at free IDs 330Ã¢â‚¬â€œ333. Bronze Pickaxe uses the saved level-1, 3-second tool profile
and is forgeable from two Bronze Ingots at the existing anvil. Keep existing
resource IDs/save names; remove the obsolete Bronze Ore entry from Mining.
Add Copper + Tin bronze smelting while retaining the old recipe ID for saves. No new
map nodes, tool tiers, shops, free inventory grants or mining animation work.

- [x] Add an actual-scene activation/click/reward/state regression and observe
      failure on the missing catalog/wiring.
- [x] Add data and state presentation; bind existing placements. Preserve
      authored approaches when rebuilding the Valtherian scene.
- [x] Update existing Mining tests from obsolete Bronze Ore to Copper; run
      focused extraction/authority/persistence checks and real click tests.
- [x] Run actual-scene worldbuilding contracts; inspect real Godot 4x Mine
      menu, full/depleted states and player. Review scoped diff; commit/push.

The user removed the attempt-count stop rule on 2026-11-03. Preserve unrelated
local changes and generated evidence outside Git. Art approval remains separate
from technical activation. The pickaxe fallback combat-style array is fixed. Final activation has 244
passing assertions, the four core suites have 129, the two actual-scene
worldbuilding gates have 1,142, and constructor preflight has 3. Real 4x menu,
depletion and respawn were inspected. The narrow validator exception pins the
reviewed MiningDeposit source; arbitrary scripts remain rejected. Dedicated
mining animations and live-server deployment are outside this activation.
