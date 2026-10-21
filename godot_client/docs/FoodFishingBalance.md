# River fish, healing, and value

The ten-species roster is selected by the user. Healing is the first implemented
balance pass; prices have been revised around the user's gold-value anchors,
including an explicit 800-gold purchase / 350-gold sale value for Sunfish.
These are not measured economy or encounter-balance results.
Fish definitions live in `data/items.json`; `FishingSession.FISH` is the catch
pool used by the existing fishing minigame. See [Fishing.md](Fishing.md) for
rod tiers, cast-range mastery, actual first-catch levels, food grades, rarity weights,
distance gates, and fight strength. Species skill requirements below are only
one gate; casting range and food can delay actual access to a higher level.

## Current balance values

Prices are per fish, from the player's perspective. `sell_value` is gold received
when selling to an NPC; `buy_price` is gold paid to purchase from an NPC. Shops
and transactions are not implemented; these are stored baseline prices, with
sell value displayed in inventory details. Direct player trade prices remain
negotiated rather than fixed by this table.

| Fish | HP restored | Sell to NPC (gold) | Buy from NPC (gold) | Species skill requirement |
| --- | ---: | ---: | ---: | ---: |
| Reedkip | 40 | 4 | 10 | 1 |
| Marlo | 60 | 7 | 18 | 1 |
| Bracken | 90 | 14 | 35 | 10 |
| Kessa | 120 | 25 | 60 | 20 |
| Veilfin | 160 | 42 | 100 | 30 |
| Lumara | 200 | 70 | 160 | 40 |
| Vesper | 250 | 110 | 250 | 50 |
| Moonfin | 300 | 165 | 380 | 65 |
| Velora | 360 | 245 | 560 | 80 |
| Sunfish | 440 | 350 | 800 | 90 |

The four earlier fishing-prototype names were replaced, preserving IDs 203â€“206:
Reedkip 203, Marlo 204, Bracken 205, Veilfin 206. Kessa is 207; Lumara through
Sunfish use 208â€“212. Removed food IDs remain unused. The catalog has 206 items:
188 after the earlier food cleanup, eight fishing supplies, and these ten fish.

## Why these values

- User economy anchors: 100,000 gold is a substantial amount. A complete Bronze
  loadout should be worth roughly 2,500 gold, and its Runite counterpart roughly
  300,000 gold. Each target includes the armor, one weapon, cape, two rings, and
  necklace. These are loadout valuation targets; per-item equipment prices,
  weapon-family differences, and equipment vendor spreads have not been assigned.
- Health remains 20 HP per level, starting at 200 and reaching 2,000 at level 100.
  Reedkip heals 20% of starting HP; Sunfish heals 22% of maximum-level HP.
- Higher fish offer more healing per action, important when eating costs attack
  time. Cheaper fish retain a lower gold cost per HP, giving a reason to choose
  economical supplies where immediate healing is less urgent.
- Reedkip costs 10 gold to buy and sells for 4, keeping beginner food inexpensive
  relative to a 2,500-gold Bronze loadout. Prices rise toward Sunfish at 800/350,
  as directed by the user. The other nine fish prices interpolate the scale;
  there is no fixed 3:1 vendor spread. All NPC buybacks stay below purchase prices.
- At these anchors, 100,000 gold buys 125 Sunfish. Selling 286 Sunfish earns
  100,100 gold; selling 858 earns 300,300. These are value comparisons, not
  fishing-time predictions. Goblin gold payouts have not been changed.
- Fishing catch times, failure rates, XP, actual gold/hour and food consumed per
  expedition need playtesting. These values are an initial calibration, not a
  promise of specific trip lengths or profit rates.

## Implemented consumption

- Heal immediately for the authored fixed amount, capped at missing HP. Excess
  healing is lost; no overheal or gradual recovery is applied.
- Spend one fish on a successful eat. Full HP, death, missing fish, or a blocked
  action consume nothing and do not start a new cooldown.
- A shared 1.8-second meal cooldown prevents rapid eating, including switching
  between fish. This is separate from the weapon-dependent attack penalty.
- Each successful eat adds one full attack interval of the currently equipped
  weapon to the remaining attack timer. Unarmed uses its own attack interval.
  For example, a Bronze Dagger adds 1.35 seconds and a Bronze Warmaul adds 3.0.
  Existing waits are preserved; eating never replaces a longer timer with a
  shorter one. This supersedes the original fixed 1.8-second attack penalty.
- While that penalty is pending, switching to a slower weapon extends its
  captured weapon interval by the difference once. Switching faster cannot
  shorten it, and repeated refreshes do not repeatedly extend it. The lock lives
  on PlayerState so recreating the combat actor cannot clear it.
