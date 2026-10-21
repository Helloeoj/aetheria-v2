# Aetheria Loot and Economy Review

**Status:** Working master record. All five approved goblin loot tables and the requested goblin roster corrections are applied in Godot. Golem review began on 2026-10-18. Crystalcore removal is applied; the revised five-golem levels, stats, and loot remain in design. User direction now sets Blacksteel as the golem equipment floor, Titan Adamantite as ordinary loot, and Runite as its rare prize. The initial golem drop odds were superseded and were never applied. Later monsters and economy tuning will be handled in manageable sections.

**Purpose:** Developer-facing design notes. Drop probabilities, expected value, acquisition-time estimates, and economy assumptions here are for balancing and planning; they are not runtime inputs the game needs to read. The game uses the approved loot tables in `data/loot.json`.

**Food update (2026-10-19):** The seven placeholder foods and their common-loot entries were removed at the user's request, moving their weights into `Nothing` without changing other items' odds. Ten selected river fish now have catch, healing, and baseline price data. They are excluded from generic monster loot. Shops are not implemented. See [River fish balance](FoodFishingBalance.md) for current values and limitations.

## Agreed rules

- Every monster has its own guaranteed, common, and rare tables.
- Guaranteed entries have a 100% chance. Bones are the usual creature drop, with explicit exceptions such as feathers or one-time quest items. The item catalog currently has no bone item, so no bone drops are assigned yet.
- Common rolls choose one listed item or `Nothing`; the listed outcome chances sum to 100% for each attempt. Tougher monsters may receive multiple attempts, each of which can miss.
- The rare table has a separate, very low access chance per kill. If accessed, one outcome is selected from that monster's rare pool; its selection chances sum to 100%. A rare result can occur alongside common and guaranteed results.
- Item rarity, drop-table category, and probability are separate fields/concepts. A catalog item marked `common` can still be an outcome in a monster's rare table.
- Tier 1–2 should support quick early progress. Tier 3 should take more effort and require suitable gear. Tier 4 is a meaningful grind but not an extreme one. Tier 5–6 gear is much scarcer; the strongest items should be exceptional achievements.
- Encounter-specific golem direction: Blacksteel T4 is the minimum equipment drop. The exceptional level-180 Titan has Adamantite in its ordinary/common pool and Runite in its rare pool. Ordinary pool placement is separate from intrinsic rarity and does not mean a guaranteed item. Evaluate difficulty, access, and supply/hour alongside per-kill chance to preserve higher-tier scarcity.
- Goblin equipment should top out around Tier 3 in ordinary drops. Tier 4 may appear as a deliberate rare reward from suitable goblins; goblins should not drop Tier 5–6 equipment.
- At Tier 4 and above, a single creature should not drop a complete armor set. Players should explore and fight different creatures to assemble stronger sets.
- Review expected value per kill, acquisition time, NPC prices, and player-trade supply. Aetheria has NPC buying/selling and direct player trades, with no central trade hub.
- User gold-value anchors: 100,000 gold is substantial; a full Bronze loadout is worth roughly 2,500 gold and an equivalent Runite loadout roughly 300,000. Both include armor, one weapon, cape, two rings, and necklace. These establish the scale without assigning individual equipment prices. Sunfish's explicit NPC prices are 800 gold paid by the player / 350 gold received by the player; other fish now scale toward that anchor. See [River fish balance](FoodFishingBalance.md).

## Catalog and economy constraints

- `data/items.json` now has 204 catalog items after removing seven placeholder foods and adding six fishing supplies and ten river fish, including all 17 restored Runite Tier 7 equipment counterparts (IDs 180–196). Standard equipment through Tier 7 is currently labeled item rarity `common`; the 60 Tier 10 artifacts are labeled `artifact`. Fish tiers order fish progression rather than equipment material. [Runite Equipment](RuniteEquipment.md) records the implemented stats, comparisons, and the approved diminishing-return armor rules.
- Steel armor and accessories are now represented as Tier 3 catalog items, alongside existing Tier 3 Steel weapons. Their defense and accessory bonuses were set to the midpoint between the existing Iron Tier 2 and Blacksteel Tier 4 values. This is an explicit balancing assumption for later review.
- The catalog has bows and `Arrow Shafts`, but no usable Arrow/Arrows or Bolt/Bolts item. Godot has quiver/ammunition-slot scaffolding, but no ammunition item or combat ammunition use was found.
- There is no bone item or coin item in the catalog. Monster gold is stored as a separate numeric range.
- The ten fish have baseline NPC `sell_value` and `buy_price` metadata. Other item prices, actual NPC transactions, spawn rates, and kills-per-hour remain undefined, so complete item-value EV and gold inflation cannot yet be calculated.
- The family gold ranges in `data/loot.json` are not the active roll in `scripts/loot_system.gd`; the current roller uses `GOLD_TABLE` by monster tier. Current tier ranges are T1 3–10, T2 5–18, T3 10–28, T4 18–40, and T5 25–60. This means the old family gold ranges for Worker, Warrior, Shaman, and Chieftain are not live runtime values.
- `main.gd` calls `LootSystem.roll_monster_loot()`. That dispatcher uses the named monster's explicit guaranteed, common, and rare tables when present, and falls back to generic loot only when no explicit table exists. Each common attempt selects one weighted outcome, including `Nothing`; rare-table access is rolled separately, then one weighted rare outcome is selected. The original `roll_loot()` remains as a compatibility alias.
- Gold still uses the existing active `GOLD_TABLE` by monster tier. Family-specific gold ranges in `loot.json` are retained as reference data but are not applied by the current roller.

