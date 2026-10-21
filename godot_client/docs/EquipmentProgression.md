# Equipment progression

Weapons require **Attack**. Armor requires **Defense**. Required skill level is:

```text
max(0, (equipment tier - 1) × 10)
```

Bronze's level-0 requirement means unrestricted equipment; skills continue to
start at level 1. Bows, crossbows, wands, and staves use Attack requirements too.

| Tier | Required level | Current catalog |
| ---: | ---: | --- |
| 1 | 0 | Bronze |
| 2 | 10 | Iron |
| 3 | 20 | Steel |
| 4 | 30 | Blacksteel |
| 5 | 40 | Mithril |
| 6 | 50 | Adamantite |
| 7 | 60 | Runite |
| 8 | 70 | Equipment definitions needed |
| 9 | 80 | Equipment definitions needed |
| 10 | 90 | Existing Artifact equipment |
| 11 | 100 | Equipment definitions needed |

The policy supports the whole ladder. Missing tiers have no invented material,
stats, artwork, or drops. Future tiers beyond 11 require levels above 100 and
remain inaccessible under the current skill cap.

## Armor and accessories

The catalog classifies helmets, bodies, legs, shields, capes, rings, and
necklaces as Armor; these all use Defense. Body armor slots and shields also
use Defense when supplied by a future custom item definition. Quiver contents
and ammunition are unrestricted. Non-equippable crafting and food items have
no equipment requirement.

## Runtime enforcement and UI

`EquipmentProgression` owns requirement calculation and descriptions.
`InventorySystem.equip_item()` rejects an unmet requirement before removing
items, replacing equipped gear, emptying a shield slot for a two-handed weapon,
or moving quiver/ring stacks. `PlayerState.equip_item()` and `give_and_equip()`
use this same entry point.

The journal shows required and current skill levels, disables locked Equip
actions, and exposes current/next tier in the Attack and Defense skill cards.
F6 grants an item to the backpack, attempts to equip it through the same rules,
and displays the actual result. Locked grants remain in the backpack. F7's
visual preview remains a separate art tool rather than a player equipment grant.

Requirements are checked when equipping. Skills normally only increase; a
manual practice-level reduction does not remove already worn equipment.

The XP curve's initial 80-hour melee calibration and its assumptions are
documented in [ExperienceRates.md](ExperienceRates.md).
