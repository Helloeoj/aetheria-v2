# Golem Loot Review

**Combat update, 2026-10-19:** The golem ladder 45/75/110/145/180 and shared
skill-derived combat stats are now implemented. Golems absorb 60% slash/stab
and 20% crush damage after a hit lands. The combat figures and pending-combat
notes in this older loot review are superseded by [Melee Scaling](MeleeScaling.md).
This update does not implement or approve the proposed loot probabilities.

**Date:** 2026-10-18. **Status:** Crystalcore removal and the user's requested complete Runite Tier 7 equipment restoration are implemented. Proposed golem intermediate levels, combat stats, and loot odds remain unapproved and unimplemented. Earlier loot odds below are superseded design history.

This is developer-facing documentation. Implemented changes are the user-requested Crystalcore roster removal, including its sprite catalog mapping/definition, and restoration of all 17 Runite equipment counterparts. Existing asset files remain available. Golem loot tables and monster levels/stats are still in design. The master decision record is [Loot Economy Review](LootEconomyReview.md).

## Direction and scope

The user wants golems to provide worthwhile equipment drops, specifically warmauls. The family begins in mid-game and extends into endgame under the requested level range. Keep unique guaranteed/common/rare pools, explicit item rarity and chance, common misses, and the rule that one monster must not supply an entire T4+ armor set.

**User-directed corrections:** Blacksteel T4 is the general minimum for golem equipment. Apply that floor to proposed tiered material drops too, pending clarification; remove Iron/Steel fallback drops from the current plan. Golem Crystalcore is removed from the game. The exceptionally difficult Titan should offer Adamantite as an ordinary-pool reward, with Runite as its rare reward. This instruction replaces the earlier proposal that made Adamantite the Titan's rare jackpot.

**User-directed progression:** golems start around level 45 and culminate in a level-180 Titan; the player maximum overall combat level is 150. With five remaining golems, the revised intermediate levels below are proposals: a 30-level first step, followed by 35-level steps. Removing Crystalcore does not transfer its loot automatically to another monster.

| Rank | Monster | Existing level | Proposed level | Ordinary/common-pool warmaul direction | Rare-pool warmaul direction |
|---|---|---:|---:|---|---|
| 1 | Golem Shardling | 15 | 45 | Blacksteel T4 | Pending individual review |
| 2 | Golem Boulderkin | 30 | 75 | Blacksteel T4 | Mithril T5 |
| 3 | Golem Stoneguard | 45 | 110 | Mithril T5 | Adamantite T6 |
| 4 | Golem Runeshell | 60 | 145 | Mithril T5 | Adamantite T6 |
| 5 | Golem Titan | 90 | 180 | Adamantite T6 | Runite T7; Warmaul ID 184 |

The user specified the level boundaries, Blacksteel floor, Crystalcore removal, and Titan's Adamantite/Runite pool distinction. The intermediate levels and other weapon assignments are proposals. Ordinary/common-pool means an individually weighted result; it does not mean guaranteed gear on every kill. No item is guaranteed merely because it appears in this overview. Proposed warmaul quantity is one per selected result, subject to individual review.

Start individual loot review with Shardling. Rates must make regular rewards meaningful for encounter effort, rather than making equipment effectively rare while merely changing its pool label. Preserve overall T5+ scarcity through appropriate encounter difficulty, access, and measured supply/hour. The Titan's ordinary-pool Adamantite is an explicit encounter-specific exception to reserving high-tier equipment for a rare pool.

### Runite equipment — catalog restoration complete

The user subsequently requested reintegration of the complete tier above Adamantite. `data/items.json` now includes 17 Runite Tier 7 items, IDs 180–196, matching every Adamantite weapon, armor, shield, cape, ring, and necklace. Runite Warmaul is ID 184, with blunt bonus 154 and weapon accuracy bonus 0.02. See [Runite Equipment](RuniteEquipment.md) for every stat, slot, and runtime comparison.

Intrinsic catalog rarity follows the existing standard-equipment convention, `common`; this is separate from the Titan's proposed rare-pool placement. Runite item definitions are now usable by the game, but monster drop probabilities, equipment requirements, and NPC prices remain separate review points. The user-approved diminishing-return armor stacking revision is implemented; full Runite now provides better protection than full Adamantite. No golem drop odds were implemented as part of the item restoration.

### Combat and economy implications