## Roster and applied decisions

| Goblin | Current review role | Monster record | Drop table status |
|---|---|---|---|
| Scout | Level 5, Tier 1, ranged-only bow user | Updated to ranged; 18 range and 2.5 projectile speed copied from the removed Ranger profile. Level, damage, and accuracy remain at the Scout's former values. | Approved Scout table applied; review record below |
| Worker | Level 10, Tier 2, melee | Existing record retained | Approved table applied |
| Warrior | Level 15, Tier 3, melee | Existing record retained | Table updated to include the Tier 3 Steel core armor set; its new piece rates are balancing assumptions |
| Shaman | Level 25, Tier 5, magic | Renamed from Goblin Mage | Approved table applied |
| Chieftain | Level 30, Tier 5, hybrid | Existing record retained | Approved table applied |

Goblin Ranger was removed from the active monster and goblin-loot records as directed. The old Python source remains archived and untouched.

## Goblin Scout — approved and applied

The common pool has one attempt per kill. Every listed item currently exists in the catalog and is item rarity `common`. The five core bronze armor pieces each have a 5.7% chance per Scout kill. For five distinct pieces with equal per-kill probability `p`, expected collection time is `(1 + 1/2 + 1/3 + 1/4 + 1/5) / p`; at `p = 0.057`, this is about 40.1 kills.

| Pool/outcome | Item rarity | Chance | Quantity |
|---|---|---:|---:|
| Guaranteed | — | no item; bone absent from catalog | — |
| Common: Nothing | — | 26% | — |
| Common: Feathers | common | 8% | 3–8 |
| Common: Arrow Shafts | common | 8% | 4–10 |
| Common: Bowstring | common | 5% | 1–3 |
| Common: Bronze Dagger | common | 8% | 1 |
| Common: Iron Dagger | common | 4% | 1 |
| Common: Iron Longsword | common | 3% | 1 |
| Common: Bronze Bow | common | 6% | 1 |
| Common: Iron Bow | common | 3.5% | 1 |
| Common: Bronze Helmet | common | 5.7% | 1 |
| Common: Bronze Platebody | common | 5.7% | 1 |
| Common: Bronze Platelegs | common | 5.7% | 1 |
| Common: Bronze Square Shield | common | 5.7% | 1 |
| Common: Bronze Cape | common | 5.7% | 1 |
| Rare | — | 0% | no suitable reward identified |

**Set assumption:** the core armor set is helmet, platebody, platelegs, one shield, and cape. Ring and necklace are separate accessories. Gold is a separate numeric payout; the current Scout family range is 3–10, with midpoint EV 6.5 if uniform. No shop value is available.

## Remaining goblins — approved and applied

All proposed drops below are already present in `data/items.json`. Every such item is currently labeled item rarity `common`; pool placement and probabilities are independent from that label. Quantity ranges are explicit. No bone item is assigned because the item catalog has none.

### Goblin Worker — Level 10, Tier 2

One common attempt per kill. Five iron core armor pieces each have 7.6% per roll, for an expected full-set collection time of about 30 kills. No rare item is assigned.

| Common outcome | Chance per attempt | Quantity |
|---|---:|---:|
| Nothing | 33% | — |
| Iron Helmet | 7.6% | 1 |
| Iron Platebody | 7.6% | 1 |
| Iron Platelegs | 7.6% | 1 |
| Iron Square Shield | 7.6% | 1 |
| Iron Cape | 7.6% | 1 |
| Iron Shortsword | 8% | 1 |
| Iron Ingot | 11% | 1–2 |
| Ripped Cloth | 10% | 1–3 |
| **Total** | **100%** | |

