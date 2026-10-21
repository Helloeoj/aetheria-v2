# Equipment crafting

The crafting service exchanges approved backpack ingredients atomically. Furnace
and anvil routes now use the guided [Smithing minigames](Smithing.md), including
timing and per-bar XP. Other exchanges remain immediate and award no XP.
Pending recipes remain disabled. There are 22 approved and 202 pending routes.

## Available exchanges

| Station | Ingredients | Output |
|---|---|---|
| Leatherworking | 1 Starter Hide | 1 Tanned Leather |
| Leatherworking | 2 Tanned Leather | 1 Tanned Leather Coif |
| Leatherworking | 5 Tanned Leather | 1 Tanned Leather Tunic |
| Leatherworking | 3 Tanned Leather | 1 Tanned Leather Chaps |
| Blacksmith's anvil | 1 Bronze Ingot | 1 Bronze Dagger |
| Blacksmith's anvil | 3 Bronze Ingots | 1 Bronze Longsword |
| Orb empowerment | 1 Magic Orb + 1 Fire Sigil | 1 Fire Orb |
| Orb empowerment | 1 Magic Orb + 1 Ice Sigil | 1 Ice Orb |
| Orb empowerment | 1 Magic Orb + 1 Lightning Sigil | 1 Lightning Orb |
| Orb empowerment | 1 Magic Orb + 1 Hurricane Sigil | 1 Hurricane Orb |
| Staff assembly | 1 Wooden Staff Body + 1 Magic Orb | 1 Apprentice Magic Staff |
| Staff assembly | 1 Wooden Staff Body + 1 Fire Orb | 1 Apprentice Magic Staff (Fire) |
| Staff assembly | 1 Wooden Staff Body + 1 Ice Orb | 1 Apprentice Magic Staff (Ice) |
| Staff assembly | 1 Wooden Staff Body + 1 Lightning Orb | 1 Apprentice Magic Staff (Lightning) |
| Staff assembly | 1 Wooden Staff Body + 1 Hurricane Orb | 1 Apprentice Magic Staff (Hurricane) |

The three starter leather armor pieces cost ten leather total. Capes use cloth
and Tailoring, regardless of the combat style wearing them.

Plain Magic Orbs and sigils have no manufacturing recipe. Empowerment permanently
converts one dropped orb, consumes one matching sigil, and produces exactly one
empowered orb. Empowered orbs cannot be used as plain orbs, combine enchantments,
change element, extract sigils, or replace the orb inside an equipped staff.
Staff assembly consumes its body and orb. A plain staff has no orb status effect.

## Pending recipes

The following routes appear as unavailable until ingredient quantities and yields
are approved. Possessing materials does not enable them.

- Furnace routes now use one corresponding ore per ingot, with no fuel added.
- Anvil: ingots into metal weapons, armor, shields, arrowheads, crossbow metal
  components, and bolts. Bolts require the respective metal ingots; no wooden bolt
  shaft or feather requirement is added.
- Fletching: logs into arrow shafts, staff bodies, and wooden crossbow stocks;
  animal sinew into bowstrings; logs plus bowstrings into bows; stocks, metal
  components, and bowstrings into crossbows; shafts, feathers and arrowheads into
  arrows.
- Leatherworking: higher hides/scales/skins into corresponding leather and leather
  into coifs, tunics and chaps. Aetherwyrm Leather is already the boss-dropped
  material, so no additional invented raw hide intermediary is required.
- Tailoring: appropriate monster cloth/scraps into usable cloth, then cloth into
  hoods, robe tops, robe bottoms, and every cape. Raw scrap definitions and ratios
  remain pending.
- Higher staffs: tier-specific staff-body materials and log mapping remain pending.
  Five plain/elemental staff routes are recorded per higher tier, but none can be
  used to produce higher equipment from the starter body.

These route records do not implement resource gathering, define log species,
invent alloy costs, set higher armor stats, or create crafting XP skills. Existing
wand records represent the staff family through catalog migration; a separate
wand recipe family is not introduced. Existing bow/crossbow display names remain
catalog identifiers until their future log/material mapping is specified.

## Materials and acquisition constraints

| Tier | Metal | Leather | Cloth | Staff prefix |
|---:|---|---|---|---|
| 1 | Bronze | Tanned Leather | Homespun | Apprentice |
| 2 | Iron | Wolf Leather | Woven | Adept |
| 3 | Steel | Direwolf Leather | Runic | Runic |
| 4 | Blacksteel | Troll Leather | Enchanted | Enchanted |
| 5 | Mithril | Dragon Scale Leather | Astral | Astral |
| 6 | Adamantite | Demon Skin Leather | Empyrean | Empyrean |
| 7 | Starforged | Aetherwyrm Leather | Celestial | Celestial |