- Monster `level` currently does not scale HP, damage, accuracy, defenses, or XP automatically. `MonsterState` copies those explicit stats from the template and omits level from its combat-stat payload. The new level ladder needs individually reviewed combat profiles before its loot can be balanced. Increasing HP also increases damage-based combat XP per kill under current rules.
- Player combat level is derived from Attack, Strength, Defense, Range, and Magic with equal weight, starting at 1 and reaching 150 only when all five skills reach 100. Health is excluded; individual skills retain their level 100 caps. See [Skill Progression](SkillProgression.md) for the implemented formula.
- Titan is 30 combat levels above the player maximum. Solo difficulty, grouping, and special mechanics remain design questions; an above-cap monster label does not by itself establish a group-only encounter.
- Golem rank is separate from runtime `tier` and equipment tier. Titan remains runtime monster tier 5. Do not assign a new monster tier merely because its proposed rare weapon may be equipment T7: monster tier also controls generic loot and guaranteed gold.
- The old Stoneguard-45/Runeshell-60 rewards and odds are not recommendations for Stoneguard-110/Runeshell-145. Their Iron/Steel fallback drops also conflict with the new Blacksteel floor. Retain them only as earlier design history; rebuild rates against approved difficulty, expected kill times, and competing goblin supply.

## Existing Godot data

Monster records are in `data/monsters.json`. These are existing values, not proposed stat changes.

| Monster | ID | Level | Monster tier | HP | Blunt damage | Current guaranteed gold range / mean |
|---|---:|---:|---:|---:|---|---|
| Golem Shardling | 1024 | 15 | 1 | 140 | 9–15 | 3–10 / 6.5 |
| Golem Boulderkin | 1025 | 30 | 2 | 180 | 17–23 | 5–18 / 11.5 |
| Golem Stoneguard | 1026 | 45 | 3 | 220 | 24–30 | 10–28 / 19 |
| Golem Runeshell | 1027 | 60 | 4 | 260 | 32–38 | 18–40 / 29 |
| Golem Titan | 1029 | 90 | 5 | 340 | 47–53 | 25–60 / 42.5 |

All five currently have 0.30 accuracy, 2-tile melee range, and a three-tick attack interval. Each has the same resistance values: slash 0.40, stab 0.40, blunt 0.50, ranged 0.30, magic 0.00. In current combat logic resistance reduces hit accuracy; these numbers are not damage-reduction percentages. Blunt is currently their strongest defense, so a warmaul reward need not be the best weapon for farming its own source.

Removed roster entry: Golem Crystalcore, former monster ID 1028. Its ID is retired and was not reassigned. It is absent from the active monster records and sprite catalog; original asset files were not deleted.

`data/loot.json` contains no golem family tables. `scripts/loot_system.gd` therefore uses generic loot for golems if instantiated. Gold is separately guaranteed by monster tier. `scripts/game_data.gd` currently exposes only goblins in the developer spawn list. Enabling golems or replacing generic loot is an implementation step after approval.

Existing warmauls in `data/items.json`:

| Item | ID | Equipment tier | Catalog item rarity | Blunt bonus |
|---|---:|---:|---|---:|
| Bronze Warmaul | 5 | 1 | common | 30 |
| Iron Warmaul | 27 | 2 | common | 44 |
| Steel Warmaul | 48 | 3 | common | 67 |
| Blacksteel Warmaul | 57 | 4 | common | 83 |
| Mithril Warmaul | 77 | 5 | common | 110 |
| Adamantite Warmaul | 98 | 6 | common | 130 |

Warmauls are two-handed and blunt-only. All have speed rating 8. The current player attack multiplier makes their interval 3.6 seconds; do not use older timing assumptions to estimate farming rates. Catalog rarity remains `common` even for an item placed in a rare loot pool. Intrinsic rarity labels are still an unresolved catalog review, independent of these chances.

## Superseded loot draft — retained for audit only

Everything from the two historical monster tables through their acquisition and economic calculations below belongs to the old level-45 Stoneguard/level-60 Runeshell assumption. No such rates were approved or implemented. These tables must not be copied into live data or treated as balanced for the revised level ladder.

### Historical Stoneguard — old level 45 assumption

Role: an accessible mid-game source of T4 Blacksteel warmauls, with T3 equipment as lower-value fallback and ingots to support crafting. Its T3 monster tier does not automatically cap equipment at T3; this proposal is based on its level, damage, and defenses. Keep its existing gold payout pending economy review.

**Guaranteed items:** none proposed. The catalog has no stone, golem core, or bone item; no new item is assumed. Numeric gold remains 100%, 10–28 per kill under current code.

**Common:** two independent attempts per kill. Each attempt selects exactly one row. Quantities are uniformly rolled inclusive ranges, or one item where shown. Common outcomes sum to 100% per attempt. None of these item drops is guaranteed.

| Common outcome | Catalog rarity | Chance per attempt | Quantity per result | Chance of at least one result per kill |
|---|---|---:|---|---:|
| Nothing | — | 50% | 0 | — |
| Iron Ingot | common | 20% | 2–4 | 36% |
| Blacksteel Ingot | common | 20% | 1–2 | 36% |
| Steel Warmaul | common | 6% | 1 | 11.64% |
| Steel Square Shield | common | 4% | 1 | 7.84% |
| **Total** | | **100%** | | |

