# Starforged acquisition — 2026-10-27

Starforged equipment is drop-exclusive. The 17 former recipes (11 enabled,
six planned) are removed. All canonical Starforged items are non-craftable;
live equipment, arrowheads and ammunition are marked drop-only. No IDs, stats,
slots, aliases, Mining probabilities or drop tables/rates changed.

## Enforcement and compatibility

- `scripts/acquisition_rules.gd::can_manufacture()` rejects Starforged material,
  retired records, drop-only items and explicit non-craftable outputs. Shared
  `CraftingService` applies this before any inventory mutation, offline and on
  the authoritative server. Retired ingredients are rejected too. Future salvage
  or reconstruction must call this guard; no salvage implementation exists today.
- Ore **256** and Ingot **257** remain `legacy_placeholder` catalog records,
  with no drop/purchase/mining/manufacturing route. No recipe consumes them.
  Existing stacks remain inert and can still be saved/restored/transferred;
  they are not confiscated or compensated. No save schema or backend migration.
- Smithing lists stop at Adamantite. Both F6 views reject Starforged grants;
  All Items still permits inspecting the complete catalog. Equipment icon
  classification stays intact. Historical Starforged staff/cape aliases resolve
  to **Celestial** items and are not subject to the Starforged-material ban.

## Content decisions still open

Existing equipment drop eligibility and component/ammunition Golem Titan
eligibility remain unchanged. However, there is no explicit live Starforged
loot table, and current monsters top out at tier 5, below tier-7 generic gear.
The documented rare Titan gear route still needs approved implementation/rates.
There is no catalog Starforged pickaxe; its ID/source/rate must be approved.
This change invents none of these. Ore/Ingot are permanently retired, not pending.

The existing bow, crossbow, ring, necklace, arrowhead and ammunition records lack
inventory textures from `ItemVisualLibrary`; this change adds no replacement art.
The ten existing smithable equipment-form icons are preserved for dropped gear.

## Regression commands

`python tools/test_starforged.py --godot <Godot-4.5.1-executable>` runs the focused
Starforged, existing crafting, Smithing UI, equipment, acquisition, persistence
and Mining suites. The focused test checks the real catalog, stale recipe/server
requests, deliberately misconfigured enabled conversions, all current monster
resource sources, explicit loot injection, aliases and save versions 1–4.

Validated: 11 suites / 8,684 checks passed; editor import and main-scene startup
passed. Independent review found no blocking defects. Save-version tests use
current-shaped fixtures with historical version tags, not archived player saves;
authentic historical fixtures remain a minor test-coverage improvement.
The two older station UI tests now synchronize both actor/player positions using
the same grid approach as the existing crafting UI test; gameplay is unchanged.

See `docs/mining/starforged-audit.md` at repository root for the pre-change audit.