Crafting components can be monster loot. Highest-tier materials are boss-only:
Starforged Ore comes from Golem Titan, Aetherwyrm Leather from the future
Aetherwyrm boss, and Celestial material from a still-undecided future boss. A
celestial beast is a proposal, not a finished encounter. Future tree and ore
gathering must preserve this restriction.

Animal Sinew belongs only to animal/beast loot; humans and humanoids are excluded.
There is no Hunting skill. Leatherworking produces leather armor; Tailoring
produces cloth and robes. Monster loot is the current material source; trees and
ore deposits are extension points for future systems.

Rings and necklaces are drop-only. Artifact crafting remains unapproved and has
no recipe. Bait is bought or looted, and ordinary rods are bait-store goods.
Demon Rod is reserved for a rare drop from the future Demon Overlord boss.
Neither rods nor bait have new manufacturing recipes. Orb/cultist assignments,
elemental-sigil boss assignments and their drop odds remain separate loot work.
Food never grants buffs. Salvage is separate pending work: its chance must
decrease with tier inside the approved 60% to 20% bounds, with consumed inputs and
conservative return budgets to prevent material-generation loops.

## Integration contract

`res://scripts/crafting_service.gd` exposes:

```gdscript
CraftingService.list_recipes(station: String = "") -> Array[Dictionary]
CraftingService.craft(player: PlayerState, recipe_id: String,
    station: String, quantity: int = 1) -> Dictionary
CraftingService.empower_orb(player: PlayerState, element: String) -> Dictionary
```

`craft` returns `{"ok": bool, "message": String}` and, on success, the output
counts and batch quantity. UI callers choose an existing recipe ID; they cannot
submit their own ingredient or output definitions. Location/proximity validation
belongs to the world interaction caller. `enchanting` identifies the permanent
orb conversion and does not introduce a new XP skill or require a new world
station.

`res://data/recipes.json` is an array of recipe objects:

```json
{
  "id": "bronze_dagger",
  "name": "Bronze Dagger",
  "station": "anvil",
  "enabled": true,
  "inputs": [{"item": "Bronze Ingot", "quantity": 1}],
  "outputs": [{"item": "Bronze Dagger", "quantity": 1}]
}
```

Pending records set `enabled` to `false`, contain empty numeric `inputs` and
`outputs`, describe `planned_inputs`/`planned_outputs` as names, and give a
human-readable `reason`. Recipe IDs are unique. Station IDs are `leatherworking`,
`anvil`, `furnace`, `fletching`, `tailoring`, and `enchanting`.

All definitions and quantities are validated before inventory changes. Matching
uses canonical catalog names so aliases cannot duplicate material counts. Batch
requests must be positive and fit a signed 32-bit count; arithmetic and existing
stacks are checked against signed 64-bit overflow. Missing ingredients, invalid
catalog entries, missing outputs, or overflow leave the entire backpack unchanged.
Equipped items are never automatically consumed or replaced. Jewelry, plain
orbs, sigils, and artifact-tier equipment cannot be manufactured by this service.
Dead players and players fighting, targeting an opponent, or actively cooking
cannot craft or empower orbs. A caller with a combat engine also checks ongoing
spell casts before invoking the service.

## Verification

Run Godot 4.5.1 with the active project:

```text
godot --headless --path godot_client --script res://scripts/dev_tools/crafting_service_smoke.gd
```

The smoke test exercises real catalog entries and `PlayerState` inventories:
approved material costs, batch results, wrong stations, pending recipes, missing
ingredients/output definitions, quantity overflow, immutable listed recipes,
permanent one-to-one orb empowerment, mismatched sigils, and staff assembly.
It dynamically loads gameplay scripts after autoload initialization so a
`SceneTree` runner does not compile their `GameData` dependencies too early.

## In-game access

The outskirts scene now adds labeled furnace, anvil, Leatherworking, Tailoring, Fletching and bait-store interaction markers near the starting position. Walk within 2.5 simulation units and click/right-click Use to open the corresponding panel. Escape closes it; leaving range, combat or casting closes/rejects use. Existing scenery and artwork are unchanged. Pending ingredient quantities are visibly disabled, not executable recipes.

Inspect a plain Magic Orb in inventory to empower it using one corresponding sigil. One orb and one sigil are consumed permanently; casting, combat and death block the exchange. A wooden staff body and orb can be assembled at the Fletching bench into the plain or corresponding empowered Apprentice staff.

The bait store lists the four purchasable rods and all three bait grades, excluding Demon Rod. The user requested waiting for prices, so purchases remain disabled while those catalog prices are unset. No provisional prices were assigned. Supply eligibility is enforced independently of prices.

Higher equipment costs, boss/cultist drop odds, higher armor balance and other production quantities remain pending. Smithing uses its separate session, timing and XP; see [Smithing](Smithing.md). Other crafting exchanges remain immediate and award no XP.
