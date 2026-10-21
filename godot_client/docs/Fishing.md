# Fishing

The following values are an initial playable balance pass. Fish tiers follow
ascending healing; healing, XP, and gold values remain in the item catalog.
Catch rates and difficulty still need human playtesting.

## Test now

Restart the game, then click **Test fishing [P]** or press **P** anywhere.
The earlier F9 shortcut conflicted with Godot 4.5's **Suspend/Resume Embedded
Project** command, freezing editor-run gameplay. Fishing no longer handles F9.
It supplies one of each of the five rods and at least 50 of each fish-food grade,
without moving the player or changing skills. Reopening refills food to 50
without duplicating rods. Click **Test skills [K]** or press **K** to adjust Fishing level for testing.
Inside fishing, **Skills [K]** switches to the same editor, cancelling an active
cast without refunding spent food. Press **P** afterward to test the new level.
For the full roster, set Fishing to 100 and select Demon Rod and High Grade
Fish Food. Cast at least 200 ft to include Sunfish (95-100% power).
Catches and XP enter the real in-memory player state. Saves and supply vendors
are not implemented. Raw catches use the ten PixelLab species icons from
`Assets/Items/fish_001/`. Rods, fish food, cooked fish and burnt fish still use
generic placeholders; authored item art takes precedence.

In the world, the two river spots are at `(1300, 260)` and `(1400, 650)`.
Walk to the bank and click a marker, choose its right-click Fish action, or
press **F** nearby. Editable `FishingSpot` nodes live under `Combat` in
`scenes/EastOutskirtsLayered.tscn`; place `shore_offset` on a walkable bank.
The hidden practice anchor is excluded from normal world markers.

## Rod progression

| Rod | Unlock level | Range at unlock | Full range level | Permanent cap | Base input | Reel speed |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Beginner | 1 | 15 ft | 10 | 60 ft | 1.20 | 9.0 ft/s |
| Apprentice | 20 | 60 ft | 30 | 90 ft | 1.55 | 10.5 ft/s |
| Pro | 40 | 90 ft | 50 | 120 ft | 2.09 | 12.0 ft/s |
| Master | 60 | 120 ft | 70 | 160 ft | 2.53 | 13.5 ft/s |
| Demon | 80 | 160 ft | 90 | 200 ft | 3.08 | 15.0 ft/s |

Maximum available range interpolates linearly with each Fishing level from the
unlock range to the permanent cap. It stops growing at mastery, even at Fishing
100. The Beginner uses the requested levels 1-10; other rods master ten levels
after their unlock. Upgrading rods never reduces the range already earned.
For example, Beginner ranges are 15/20/25/30/35/40/45/50/55/60 ft at levels 1-10.

The cast meter rises from 0% to 100% over 0.9 seconds and falls over the
next 0.9 seconds, repeating every 1.8 seconds. Zero power casts 10 ft. The top
95-100% is a marked perfect-cast band that reaches the current level's maximum range. Below it,
`distance = 10 + (power / 0.95) * (current maximum - 10)`. This avoids demanding
one exact frame at the peak when a species lives at a rod's full-range boundary.
The perfect band does not bypass level progression, bait or distance gates.

Click water or **Space** to start the meter and again to stop it. The panel
previews cast distance, current/permanent range, mastery level, skill resistance,
and eligible species count. A longer actual cast lands farther from shore.

## Easier fights and Fishing-level tolerance

All species' authored pull strengths are 15% lower than the earlier pass.
Fishing adds a tolerance divisor of `1 + 0.0025 * (level - 1)` to fish pull.
This means about 2.2% less effective pull at Fishing 10, 10.9% less at 50, and
19.8% less at 100, on top of the authored strength reduction. Raw dart direction
and timing stay species-specific.

Input is clamped to -1 through +1 and multiplied by the rod's base input strength.
The target lateral velocity is:

`raw fish pull / skill tolerance + player input * rod input strength`

The skill bonus reduces opposing fish force rather than increasing binary A/D
steering speed, which caused overshoot in the initial comparison. Rod input
remains predictable as Fishing rises. Neutral input still allows the fish to
pull; this is an active minigame rather than an automatic catch.

The safe corridor between the red bars is another 25% narrower than the previous
20% reduction, making it 40% narrower than the original width. Its half-width is
`min(0.78, rod width + 0.0015 * (level - 1)) * 0.6`, using authored rod widths
of 0.36/0.40/0.44/0.48/0.52. Scaling the final width applies the same reduction
to every pole and skill level, including the skill bonus. The revised balance
needs human feedback.

## Fish food is bait

These supplies feed fish; they are not healing food for the player.

| Fish food | Grade | Fishing level | Permitted species tiers |
| --- | ---: | ---: | --- |
| Low Grade Fish Food | 1 | 1 | 1-3 |
| Medium Grade Fish Food | 2 | 20 | 4-6 |
| High Grade Fish Food | 3 | 50 | 7-10 |

