# Runite Equipment — Tier 7

**Date:** 2026-10-18. **Status:** All 17 equipment definitions and the user-approved armor stacking revision are implemented and verified.

The user requested restoration of the complete material tier above Adamantite, with noticeably stronger weapons, accuracy, and armor without a large power spike. No older Runite definition was found in the local active catalog, archived Python, or synced references. These definitions were rebuilt from the existing Blacksteel/Mithril/Adamantite progression. Active item definitions are in `data/items.json`.

## Implemented rules

- Material Runite; equipment tier 7, immediately above Adamantite tier 6.
- One counterpart for each of the 17 Adamantite equipment items. Existing item IDs and definitions are preserved; new IDs are 180–196.
- Weapons have approximately 18–20% higher main attack bonuses. Weapon speeds, styles, two-handed handling, range, and projectile class follow the existing counterpart.
- Each weapon has a +0.02 flat accuracy bonus in addition to its stronger style bonus. This adds two percentage points before the existing 0.99 accuracy cap and enemy defense calculation.
- Armor continues the recent per-tier increments in each defensive style, with smaller magic penalties. Jewelry continues the prior attack and accuracy increments.
- Intrinsic item rarity remains `common`, following the current standard-equipment catalog convention. This field is independent of drop-pool placement: the Titan's proposed Runite rare drop is still a rare-pool reward. Intrinsic rarity labels across standard tiers remain a separate review.
- Existing equipment slots and automatic catalog loading make these available in F6 and normal inventory code. The current progression policy requires Attack 60 for Runite weapons and Defense 60 for Runite Armor items. Prices, set effects, and drop odds remain separate design work. See [Equipment Progression](EquipmentProgression.md).

## Weapons and actual combat results

The following damage ranges are runtime results at offensive/power skill 100 with only that weapon equipped, no jewelry, and its primary attack style. Accuracy is before enemy resistance. Critical hits retain the game's current damage cap.

| ID | Runite weapon | Attack bonuses | Speed rating | Adamantite damage → Runite damage | Adamantite accuracy → Runite accuracy |
|---|---|---|---:|---|---|
| 180 | Dagger | stab 43; slash 22 | 3 | 4–42 → 5–45 | 0.844 → 0.872 |
| 181 | Shortsword | slash 50; stab 25 | 4 | 5–44 → 6–48 | 0.851 → 0.880 |
| 182 | Longsword | slash 66; stab 33 | 5 | 7–50 → 8–54 | 0.866 → 0.895 |
| 183 | Mace | blunt 76; slash 20; stab 15 | 6 | 8–54 → 9–59 | 0.874 → 0.903 |
| 184 | Warmaul | blunt 154 | 8 | 16–81 → 19–91 | 0.913 → 0.942 |
| 185 | Bow | ranged 55 | 4 | 5–46 → 6–50 | 0.856 → 0.885 |
| 186 | Crossbow | ranged 66 | 4 | 7–50 → 8–54 | 0.866 → 0.895 |
| 187 | Magic Staff | magic 53 | 5 | 5–45 → 6–49 | 0.854 → 0.883 |
| 188 | Magic Wand | magic 69 | 3 | 7–51 → 8–56 | 0.868 → 0.898 |

At skill 50 the weapon-only Warmaul range improves from 8–43 to 10–49, and Longsword from 3–27 to 4–29. These are sustained weapon-stat improvements, with existing attack cadence preserved. Explicit spell damage uses the spell's damage definition and Magic level; staff/wand bonuses improve automatic magic attacks and spell accuracy, while explicit spell damage caps retain their current behavior.

## Armor and accessories

Defense entries below are item stat contributions, not final damage-reduction percentages. Current combat uses resistance to reduce hit chance.

| ID | Item | Slash | Stab | Blunt | Magic | Ranged |
|---|---|---:|---:|---:|---:|---:|
| 189 | Runite Helmet | 0.410 | 0.380 | 0.400 | -0.007 | 0.370 |
| 190 | Runite Platebody | 0.490 | 0.430 | 0.470 | -0.021 | 0.420 |
| 191 | Runite Platelegs | 0.445 | 0.405 | 0.435 | -0.014 | 0.380 |
| 192 | Runite Kiteshield | 0.500 | 0.450 | 0.540 | -0.024 | 0.430 |
| 193 | Runite Square Shield | 0.460 | 0.430 | 0.520 | -0.021 | 0.400 |
| 194 | Runite Cape | 0.180 | 0.180 | 0.180 | 0.000 | 0.180 |