Guaranteed: no item currently available. Rare table: no reward assigned. Existing family gold range is 10–25, but active tier-based gold range is 5–18.

### Goblin Warrior — Level 15, Tier 3

Two common attempts per kill. Each attempt has a 60% `Nothing` outcome, so the chance of receiving no common items from either attempt is 36%. Steel is Tier 3. The common table includes the full five-piece Steel core set, with each piece at 2% per attempt. This rate is a balancing assumption intended to put expected full-set completion at about 57.7 kills; each individual piece has a 3.96% chance per kill.

| Common outcome per attempt | Chance | Quantity |
|---|---:|---:|
| Nothing | 60% | — |
| Steel Helmet | 2% | 1 |
| Steel Platebody | 2% | 1 |
| Steel Platelegs | 2% | 1 |
| Steel Square Shield | 2% | 1 |
| Steel Cape | 2% | 1 |
| Steel Dagger | 4% | 1 |
| Steel Shortsword | 4% | 1 |
| Steel Longsword | 3% | 1 |
| Steel Mace | 2% | 1 |
| Steel Warmaul | 2% | 1 |
| Iron Ingot | 7% | 1–2 |
| Ripped Cloth | 8% | 1–3 |
| **Total** | **100%** | |

Guaranteed: no item currently available. Rare table: no reward assigned. Existing family gold range is 25–60; active tier-based gold range is 10–28. **Unresolved catalog gap:** Tier 3 crafting materials are missing.

### Goblin Shaman — Level 25, Tier 5

The Shaman retains the old Mage's level and magic capability, but goblin equipment is capped at Tier 4. Two common attempts per kill; each has 79% `Nothing`, giving 62.41% chance of no common item at all. Tier 3 magic weapons and Tier 4 crafting items are common-pool outcomes. A separate 3% rare-table access roll selects a Tier 4 magic weapon.

| Common outcome per attempt | Chance | Quantity |
|---|---:|---:|
| Nothing | 79% | — |
| Steel Magic Staff | 6% | 1 |
| Steel Magic Wand | 6% | 1 |
| Blacksteel Ingot | 5% | 1–2 |
| Enchanted Cloth | 4% | 1–2 |
| **Total** | **100%** | |

| Rare-table outcome, on access | Within-table chance | Effective chance per kill |
|---|---:|---:|
| Blacksteel Magic Staff | 50% | 1.5% |
| Blacksteel Magic Wand | 50% | 1.5% |
| **Rare table access** | **3% per kill** | |

Guaranteed: no item currently available. Existing family gold range is 120–220; active tier-based gold range is 25–60.

### Goblin Chieftain — Level 30, Tier 5

Three common attempts per kill. Each has 85% `Nothing`, giving 61.4125% chance of no common item from all three attempts. The common table focuses on Tier 4 crafting and modest Tier 3 weapon drops. The separate 5% rare table contains selected Tier 4 gear, not a complete armor set.

| Common outcome per attempt | Chance | Quantity |
|---|---:|---:|
| Nothing | 85% | — |
| Blacksteel Ingot | 6% | 1–2 |
| Enchanted Cloth | 6% | 1–2 |
| Steel Warmaul | 1.5% | 1 |
| Steel Longsword | 1.5% | 1 |
| **Total** | **100%** | |

| Rare-table outcome, on access | Within-table chance | Effective chance per kill |
|---|---:|---:|
| Blacksteel Platebody | 30% | 1.5% |
| Blacksteel Warmaul | 30% | 1.5% |
| Blacksteel Longsword | 25% | 1.25% |
| Blacksteel Ring | 15% | 0.75% |
| **Rare table access** | **5% per kill** | |

Guaranteed: no item currently available. Existing family gold range is 180–320; active tier-based gold range is 25–60.

## Pacing and economy calculations

These figures follow the current table weights after food removal. Gold averages assume the active tier gold range is uniformly rolled. Goblin item-price value is still unknown because their drops have no NPC prices; the new fish prices do not apply to these tables.

| Goblin | Expected common item results per kill | Rare item results per kill | Average active gold per kill |
|---|---:|---:|---:|
| Scout | 0.74 | 0 | 6.5 |
| Worker | 0.67 | 0 | 11.5 |
| Warrior | 0.80 | 0 | 19 |
| Shaman | 0.42 | 0.03 | 42.5 |
| Chieftain | 0.45 | 0.05 | 42.5 |