**Rare access:** one separate 4% roll per kill. On access, select exactly one outcome below. Selection chances sum to 100%. Rare drops are additional to common drops.

| Rare outcome | Catalog rarity | Chance within rare pool | Effective chance per kill | Quantity | Guaranteed? |
|---|---|---:|---:|---:|---|
| Blacksteel Warmaul | common | 50% | 2% (1/50) | 1 | No |
| Blacksteel Helmet | common | 50% | 2% (1/50) | 1 | No |
| **Total on access** | | **100%** | **4% any rare item** | | |

The single T4 armor slot avoids making Stoneguard a full-set farm. Two 50% common misses give a 25% chance of no common item; including the separate rare roll, 24% of kills yield no item. Those kills still pay gold.

### Historical Runeshell — old level 60 assumption

Role: a stronger Blacksteel warmaul source with a scarce T5 Mithril warmaul upgrade. Keep T6 Adamantite out of this initial mid-game pair. No T6 source or rate is approved for other golems yet.

**Guaranteed items:** none proposed. Numeric gold remains 100%, 18–40 per kill under current code.

**Common:** two independent attempts per kill, with the same one-outcome rule. All listed items exist in the catalog; none is guaranteed.

| Common outcome | Catalog rarity | Chance per attempt | Quantity per result | Chance of at least one result per kill |
|---|---|---:|---|---:|
| Nothing | — | 55% | 0 | — |
| Blacksteel Ingot | common | 30% | 1–3 | 51% |
| Iron Ingot | common | 5% | 3–5 | 9.75% |
| Steel Warmaul | common | 8% | 1 | 15.36% |
| Steel Kiteshield | common | 2% | 1 | 3.96% |
| **Total** | | **100%** | | |

**Rare access:** one separate 4% roll per kill. On access, choose one outcome:

| Rare outcome | Catalog rarity | Chance within rare pool | Effective chance per kill | Quantity | Guaranteed? |
|---|---|---:|---:|---:|---|
| Blacksteel Warmaul | common | 75% | 3% (1/33.3) | 1 | No |
| Blacksteel Platelegs | common | 20% | 0.8% (1/125) | 1 | No |
| Mithril Warmaul | common | 5% | 0.2% (1/500) | 1 | No |
| **Total on access** | | **100%** | **4% any rare item** | | |

Runeshell supplies a different T4 armor slot from Stoneguard, and neither drops a full set. The T5 warmaul is fifteen times less frequent than its T4 warmaul. Two 55% common misses give 30.25% no-common-item kills; including rare access, 29.04% of kills yield no item, with gold still paid.

### Historical acquisition and supply calculations

For a per-attempt outcome probability `p` over `n` common attempts, chance of at least one result is `1 - (1-p)^n`; expected units are `n * p * mean_quantity`. These differ when duplicate common results can occur. A separate rare outcome has `P = rare_access * within_pool_probability`.

| Desired item/source | Chance per kill | Mean kills until first drop | Kills giving at least 90% chance of one or more |
|---|---:|---:|---:|
| Stoneguard Blacksteel Warmaul | 2% | 50 | 114 |
| Stoneguard Blacksteel Helmet | 2% | 50 | 114 |
| Runeshell Blacksteel Warmaul | 3% | 33.3 | 76 |
| Runeshell Blacksteel Platelegs | 0.8% | 125 | 287 |
| Runeshell Mithril Warmaul | 0.2% | 500 | 1,151 |

These are RNG estimates, not guarantees, timers, or pity mechanics. At 500 Runeshell kills, the chance of at least one Mithril Warmaul is about 63.25%; roughly 36.75% of players would still have none. Hours cannot be estimated without observed kill and respawn rates.

Expected production per kill, including stack quantity:

| Item | Stoneguard | Runeshell |
|---|---:|---:|
| Gold | 19 | 29 |
| Iron Ingot | 1.20 | 0.40 |
| Blacksteel Ingot | 0.60 | 1.20 |
| Steel Warmaul | 0.12 | 0.16 |
| Steel Square Shield | 0.08 | 0 |
| Steel Kiteshield | 0 | 0.04 |
| Blacksteel Warmaul | 0.02 | 0.03 |
| Blacksteel Helmet | 0.02 | 0 |
| Blacksteel Platelegs | 0 | 0.008 |
| Mithril Warmaul | 0 | 0.002 |

Existing competing supplies are unchanged: Goblin Warrior produces 0.04 Steel Warmauls per kill; Chieftain produces 0.045 Steel Warmauls and 0.015 Blacksteel Warmauls per kill. A Stoneguard must be killable at at least 75% of Chieftain's kills/hour to match Blacksteel warmaul supply/hour. Runeshell needs at least 50% of Chieftain's kills/hour. Runeshell needs at least two-thirds of Stoneguard's kills/hour to match that source. Do not approve golems as the most efficient warmaul farm without measuring these comparisons.

