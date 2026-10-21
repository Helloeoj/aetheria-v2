# Aetheria gameplay direction

Source review: October 19, 2026. This is a design assessment of the active Godot project, not a runtime playtest. Everything proposed below is a candidate, not an approved change to the game.

## Recommended focus

**A persistent, combat-led adventure RPG where players prepare in town, venture into the wilderness, bring back useful rewards, and earn access to harder adventures.**

The strongest next milestone is a complete 15–25 minute adventure using the existing tavern, road, and woodland. This duration is a proposed playtest target. Do not force a full equipment tier into that time or change approved XP rates merely to meet it.

Your foundations are already substantial: movement, collision, targeting, tick combat, several attack styles, spells, enemy pursuit and leashing, ground loot, inventory, equipment requirements, and six combat skills. The biggest opportunity is connecting these into repeatable player decisions.

A loop is a repeated sequence with a reason to start again. A mechanic is a rule or action that makes that sequence work. A shop is a mechanic; earning loot, selling surplus, buying supplies, and attempting a harder route is a loop.

## Missing or incomplete loops

| Priority | Loop | Repeated sequence | Player decision | Smallest useful version |
|---|---|---|---|---|
| First | Expedition | Choose goal → prepare → travel → fight/loot → return → improve → choose next goal | Stay for another reward or return with what I have? | One tavern hub, one enemy pocket, one destination, one objective, one useful reward |
| First | Economy and resupply | Loot → keep/sell → buy supplies/service → fund next trip | Keep this drop, sell it, or spend gold on readiness? | One buyer/supply NPC; food and rest as modest recurring purchases |
| Next | Supply production | Gather → process → make consumable → use → replenish | Buy supplies or make them? | One resource, one preparation station, one recipe, one useful food. Production can exist before a new gathering skill. |
| Next | Discovery and access | See landmark → investigate → meet condition → unlock reward/shortcut → explore farther | Which visible destination should I pursue? | One side path or cache and one earned shortcut; no sprawling quest framework |
| Next | Combat mastery | Observe threat → choose style/position → counter → beat stronger encounter → improve efficiency | Which loadout or position solves this encounter? | One readable ranged enemy and one melee threat using existing cover, styles, and pursuit |
| Later | Collection and long goals | Find source → target missing reward → assemble collection → unlock new challenge → pursue next set | Which creature or route offers what I need? | Named reward sources and a simple collection record; use existing different-monster set sourcing |

Optional later social loop: complementary player production → direct trade → prepare together → shared challenge. Direct trading and NPC commerce are stated economy intentions, but I did not find a connected implementation in the active main scene. Networking has placeholder/demo code. Build the first adventure so it is worth repeating alone; define authoritative ownership, rewards, and persistence before implementing shared play.

## Missing core mechanics

### Complete the first adventure

1. **Normal world population:** authored spawn locations, initial population, respawn timing, and safe placement. Reuse existing chase/leash behavior rather than rebuilding AI.
2. **A clear objective and guaranteed payoff:** visible goal, progress, completion, reward once, and a next lead. A small objective tracker is sufficient. Basic progress should not depend entirely on rare loot.
3. **Preparation and recovery:** a starter loadout; food consumption with a stated heal amount and action timing; an explicit mana recovery rule; rest at a safe location. Mana capacity already exists; mana recovery is the missing part.
4. **Death and restart:** readable defeat state, safe respawn, restored ability to act, and an explicit loss rule. Proposed first version: keep equipment and XP, with a modest recoverable cost. Avoid an early punishment spiral.
5. **Keep/sell/spend:** a simple NPC transaction, clear prices, a useful gold sink, and transaction feedback. Gold already accumulates from kills; it needs purchasing power.
6. **Persistent progress:** save/load for skills, equipment, inventory, gold, objective flags, and valid position. Reopening should preserve achievement. This is a foundation rather than a gameplay loop.
7. **Readable feedback:** objective and reward notices, clear failure reasons, recovery availability, and visible threat cues. Some feedback already exists in health bars, hit effects, targeting and the journal; a number of progression/spell events currently print to the console.

### Add depth after that works

- **Encounter decisions:** distinguish melee pressure, ranged cover use, and hybrid timing with clear cues. Use the existing spell roles and style resistances. Ordinary elemental spells have an agreed straightforward damage ladder; do not add new status systems to all schools by default.
- **A resource-to-use chain:** make one existing material useful before adding many professions. Food preparation is a good candidate because it strengthens the expedition/resupply loop.
- **Exploration rewards and access:** authored discoveries, a small map/wayfinding aid if needed, and meaningful reasons to revisit a location.
- **Long-term pursuit:** named equipment sources, collection progress, and challenge unlocks. Scarcity becomes motivating when players understand the route to their goal.
- **A carry/storage policy:** currently the backpack is a name-to-quantity dictionary with no capacity check in add_to_backpack. Decide whether trip length is governed by supplies alone or also by inventory space. A restrictive bag and bank are not automatically required.
- **A ranged supply policy:** quiver scaffolding exists, but the economy review records no usable arrows/bolts or ammunition consumption. Decide explicitly whether ammunition is consumed, recovered, or abstracted. It need not block a melee-focused first slice.

