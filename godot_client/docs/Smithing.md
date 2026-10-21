# Smithing

Smithing is a noncombat skill using the existing level 1–100 XP curve. Click a
nearby Blacksmith's Furnace or Anvil in East Outskirts to open its existing
station panel. Combat, casting, death and cooking block new Smithing work.

| Tier | Material | Smithing level | Initial heat width | XP per bar |
| ---: | --- | ---: | ---: | ---: |
| 1 | Bronze | 1 | 30% | 40 |
| 2 | Iron | 10 | 30% | 80 |
| 3 | Steel | 20 | 25% | 120 |
| 4 | Blacksteel | 30 | 22% | 159 |
| 5 | Mithril | 40 | 20% | 199 |
| 6 | Adamantite | 50 | 18% | 239 |
| 7 | Starforged | 60 | 16% | 279 |

Each existing ore smelts into one corresponding ingot, following the user's
approved one-ore/one-bar rule. No fuel or alloy ingredients are added. Existing
equipment recipes remain Bronze Dagger (one ingot) and Bronze Longsword (three).
All other anvil costs remain pending and disabled. No items, loot, equipment
stats or equipped-item requirements have changed. Historical Runite equipment
aliases resolve through the existing catalog migration to Starforged.

## Furnace

Choose 1–10 bars. Hold the bellows button to heat the furnace; release to cool.
The gold section marks the correct fraction of the entire gauge. Progress
pauses outside that section. Excess heat starts a consecutive overheat timer;
returning to the range resets it. Timer expiry destroys every reserved ore in
the batch, produces no ingots and awards no XP.

Proficiency is `clamp((Smithing level - required level) / 30, 0, 1)`. The range
widens linearly from the tier width to a configurable maximum (currently 55%),
centered on 60% heat. Grace rises from 2 to 6 seconds. At **exactly +30 levels**,
burning becomes impossible. Excess heat still pauses progress.

Provisional duration is `6 + 2 × (bars - 1)` seconds of correct heat. Cooling is
6.5% of the gauge per second; bellows add 24% per second before cooling. Timings,
maximum width, target lifetime and animation timings live in `data/smithing.json`,
separate from approved recipe costs.

Inputs are reserved atomically when work starts. Cancelling ordinary unfinished
work refunds once. A hot batch continues cooling/burning while its panel is
closed, then refunds if it cools safely; closing never resets its timer. Damage,
combat, casting or leaving reach interrupts unfinished work. Pending refunds
and completed rewards survive scene travel and retry when inventory permits.

## Anvil and quenching

Forge one workpiece at a time. Click the highlighted circular target before it
moves. A miss or wrong strike makes no progress and never destroys anything.
Sword, axe, helmet, chestplate, legs, shield, blunt weapon and component patterns
are independently configurable. Each pattern repeats twice; four reusable
shaping stages avoid simulation. Forging has no cooling or reheating.

The completed hot object lowers into a barrel. Bubbles, steam and a synthesized
filtered-noise hiss accompany immersion. Its glow ends, then its actual inventory
sprite rises. Inventory and XP are awarded once after the rise. Closing/reopening
preserves quenching; scene teardown settles the already completed workpiece.

Transactions reuse canonical names and overflow validation. Reserved materials
cannot be sold, dropped or spent twice. Immediate `CraftingService.craft` calls
cannot bypass Smithing. Concurrent crafting/Cooking starts are rejected.
Inventory overflow retains a pending reward without wrapping or early XP.

## XP pacing

Smelting pays XP per ingot; forging pays the same tier reward per ingot consumed.
A Bronze Longsword earns three times a Bronze Dagger's XP. Only completed work
awards XP through `PlayerState.add_skill_experience`, with the existing cap,
journal and session tracking. The original combat calibration is unchanged.

The target is approximately **60 active gameplay hours** to level 100. The
reference uses ten-bar batches, the best unlocked tier and 80% valid-heat uptime,
with ore available. It excludes gathering, travel and interruptions. An independent
batch simulation reaches the cap in **60.02 hours**. Perfect control is faster;
batch sizes, misses, forging and gathering change actual pacing. This is a
tuning benchmark, not sixty hours of human playtesting.

`SmithingRules.xp_per_bar` scales the 10/20/30/40/50/60/70 tier ratio against the
shared curve and configured timing/target, rounding to integer XP.
`xp_per_bar_override` allows explicit per-tier rewards without code changes.

## Verification and remaining content

```text
python tools/test_smithing.py --godot <installed-Godot-4.5.1> --render
python tools/test_cooking.py --godot <installed-Godot-4.5.1>
python tools/test_inventory_items.py --godot <installed-Godot-4.5.1>
```

Coverage includes every batch size/tier width, unlocks, +29/+30 mastery,
overheat failure/recovery, bellows/cooling, misses/shaping, quench delays,
item/XP conservation, pending recipes, concurrency, overflow, lifecycle and
actual station GUI clicks. Rendered captures cover shaping and quench phases.
Evidence is kept outside the repository.

Higher equipment categories reuse these patterns and animation when their costs
are approved. Existing inventory sprites are reused; missing future art has a
simple fallback. No permanent new ore tiers or expensive metal simulation exist.