- Melee and ranged attacks honor the delayed timer. Spell inputs remain blocked
  until both the meal cooldown and pending food attack lock expire. Eating
  during an active spell cast is rejected. Repeated meals preserve pending time
  and add another equipped-weapon interval rather than restarting a shorter wait.
- Fishing level gates catching, not eating. A beginner can eat a gifted or
  purchased high-level fish. No Health-level gate on eating exists.
- Catches are raw and cannot be eaten. The existing unprefixed species names
  are now the cooked forms, retaining the healing and price values above.
  Raw/cooked/burnt items and Cooking logic are implemented; playable campfire
  interactions await the separate firemaking work. See [Cooking.md](Cooking.md).
- Fish have `generic_loot: false`, keeping them out of generic monster drops.
  Named monster tables contain no fish; fishing is their current normal source.

## Food controls and feedback

Food usability update, 2026-10-20:

1. Catches land in the nine-slot Fishing Pale. Use **Move to inventory** for a
   fish or **Empty Pale** to move the raw catches into the backpack. Cooking
   logic converts raw fish to edible food; the campfire interaction is deferred.
2. Open the journal with **I**, select a cooked fish, and choose **Set quick food [H]**
   from its details or right-click menu. Selection does not consume food.
3. Press **H** or click the food HUD button to eat without reopening the journal.
   The journal's existing **Eat fish** action uses the same transaction.

The HUD shows the selected species, carried quantity, authored heal amount,
readiness and the shared cooldown. Success feedback reports actual HP gained and
current/max HP. Failed attempts explain full health, cooldown, casting, defeat,
or missing food without spending a fish. Combat HP is authoritative, so stale UI
state cannot erase recent damage.

Before a selection exists, the lowest-healing food in the backpack is the initial
default. Once selected, a depleted species stays selected; the game never silently
switches to another, potentially expensive food. Choose another species explicitly.
This selection belongs to PlayerState and follows the character between loaded
areas; no disk persistence was added.

Held-key echoes do not eat repeatedly. H does not consume food while editing text,
inside the fishing modal, or while preview/testing menus own the input. Fishing
Pale contents must first be moved to the backpack. The HUD hides behind modal
menus and remains on-screen at the tested 960x540, 1280x720, and 1920x1080 sizes.

## Agreed recovery direction and remaining work

There is no passive health regeneration, hunger meter, or healing potion.
Town-center recovery to full HP within 15 seconds is deferred until a town exists.
The current playable area is the outskirts; no healing zone was added there.
Mana potions are allowed but not implemented. Existing Mending Light remains;
the ban on healing potions does not ban healing magic. Meat is deferred.

Backpack quantities remain unrestricted. A finite food-carrying policy, campfire interactions,
regional species pools, and actual NPC transactions remain open. The current
prototype spots share one level-gated catch pool; species habitat descriptions
do not enforce geography or time-of-day requirements.

## Validation

Food usability checks on Godot 4.5.1, 2026-10-20:

- `res://scenes/dev_tools/food_input_smoke.tscn`: 27 checks, zero failures, in
  both headless and actual OpenGL runs. Covers catch landing/transfer, native
  context-menu selection, H and HUD consumption, feedback, key repeat, species
  switching, depletion, full HP, death, text-entry focus, stale UI HP, no passive
  healing in the outskirts, and HUD bounds at three viewport sizes. Rendered
  screenshots were inspected outside the repository.
- `res://scenes/dev_tools/fish_food_smoke.tscn`: 89 checks, zero failures. Covers
  actual healing, consumption, overheal/death, shared cooldown, additive melee
  and ranged timers using ten real weapon/unarmed profiles, stale actor speed,
  slow/fast weapon swaps, actor refresh, repeated eating, spell blocking beyond
  the meal cooldown, level gates, all ten species being reachable, and exclusion
  from generic monster loot.
- `res://scenes/dev_tools/fishing_pale_smoke.tscn`: 58 checks, zero failures.
- `tools/test_inventory_items.py`: 38 checks, zero failures.

Weapon-delay integration was also verified against the current
`res://scenes/dev_tools/food_input_smoke.tscn` (30 checks),
`res://scenes/dev_tools/bronze_combat_smoke.tscn` (2,635 checks), and
`res://scenes/dev_tools/cooking_smoke.tscn` (1,259 checks), all with zero failures.
Food values, weapon cadence, and combat damage formulas are unchanged.

These tests establish mechanics, not balanced long-term play. Diagnostic logs
and machine-specific validation output are stored outside the repository.