Food must match the fish's required grade exactly. Low, medium and high bait
have separate catch pools; higher grades cannot catch lower-grade fish.
Fishing level and minimum cast distance are additional hard requirements.
No rarity bonus or longer cast bypasses them. An empty eligible pool blocks
release without spending food. One food is spent on a valid release; cancelling while charging spends
nothing. Rods are reusable. Requirements are checked against the current cast
before consuming food, rather than against the previous cast's distance.

## Fish roster ranked by healing

Base weight is relative selection weight, not a fixed percentage. Maximum raw pull is before applying Fishing-level tolerance.

| Fish | Tier | Cooked heal HP | First reachable level | Rarity | Base weight | Required food | Minimum cast | Maximum raw pull |
| --- | ---: | ---: | ---: | --- | ---: | --- | ---: | ---: |
| Reedkip | 1 | 40 | 1 | Common | 100 | Low | 10 ft | 0.5525 |
| Marlo | 2 | 60 | 10 | Common | 75 | Low | 60 ft | 0.6800 |
| Bracken | 3 | 90 | 25 | Uncommon | 52 | Low | 75 ft | 0.8500 |
| Kessa | 4 | 120 | 30 | Uncommon | 36 | Medium | 90 ft | 1.0200 |
| Veilfin | 5 | 160 | 45 | Rare | 25 | Medium | 105 ft | 1.1900 |
| Lumara | 6 | 200 | 50 | Rare | 17 | Medium | 120 ft | 1.4025 |
| Vesper | 7 | 250 | 65 | Epic | 11 | High | 140 ft | 1.6150 |
| Moonfin | 8 | 300 | 70 | Epic | 7 | High | 160 ft | 1.8700 |
| Velora | 9 | 360 | 85 | Legendary | 4 | High | 180 ft | 2.1250 |
| Sunfish | 10 | 440 | 90 | Legendary | 2 | High | 200 ft | 2.3800 |

First reachable levels account for the earliest rod that can actually reach
the required distance, its mastery curve, food unlocks, and existing species
skill requirements. They are not new hardcoded level checks. Marlo still has
its underlying level-1 skill requirement, but a Beginner Rod cannot reach its
60-ft habitat at levels 1-9. At level 10, the same rod can reach Marlo using a
perfect cast. Bracken lives beyond that rod's cap and first becomes reachable
with an Apprentice Rod at level 25. Species skill gates, healing and prices have
not been changed.

Dart timing remains 1.0-1.8 seconds for Reedkip, declining incrementally to
0.55-1.125 seconds for Sunfish. The species data contains each exact interval.

Each dart picks a left/right pull at 60%-100% of that species' maximum strength.
Stronger fish have shorter dart intervals. At a given cast, filter all hard
requirements, then compute each eligible species' weight:

`base weight * (1 + (tier - 1) * clamp(cast distance / 200, 0, 1) * 0.35)`

Normalize those weights to select the catch. Longer actual casts increase the
relative odds of higher tiers within the eligible pool, including at equal
power when a better rod casts farther. There is no fixed catch percentage
across all distances, skill levels, and food grades. The fish's minimum cast
is checked when hooked; reeling closer does not invalidate an existing fish.

## Hook and fight

After release, the bobber lands and waits for a bite. The **!** alert gives two
seconds to hook with a click or Space. Move the mouse left/right or hold
**A/D** or arrows to pull against the fish. Keep the bobber inside the red
boundaries while reeling. Outside them, escape pressure rises by 0.8 per second;
inside, it recovers by 0.55 per second and the rod reels at its distance-adjusted speed.
Full escape pressure or a 60-second fight loses the fish. A brief mistake is
recoverable. The panel shows rod control, skill resistance, and current effective fish pull.

Short casts now have more reeling time and start visibly farther from the near
shore. For an actual cast of `d` feet, the pacing travel is
`d + 50 * clamp((200 - d) / 190, 0, 1)`; the rod's authored reel speed is multiplied
by `d / pacing travel`. This extra travel fades smoothly from 50 at 10 ft to zero
at 200 ft. The displayed remaining feet still count down from the actual cast,
and actual cast distance continues to own fish requirements and rarity weights.
Reeling pauses outside the corridor as before.

| Cast and rod | Previous ideal reeling time | New ideal reeling time |
| --- | ---: | ---: |
| 10 ft, Beginner | 1.1 s | 6.7 s |
| 15 ft, Beginner | 1.7 s | 7.1 s |
| 60 ft, Beginner | 6.7 s | 10.8 s |
| 200 ft, Demon | 13.3 s | 13.3 s |

These times assume the bobber stays inside the red bars. The bobber's starting
depth uses the same pacing travel, then approaches the near shore continuously
as remaining feet reach zero. At 200 ft, both the reel speed and entire visual
path are unchanged.

