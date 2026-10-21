# Cooking flip minigame

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

Each fish heats for its existing **3 seconds**, then displays **FLIP!**.
Click the button or press **Space / Enter** once. A successful flip always
produces the cooked item; a missed finite window produces the existing burnt
item. There are no random burn rolls. Success alone awards the original XP.

The window comes from that food's authored requirements in `data/items.json`:

```text
if level >= no_burn_level: window = INF
else:
    progress = clamp((level - cooking_level) / max(1, no_burn_level - cooking_level - 1), 0, 1)
    window = lerp(0.8, 2.5, progress)
```

`CookingSession.MIN_FLIP_WINDOW` and `MAX_FINITE_FLIP_WINDOW` configure the
finite limits. At unlock the player gets **0.8 seconds**; immediately before
mastery they get **2.5 seconds**. A one-level span stays at 0.8 seconds until
mastery. Invalid/missing mastery metadata never invents an untimed threshold;
invalid catalog recipes cannot start.

At the exact no-burn level the timer says **SAFE**, never expires, and still
requires a manual flip. Mastery is per food: Reedkip is safe at 21 while a
newly unlocked Sunfish at 90 still has a 0.8-second window. Every batch fish
recalculates its window from the current Cooking level when its prompt opens.
The XP curve, rewards, cooked healing and item IDs are unchanged. Reaction time
and a short 0.65-second feedback animation add to the existing heating interval.

## Transactions and interruptions

Starting or partially heating a fish spends nothing. When the FLIP prompt
appears, exactly one raw fish is reserved from the backpack. The session then
resolves exactly one cooked/burnt output, with original XP only on success.
Rewards resolve synchronously before animation; repeated clicks cannot replay
an outcome. All existing inventory-slot and XP-cap behavior still applies.
Cook all requires a separate manual flip for every fish, including at mastery.

**Closing/interruption during a live FLIP prompt burns its reserved fish**,
with no XP, and cancels the rest of the batch. This prevents resetting a
nearly expired prompt by closing/reopening. Cancellation during heating keeps
that unfinished raw ingredient; already resolved items and XP remain. An
abandoned session cannot restore its reserved ingredient. The game currently
keeps skills/inventory in memory and has no durable reconnect/save protocol.

Movement, damage, death, combat/target acquisition, spell casting, eating
cooldown, losing heat/range, or Cooking falling below the recipe requirement
cancels cooking.
Missing ingredients cancel before a new reservation. The weak per-player lock
covers heating, the prompt and feedback, and is released on completion, close,
travel or teardown. Invalid time steps are ignored. A long heating frame opens
a fresh full prompt window; unseen overshoot is not charged to the player, and
large time steps never auto-complete a batch or skip feedback.
The controller advances once per process/render frame, so physics catch-up
steps cannot shorten a prompt before it is first presented.

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
# When state == CookingSession.State.FLIP_PENDING, forward a manual input:
var flip_results := cooking.flip()
# Both paths return input, output, burnt, flip_window, experience,
# level_before, level_after. Record each returned XP reward once.
cooking.close() # Cancel unfinished work on exit, travel or controller teardown.
```

Keep the session alive while cooking. Before advancing it, synchronize the
authoritative player position, HP, combat flags and fire state. The
controller owns mutually exclusive interactions (including closing fishing),
modal input and scene transitions. `cooking_controller.gd` now supplies this
lifecycle for `CookingStation` and `CookingPanel` at the tavern stove. It uses
one persistent heat source per stove, synchronizes actor state, advances only
the visible panel's session, records Cooking training XP, and releases the
session on close, travel or teardown.

## Validation

`res://scenes/dev_tools/cooking_smoke.tscn` exercises recipe and item coverage,
every level's reaction window, deterministic flips/misses, untimed mastery,
level-ups inside batches, XP caps, cancellation, duplicate sessions, raw fishing rewards,
inventory transfer, and the existing eating path. The real `cooking_ui_smoke`
and `tavern_integration` scenes cover the pan,
actual button/key input, training XP, finite burns, mastery, close/reopen,
damage, travel and teardown. Optional `--output=<outside-repo-folder>` captures
UI evidence in a rendered engine run. The adjacent fishing, pale,
food input, individual slots and skill editor scenes also run through:

```powershell
python tools/test_cooking.py --godot <installed-Godot-executable>
```

The runner rejects script errors even when Godot exits zero. Detailed logs and
machine-specific evidence go outside the repository.

## Presentation and authority

The shared Cooking panel reuses the existing FantasyUI frame, nearest-filtered
inventory fish image, and a reusable code-drawn pixel pan. Heat flicker, a
short rotating food toss, success sparks and burn smoke are presentation only.
No new raster art is required. Fish retain the existing generic placeholder;
there are no dedicated cooking sound effects in this implementation.

The running Godot client is the local gameplay authority; the dormant network
placeholder is not a multiplayer server. UI inputs request `flip()` without a
client-supplied outcome. The controller synchronizes actor HP/position and stove
state, and the session validates conditions before both timing and flip
transactions. A future multiplayer transport must own session timing and
reservation on the server, with latency-aware input validation; this change
adds no unverified client-success endpoint.