| ID | Item | Attack bonus to each style | Flat accuracy bonus |
|---|---|---:|---:|
| 195 | Runite Ring | 24 | 0.12 |
| 196 | Runite Necklace | 26 | 0.14 |

Warmaul, Bow, and Magic Staff retain the two-handed rules and return an equipped shield to the backpack. All 17 items use actual equipped inventory entries and can be equipped through the normal slot logic.

## Implemented armor stacking

The user approved revising armor stacking so Runite provides a real full-set upgrade. Equipment defense entries now sum as raw ratings without an intermediate cap. Defense skill adds up to 0.25 physical rating; Magic skill adds up to 0.25 magic rating. Convert the combined rating once, independently for each attack style:

```text
resistance = clamp(rating / (1 + abs(rating)), -0.50, 0.80)
incoming player hit chance = clamp(attacker accuracy * (1 - resistance), 0.05, 0.99)
```

This curve gives diminishing returns while preserving upgrades. Negative ratings remain vulnerabilities. Armor changes the frequency of landed hits, not damage per landed hit. Authored NPC resistances retain their existing flat accuracy subtraction; an explicit player armor flag follows stats into combat actors, equipment refresh, serialization, and actual collision targets.

Full helmet/body/legs/kiteshield/cape at Defense 100, against slash attacks with enemy accuracy 0.30:

| Material | Slash resistance | Incoming hit chance |
|---|---:|---:|
| Bronze | 38.27% | 18.52% |
| Iron | 47.78% | 15.67% |
| Steel | 51.34% | 14.60% |
| Blacksteel | 54.44% | 13.67% |
| Mithril | 59.92% | 12.02% |
| Adamantite | 65.34% | 10.40% |
| Runite | 69.47% | 9.16% |

Runite receives about 11.9% fewer slash hits than Adamantite in this comparison. Each individual Runite armor upgrade also improves a full Adamantite loadout. The 80% resistance ceiling begins at rating 4; the standard full Runite slash rating including max Defense is 2.275. The 5% minimum and 99% maximum hit chance still apply, so sufficiently weak attacks or strong attacks against vulnerabilities can reach the same bound.

**Balance effect:** This changes player durability across existing tiers. Previously, flat subtraction pushed many incoming attacks down to the same 5% hit floor. Those enemies can now hit armored players more often, with a meaningful difference between material tiers. Enemy damage, attack cadence, and authored defenses are unchanged. Encounter difficulty and supply per hour still need playtesting before finalizing golem loot.

## Remaining caps and open decisions

Full high-tier jewelry can also reach the existing 0.99 accuracy cap. Higher Runite attack and accuracy stats help until that cap; additional weapon damage remains effective even at capped accuracy. No accuracy cap bypass or armor penetration has been added.

Runite-specific equipment art has not been assigned. Current equipment visuals use their existing fallback when no exact item artwork exists.

## Loot and economy status

Adding these items does not approve Titan or other monster drop percentages. Existing monsters currently stop at runtime monster tier 5; current generic loot therefore does not roll tier 7. Future generic tier-7/8 monsters would make these items eligible under the existing generic rules, so their individual tables should be reviewed before enabling such sources.

The Titan's proposed regular Adamantite and rare Runite equipment is tracked in [Golem Loot Review](GolemLootReview.md). NPC prices, crafting recipes, and drop quantities/chances still require explicit review.

## Verification

Godot 4.5.1 imported the project successfully. The normal-autoload integration scene `scenes/dev_tools/runite_equipment_smoke.tscn` passed 4,077 checks covering unique IDs/names, all 17 real equip operations, weapon damage/accuracy at skills 50 and 100, preserved cadence/range/projectile profiles, real combat rolls above Adamantite maxima, jewelry, and two-handed restrictions. Armor checks cover all seven tiers at skills 1/50/100, both shields and no shield, individual upgrades/removal, skill contributions, vulnerabilities, hit bounds, NPC compatibility, elemental projectile target selection, and actual game-scene actor creation/refresh.

Paired combat samples used the same random seeds for each set: at enemy accuracy 0.30, Adamantite took 1,033 hits and Runite 907 out of 10,000 attacks; at accuracy 0.90, 3,130 versus 2,744. Normal project headless startup also exited successfully with no script errors. These checks confirm code behavior; visual gameplay feel and encounter balance still need manual playtesting.

Run the check with Godot in headless mode, passing the project path and `res://scenes/dev_tools/runite_equipment_smoke.tscn` as the scene. The source is `scripts/dev_tools/runite_equipment_smoke.gd`.