## A concrete first adventure

Working concept: **The Roadside Job**.

1. At the tavern, receive starter equipment, a few usable meals, and a clear task to recover a parcel from a nearby goblin pocket. The parcel and task are new proposed content, not existing items.
2. Follow the existing road into the woodland. Populate a small pocket with enemies tuned to be beatable by a fresh character. Catalog level alone does not prove that difficulty.
3. Teach targeting, attacking, looting and eating through the task. If testing Magic, provide the chosen mana recovery method from the start.
4. Offer an optional tougher encounter with a visible reward. Let the player retreat. Use a safe marked position away from enemy pursuit for the hub.
5. Return the parcel for a guaranteed practical reward: supplies, a chosen starter sidegrade, or enough gold for a meaningful purchase. Normal drops remain a separate source of excitement.
6. Sell surplus, rest, save, and receive the next destination. Repeat once with a different loadout or route.

Success criteria: a new tester can identify a goal, complete it without developer menus, recover after a defeat, use or spend a reward, resume saved progress, and explain why they would take another trip. Verify both the ordinary path and interrupted/reloaded objective completion so rewards cannot be duplicated or lost.

## Suggested build order

1. Agree the small adventure and its reward. Establish minimal save/load, defeat/respawn, and starter state.
2. Populate one encounter area with repeatable spawns. Add food use, safe rest, and mana recovery if Magic is in the slice.
3. Add the single objective, return reward, one vendor and useful purchase. Save the complete loop state.
4. Playtest the full adventure with developer menus closed; tune travel, recovery, reward clarity and the reason to repeat.
5. Add one production chain, one discovery, and one more encounter decision. Expand locations only as those loops need them.

Defer broad profession rosters, housing, guilds, raids, procedural worlds, and large quest systems. They are possible future directions, not missing requirements for the next playable milestone. If shared play is essential to the game's identity, settle that architectural requirement early without making it the content milestone.

## Design tensions to revisit with play evidence

- Defense currently earns XP from damage received, so better armor can reduce training speed. Decide whether the intended optimal play should reward enduring harm or effective defense. This is a review question, not a requested rule change.
- The 80-hour melee model is a calculation, not demonstrated content coverage. It assumes immediate equipment acquisition and 70% combat uptime. Its idealized first 1–10 band is about two hours, so the first session needs goals and rewards inside a tier.
- Magic recovery must be chosen before casting pace or XP/hour can be judged. The current documentation notes that a fresh mage cannot sustain enough casting to reach the next level on its initial mana.
- Useful-effect requirements for utility cast XP remain an open decision; the docs note that empty/full-health casts can currently award XP. Review this when recovery makes repeat casting sustainable.
- Tiers 8 and 9 lack authored equipment according to the current progression/calibration notes. That is a later content gap, not a prerequisite for proving the first adventure.

## Evidence anchors

Paths below are relative to the active Aetheria game repository unless marked as supporting workspace files.

- `godot_client/scripts/main.gd`: constructs a fresh PlayerState and `WorldState.new(player, [])`; developer spawn entry point; kill loot/gold handling; player death branch continues without a recovery flow.
- `godot_client/scripts/player_state.gd`: six skill states, mana, gold, backpack, gear; fresh state initialization.
- `godot_client/scripts/inventory_system.gd`: equipment/quiver and backpack transfer; no capacity check in add_to_backpack.
- `godot_client/scripts/ui_inventory_menu.gd`: equip/drop inventory context actions; no Eat action found.
- `godot_client/scripts/world_interaction.gd`: monster, item and walk interactions.
- `godot_client/scripts/combat_system.gd`: pursuit/leashing, target refresh, hybrid attack selection already exist.
- `godot_client/docs/SkillProgression.md`: current skill effects, Defense XP, in-memory progress and absence of player save data.
- `godot_client/docs/CoreSpellbook.md`: existing damage, area, healing, wall and knockback roles; spell design guardrails.
- `godot_client/docs/ExperienceRates.md`: absent mana recovery and open useful-effect XP decision.
- `godot_client/docs/LootEconomyReview.md`: approved loot direction, intended NPC/direct trade economy, absent prices/ammunition and related gaps. Older sections can lag newer code; confirm a specific encounter before implementation.
- `godot_client/README.md` and supporting `work/map-planning/wilderness-section-plan.md`: existing tavern, farm, road and woodland geography.
- Supporting `work/xp-balance/80-hour-melee-model.md`: calculated pacing and limitations.

No game code, balance, art, map, or approved rule was changed for this assessment.

## Tracking work in Sentinel

Open Sentinel's **Roadmap** tab to use the original Missing loops, Core mechanics,
and Build next views. The 18 manual checklist tasks share completion state across
all three views. The overall counter counts each task once; related loop/build
stage counters summarize the same saved tasks. Check work after completing it,
and uncheck to reopen. These records do not scan game code or assert that a
feature passed its tests. The original source assessment remains a dated starting
snapshot. Use the game's applicable checks before considering implemented work
verified.
