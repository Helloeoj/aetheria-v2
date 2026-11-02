# Smithing

Furnace/anvil recipe buttons open the guided Smithing games in the active game,
offline and online. Existing recipes, equipment stats, inventory and item sprites
are retained. Steel consumes one Iron Ore and one Coal per ingot. The later
[Starforged drop-only decision](StarforgedAcquisition.md) remains enforced;
retired materials and manufacturing recipes are not reintroduced.

| Material | Required Smithing | Initial gauge width | XP per bar |
|---|---:|---:|---:|
| Bronze | 1 | 30% | 46 |
| Iron | 10 | 30% | 92 |
| Steel | 20 | 25% | 138 |
| Blacksteel | 30 | 22% | 184 |
| Mithril | 40 | 20% | 230 |
| Adamantite | 50 | 18% | 275 |

Choose 1-10 bars at a furnace. Hold bellows to heat and release to cool. Smelting
progresses only inside the gold band, measured against the whole gauge. Cold
pauses progress; excess heat pauses progress and counts consecutive overheating.
Expired grace destroys every reserved ingredient and awards no bars or XP.

Proficiency is `clamp((Smithing level - required level) / 30, 0, 1)`. Heat width
and grace increase with proficiency. At exactly +30 levels burning is impossible;
overheating still pauses progress. Configurable defaults are a 60% heat center,
maximum width 55%, grace 2-6 seconds, cooling 6.5%/second and bellows 24%/second
before cooling. Valid-heat duration is `6 + 2 * (bars - 1)` seconds. Approved
tier-7 width 16% remains configured, without enabling Starforged crafting.

Forge one workpiece at a time. Clicking the highlighted circular target advances
shaping. Wrong clicks and missed targets never destroy materials or progress.
Sword, helmet, chestplate, legs, shield, blunt and component patterns use
meaningful locations; an axe pattern is available for future approved recipes.
Targets, counts, lifetimes and four reusable shaping stages are configurable in
`data/smithing.json`. Forging has no cooling/reheating mechanic.

The completed hot item floats above a barrel, lowers into water, produces bubbles,
steam and a reusable synthesized hiss, loses its glow and rises using its actual
inventory texture. Default lower/immerse/raise times are 0.8/1.8/1.0 seconds.
Inventory and XP are awarded once after the rise. Closing/reopening cannot replay
the reward. The original minigame presentation is reused; no world props moved.

Inputs are validated and reserved atomically before starting. Missing either
Steel ingredient consumes nothing. Reserved materials cannot be spent twice.
Combat, damage, casting, death and lost station reach interrupt unfinished work.
Cancellation refunds once; a hot batch must cool safely and keeps its burn timer
while hidden. Finished work waits safely when a stack is full.

The server owns heat, clocks, targets, reservations, rewards and XP, using the same
session rules as offline play. Clients send identity-bound starts, expiring
bellows input and strikes tied to encounter/action/target IDs. Clients never award
inventory or XP. Start/cancel intents retry safely across host persistence pauses;
instant `craft` requests cannot bypass either minigame. Freezes pause activity
clocks and stale held input expires before resumption.

Save schema 5 adds Smithing XP and a private reservation/earned-work ledger.
Versions 1-4 default absent Smithing XP to zero without repairing corrupt fields.
Live client projections do not settle work. A real reload returns unfinished
ingredients or preserves earned finished work once, resolving outstanding burn
risk. Full output/refund stacks retain their claim, including after area travel.
Stable settlement transitions are persisted without saving every heat frame.

Smelting XP is per successful bar; forging XP is per ingot consumed. Smithing uses
the existing level 1-100 curve, cap, journal and practice tools, without affecting
combat level. The configurable 60-hour reference uses ten-bar batches, the best
craftable tier through Adamantite, 80% valid-heat uptime and available ore. The
simulation reaches max in 60.09 active hours. Gathering, travel, control quality,
forging and batch choices change real pacing; this is not human playtesting.

Run `tools/test_smithing.py --godot <engine> --render` for rules, real station UI,
authority/remote sessions, save recovery, Bronze/catalog and crafting tests.
Rendered captures cover billet/shaping and lowering/steam/rising/finished phases.
Additional account, networking, inventory, cooking/fishing and Starforged tests
protect existing gameplay. This validates local authority and transport adapters,
not a deployed remote-account end-to-end session. Client, world and account
service must all use the updated code for online play.