Landing awards XP once and places one raw fish in the **Fishing Pale**, the 3×3
catch inventory on the left. Each slot holds exactly one fish. A full pale
blocks the next cast before food is consumed. The pale belongs to the player,
so closing fishing, opening skill tools, or travelling areas preserves it.
Click or right-click a caught fish to **Move to inventory** or **Drop to ground**
at the player's feet. **Empty Fishing Pale to inventory** transfers all catches.
Transfers and drops award no additional XP. Fish occupy individual backpack
slots too; repeated species never share a displayed slot or a Drop all action.
Both containers use the exact same `ItemVisualLibrary` inventory-state texture,
using each raw species' authored PixelLab icon in both containers.

**Esc** dismisses a catch action menu first, then leaves fishing. **I** opens the
backpack after leaving, for inspecting transferred raw catches. They must be
cooked before eating; see [Cooking.md](Cooking.md) for the implemented logic
and the deferred campfire interaction.
Fish descriptions show rarity, required food,
minimum distance and fight strength. Damage or displacement interrupts fishing;
the world keeps running. Fishing does not affect combat level.
See [FoodFishingBalance.md](FoodFishingBalance.md) for healing, consumption and
existing gold values. Cooking logic is implemented; world campfire interactions
and habitat-specific pools remain deferred.

## Implementation and validation

`data/items.json` owns the authored rod and species numbers. `fishing_session.gd`
owns cast state, eligibility, weighting, forces and rewards. `ui_fishing.gd`
forwards player input and renders the lake view, using the shared `FantasyUI`
brass frame, navy palette, pixel headings and inventory styling. The environment-only
pixel-art backdrop is `Assets/UI/Fishing/aetheria_fishing_lake.png`; its generation
prompt is saved alongside it in `art-prompt.txt`. Tackle, bobber, water glints,
safe-area guides and meters remain separate drawings, with nearest filtering
and no per-row gradient lines. The visible guides still use the session's actual
safe boundary, and the bobber still uses its unchanged visual depth/pacing helper.
`fishing_spot.gd` draws the
world overlay separately from terrain artwork.
The skill tester builds rows from `SkillProgression.SKILL_IDS`, including Fishing,
and scrolls when future skills exceed the available space. Add new skills to
that registry to include them automatically; player initialization supplies a
default level for each registry entry.

```powershell
& $env:GODOT --headless --path godot_client res://scenes/dev_tools/fishing_smoke.tscn
& $env:GODOT --headless --path godot_client res://scenes/dev_tools/fishing_pale_smoke.tscn
& $env:GODOT --headless --path godot_client res://scenes/dev_tools/fish_inventory_slots_smoke.tscn
& $env:GODOT --headless --path godot_client res://scenes/dev_tools/fishing_cast_pacing_smoke.tscn
```

The fishing suite covers healing-ordered tiers, exact distance boundaries,
exact food-grade matching, skill gates, rarity weights, cast interpolation, force arithmetic,
each rod landing its strongest reachable fish with automated counter-steering,
incremental mastery at every level, unchanged caps, exact first-access milestones,
power-meter timing, actual UI input, rewards, interruption, placeholder art,
and P provisioning. These checks verify mechanics, not human difficulty.
Non-headless `-- --capture=<absolute directory>` writes previews outside the repo.

`res://scenes/dev_tools/fishing_input_smoke.tscn` additionally runs with live
physics and panel processing. It checks P and the on-screen entry button,
mouse press/release separated by frames, both native dropdowns, Cast, Leave,
and Escape. It guards against assigning the reserved F9 shortcut again.

`res://scenes/dev_tools/fishing_difficulty_smoke.tscn` compares the prior forces
against current force tolerance across 100 seeds per species with visible-motion-only
feedback sampled every 200 ms. It also checks a novice digital A/D controller
on Marlo. The comparison holds rod, level and distance constant and changes only
fish force/tolerance; both sides use the current narrower corridor and longer
short-cast pacing. These are controlled simulations, not human success rates.

`res://scenes/dev_tools/fishing_cast_pacing_smoke.tscn` checks the exact corridor
reduction, short-cast timing and visual travel, unchanged 200-ft timing and
bobber positions, and unchanged catch eligibility and rarity weights.

Horizontal fight movement stops at `boundary() + 0.24` on each side. The extra
0.24 lateral units (68.4 pixels in the 720-pixel lake) match the red-to-green guide
gap and stay constant across rods and skill levels. The absolute stop position
moves with each rod's red bars, giving wider corridors the same room outside
them. Strain and escape still use the existing red lines. Outward velocity is
cleared at a stop so corrective input can bring the bobber inward immediately.
No guide markers are drawn. `res://scenes/dev_tools/fishing_limits_smoke.tscn`
checks both limits with every rod at unlock, mastery and level 100, equal gaps,
screen containment, inward recovery, strain and unrewarded escape.