- Expected core-set completion is about 40.1 Scout kills for Bronze, 30.0 Worker kills for Iron, and 57.7 Warrior kills for Steel. These are expectation values, so actual completion varies with RNG.
- Each Shaman rare magic weapon has a 1.5% per-kill chance, or 66.7 kills on average for that specific weapon.
- Chieftain rare outcomes have effective per-kill rates of 1.5% for the platebody, 1.5% for the warmaul, 1.25% for the longsword, and 0.75% for the ring. Their expected individual acquisition times are about 66.7, 66.7, 80, and 133.3 kills, respectively.
- The current common and rare odds estimate item supply per kill, but not economic value. NPC buy/sell prices, spawn rates, kill speeds, and player trade activity are still needed to estimate gold inflow, item valuation, and market saturation.

## Golems — initial review, proposals awaiting approval

User direction: golems should provide worthwhile gear, specifically warmauls, with Blacksteel as the general equipment floor. They begin around level 45 and scale to an exceptionally difficult level-180 Titan, above the player's maximum combat level of 150. Crystalcore has been removed from the game. Titan's ordinary reward tier is Adamantite; its rare prize is Runite. The revised five-golem intermediate levels below are proposals. Monster tier, equipment tier, combat level, and individual skill levels remain separate values.

| Monster | ID | Existing level / monster tier | Proposed level | Ordinary/common-pool warmaul direction | Rare-pool warmaul direction |
|---|---:|---|---:|---|---|
| Golem Shardling | 1024 | 15 / T1 | 45 | Blacksteel T4 | Pending individual review |
| Golem Boulderkin | 1025 | 30 / T2 | 75 | Blacksteel T4 | Mithril T5 |
| Golem Stoneguard | 1026 | 45 / T3 | 110 | Mithril T5 | Adamantite T6 |
| Golem Runeshell | 1027 | 60 / T4 | 145 | Mithril T5 | Adamantite T6 |
| Golem Titan | 1029 | 90 / T5 | 180 | Adamantite T6 | Runite T7; Warmaul ID 184 |

The user specified the boundary levels, gear floor, roster removal, and Titan's reward-pool distinction. Middle levels and other weapon assignments are proposals. Level currently does not scale monster combat stats automatically. Player combat level equally weights Attack, Strength, Defense, Range, and Magic, starting at 1 and reaching 150 only when all five reach 100; Health is excluded. See [Skill Progression](SkillProgression.md) for the implemented formula; individual skills retain their level 100 caps. Titan remains runtime monster tier 5; equipment tier does not automatically change monster tier, gold, or generic loot.

Crystalcore (former ID 1028) is removed from `data/monsters.json` and the active sprite catalog. Its ID was not reassigned; asset files are retained. The user-requested Runite Tier 7 restoration is implemented: all 17 equipment counterparts are in `data/items.json`, IDs 180–196, including Warmaul 184. See [Runite Equipment](RuniteEquipment.md) for stats and verified combat improvements. The user-approved armor stacking revision is implemented and verified across all seven material tiers; full Runite now improves protection over full Adamantite. Requirements, prices, and monster drop odds still need review. Blacksteel/Mithril/Adamantite/Runite warmauls are catalog rarity `common`, independently of their assigned loot pools.

No golem-specific loot tables exist in `data/loot.json`; golems currently fall back to the generic roller if instantiated. The developer spawn list currently exposes only goblins. Neither behavior was changed during this design review.

Current progression plan, restored Runite equipment, unresolved stat/economy questions, and superseded historical item-by-item draft: [Golem Loot Review](GolemLootReview.md). Rebuild the loot from Shardling upward against the new difficulty profiles. Earlier Iron/Steel fallback tables and Stoneguard-45/Runeshell-60 odds are design history, not current recommendations or approved runtime data. Existing goblin tables remain the baseline when comparing competing item supply.

## Open review points

- Goblin Scout's 18-tile range and 2.5 projectile speed are copied from the removed Ranger. Confirm or revise these combat values during monster-stat review.
- The catalog lacks a bone item, usable arrows, and Tier 3 crafting materials. No such items are invented here.
- Steel armor's new defense values and accessory bonuses use midpoint interpolation; confirm or rebalance them during item-stat review.
- The Warrior's new 2% per-attempt chance for each Steel core piece is a pacing assumption; confirm or adjust it during the next loot review.
- The current catalog calls standard Tier 1–7 gear `common` item rarity, even when proposed in a rare pool. Revisit intrinsic item-rarity labels separately from drop chances.
- NPC prices, spawn rates, and kills-per-hour are still needed to calculate item EV, player acquisition pace, and likely trade supply.