No active NPC buy/sell prices or player trade prices exist. Let `S(item)` mean the NPC's buy price paid to the player. Proposed NPC liquidation EVs, excluding combat costs, are:

- Stoneguard: `19 + 1.20*S(Iron Ingot) + 0.60*S(Blacksteel Ingot) + 0.12*S(Steel Warmaul) + 0.08*S(Steel Square Shield) + 0.02*S(Blacksteel Warmaul) + 0.02*S(Blacksteel Helmet)`.
- Runeshell: `29 + 0.40*S(Iron Ingot) + 1.20*S(Blacksteel Ingot) + 0.16*S(Steel Warmaul) + 0.04*S(Steel Kiteshield) + 0.03*S(Blacksteel Warmaul) + 0.008*S(Blacksteel Platelegs) + 0.002*S(Mithril Warmaul)`.

Net profit must subtract supplies and other actual costs. Direct player-trade valuation uses expected sale proceeds rather than NPC prices and depends on demand, negotiation, and finding a buyer. No central trade hub is assumed. Higher demand does not guarantee a particular price or sale volume.

No equipment wear/removal mechanism or equipment level requirements were found in active equipping logic. Durable warmauls can accumulate over time. The proposed Blacksteel supply and especially the T5 rate should be reviewed alongside future item sinks, crafting supply, and demand; low drop chance alone does not ensure a lasting market.

## Assumptions and unresolved decisions

1. User-directed endpoints are around 45 through Titan 180, with player overall combat capped at 150. Confirm the revised five-golem intermediate levels 75/110/145 and review actual combat stats from Shardling upward against the implemented player progression in [Skill Progression](SkillProgression.md).
2. Confirm metal ingots as suitable salvage from these constructs. This is a proposed theme, not established golem lore. No stone/core material exists to substitute automatically; there is also no T3 crafting material.
3. Rebuild individual drops and probabilities after the revised difficulty profiles. The historical 2%/3% Blacksteel and 0.2% Mithril rates above are superseded, not pending approval at the new levels.
4. Review all five remaining golems individually with equipment no lower than Blacksteel. Confirm ordinary-pool rates versus rare-pool rates, especially the Titan's regular Adamantite and rare Runite. Runite Tier 7 items are now defined; their golem drop odds are not.
5. Blacksteel/Mithril/Adamantite/Runite warmauls have intrinsic item rarity `common` in the current catalog. Pool placement and probabilities remain separate decisions. Full-set armor stacking has been revised with user approval and verified across all seven material tiers; see [Runite Equipment](RuniteEquipment.md).
6. Need measured player loadouts, kill times, respawns, supply costs, NPC buy/sell prices, item sinks, and trade demand to finish economic evaluation. Existing identical golem defenses and their actual player challenge need play evaluation; no stat edits are proposed here.

## Decision log

| Date | Decision or finding | State |
|---|---|---|
| 2026-10-18 | Golems should give worthwhile gear and specifically warmauls | User direction recorded |
| 2026-10-18 | Six existing golems and six catalog warmauls inspected; no golem-specific live table exists | Inspection complete |
| 2026-10-18 | Initial Stoneguard-45/Runeshell-60 tables and odds | Superseded by new level scope; never approved or implemented |
| 2026-10-18 | Golems start around 45, increase across ranks, Titan reaches 180; player maximum overall combat level 150 | Golem changes pending; player combat level implemented |
| 2026-10-18 | Rounded golem ladder 45/70/95/120/150/180 and T3–T6 warmaul direction | Proposed; stats and drop rates still to review |
| 2026-10-18 | Earlier six-rank ladder and Steel/Adamantite-jackpot reward direction | Superseded by the following user corrections |
| 2026-10-18 | Blacksteel is the general minimum golem gear; Titan Adamantite is ordinary loot and Runite is its rare reward | User direction recorded; loot implementation pending |
| 2026-10-18 | Remove Golem Crystalcore from the game | Applied to monster and sprite registries; assets retained |
| 2026-10-18 | Five-golem ladder 45/75/110/145/180 and Runite Warmaul as proposed equipment T7 | New proposal; intermediate levels, item stats, and odds unapproved |
| 2026-10-18 | User requests complete Runite tier above Adamantite, with stronger damage/accuracy/defense and controlled scaling | 17 Tier 7 equipment items implemented and integration-checked; armor stacking subsequently approved and revised |

| 2026-10-18 | User approves revising armor stacking so Runite upgrades work fully | Implemented raw rating aggregation, diminishing returns, and fractional incoming player hit chance; 4,077 integration checks pass, including actual scene actor refresh. See RuniteEquipment.md for balance effects. |
