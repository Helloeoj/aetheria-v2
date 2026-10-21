# Cooking logic

The cooking rules were implemented 2026-10-20 and are now usable at the
[roadside tavern stove](Taverns.md). Left-click, or right-click **Cook at stove**,
to approach and open the Cooking panel. **Cook 1** and **Cook all** use the
existing rules below. Player-made campfire placement, firemaking, fuel and
lifetime remain deferred.

Cooking is independent from Fishing and combat level. It starts at level 1,
uses the existing level 1–100 XP curve, and appears automatically in the Skills
journal, skill editor and XP session meter. Skill progress remains in memory,
as with the other skills; this change adds no disk save system.

## Fish and recipes

Every species has raw, cooked and burnt item definitions in `data/items.json`.
Fishing only awards **Raw <species>**, initially stored in the Fishing Pale.
Move catches into the backpack before cooking. Raw and burnt fish cannot be
eaten or selected as quick food. Cooked and burnt fish cannot be cooked again.
All three forms use one inventory slot per fish, remain outside generic loot,
and reuse the existing generic fish placeholder. No art was generated.

The existing unprefixed names and IDs (for example `Reedkip`) identify the
**cooked** form, preserving current food, price and item references. Raw forms
hold the fishing metadata. Existing in-memory unprefixed fish are consequently
cooked; future catches always have explicit raw names. Authored healing and
prices are unchanged on cooked food; raw fish initially share the species price
anchors. Burnt fish have zero healing and zero value. NPC shops remain deferred.

| Species | Tier | Cooking level | No-burn level | XP per successful cook | Cooked healing |
| --- | ---: | ---: | ---: | ---: | ---: |
| Reedkip | 1 | 1 | 21 | 40 | 40 |
| Marlo | 2 | 10 | 30 | 60 | 60 |
| Bracken | 3 | 20 | 40 | 90 | 90 |
| Kessa | 4 | 30 | 50 | 120 | 120 |
| Veilfin | 5 | 40 | 60 | 160 | 160 |
| Lumara | 6 | 50 | 70 | 200 | 200 |
| Vesper | 7 | 60 | 80 | 250 | 250 |
| Moonfin | 8 | 70 | 90 | 300 | 300 |
| Velora | 9 | 80 | 100 | 360 | 360 |
| Sunfish | 10 | 90 | 100 | 440 | 440 |

Each attempt takes **3 seconds**, regardless of outcome. At the recipe's unlock
level, burn chance is **30%**, decreasing linearly to **0%** at its no-burn level:

```text
mastery = min(100, required Cooking level + 20)
progress = clamp((Cooking level - required level) / (mastery - required level), 0, 1)
burn chance = 0.30 * (1 - progress)
```

For a normal 20-level mastery span, 0/5/10/15/20 extra levels mean
30/22.5/15/7.5/0% burn chance. Sunfish compresses mastery into levels 90–100,
so every species eventually becomes impossible to burn within the level cap.
Requirements below the unlock are rejected, rather than rolling a harder cook.
This is a RuneScape-inspired progression, not a copy of its recipe tables.

These XP rewards are an initial tuning pass, not a measured 80-hour progression
calibration. At three seconds per attempt, perfect uninterrupted Sunfish cooking
would yield 528,000 XP/hour before downtime and supply constraints. Burns award
no XP; catching, moving, eating and discarding fish never award Cooking XP.

## Transactions and interruptions

Starting or partially completing an attempt spends nothing. At completion,
one backpack raw fish is replaced by exactly one cooked or burnt fish. Only
successful cooking awards XP. XP is capped by the existing progression system.
Each fish in a batch checks the current Cooking level, so an earlier level-up
immediately reduces the next fish's burn risk. Extra frame time carries between
attempts in that batch; it never carries into another batch.

Cooking requires a burning campfire within 2 simulation units. Movement, damage,
death, combat/target acquisition, spell casting, eating cooldown, losing heat or
range, a lowered skill requirement, or missing ingredients cancels cooking.
Completed results remain; an interrupted attempt keeps its ingredient. A weak
per-player session lock prevents overlapping cooking actions without keeping an
abandoned session alive. Large time steps process multiple completed attempts;
negative and non-finite time steps are ignored.

There is no Cooking or Fishing level requirement to **eat** cooked food. Existing
healing, shared 1.8-second food cooldown, quick-food selection, and attack delay
continue to apply.

## Campfire integration contract

`CookingCampfire` is a shared, nonvisual heat-source state. It starts inactive;
firemaking will set `active`, position and any lifetime rules. Its position must
use PlayerState simulation coordinates, not map pixels. Do not create a fresh
always-active source every frame. Set `active = false` before the next cooking
advance when the actual fire is extinguished, removed or expired.

```gdscript
var heat := CookingCampfire.new(campfire_simulation_position)
heat.active = true # Supplied by the actual fire's authoritative state.
var cooking := CookingSession.new(player, heat, combat_engine)
var error := cooking.start("Raw Reedkip", 1) # Empty string means started.
# Cook-all passes the selected raw fish's current backpack quantity.
var results := cooking.advance(delta)
# Each result: input, output, burnt, burn_chance, experience,
#              level_before, level_after.
cooking.close() # Cancel unfinished work on exit, travel or controller teardown.
```

Keep the session alive while cooking. Before advancing it, synchronize the
authoritative player position, HP, combat flags and fire state. The future
controller must own mutually exclusive interactions (including closing fishing),
modal input and scene transitions. `cooking_controller.gd` now supplies this
lifecycle for `CookingStation` and `CookingPanel` at the tavern stove. It uses
one persistent heat source per stove, synchronizes actor state, advances only
the visible panel's session, records Cooking training XP, and releases the
session on close, travel or teardown.

## Validation

`res://scenes/dev_tools/cooking_smoke.tscn` exercises recipe and item coverage,
every level's burn curve, actual seeded burn rolls, mastery, level-ups inside
batches, XP caps, cancellation, duplicate sessions, raw fishing rewards,
inventory transfer, and the existing eating path. The adjacent fishing, pale,
food input, individual slots and skill editor scenes also run through:

```powershell
python tools/test_cooking.py --godot <installed-Godot-executable>
```

The runner rejects script errors even when Godot exits zero. Detailed logs and
machine-specific evidence go outside the repository.
