# Dead Man's Orders — framework status

## Scope and authority

The user authorized implementation after a compatibility audit, then narrowed it to
the major framework. Actual hunt locations, NPCs and new world content are not part
of this installation. Missing systems must remain disabled rather than invented.
The conversation's reward decisions supersede the attachment's example rewards.

Production `data/dead_man_orders.json` is deliberately `enabled: false`, with empty
anchors, directives and reward pools and zero acquisition probabilities. There are
no live hunts or normal-game order drops. This is a tested framework, not a completed
treasure-hunt content release. Existing login, saves, gameplay, maps and artwork stay.

## Implemented

- Four tier definitions from the supplied brief: Deckhand (2–3 directives/2 available),
  Smuggler (3–4/2), Corsair (4–5/2), Dread Captain (5–7/3). Proposed gate probabilities
  and ranges remain data, not final economy commitments.
- Four sealed packet catalog definitions, IDs 9001–9004. They are excluded from
  generic loot and crafting. Opened instances live in character state, not stackable
  backpack items, so they cannot be transferred as ordinary inventory.
- Authored-template generation with weighted choices, optional order-level gates,
  randomized reveal order, bounded concurrent directives and final cache selection.
  No runtime AI, generated lore, map fragments, fixed quest chain or new skill.
- Durable per-tier lifecycle counters prevent a stale activation from consuming a
  second item, including after abandonment/claim. At most one active instance per
  tier; additional sealed packets can remain in the backpack.
- All directives, cache and base reward selections are generated once. Activation
  fails without consuming the packet when content is unconfigured or invalid.
- Search/riddle/cipher/equipment validation entry points and trusted action completion
  entry point. Available directives can complete in either order; completing one
  reveals the next sealed directive. Earlier or sealed actions do not grant credit.
- Existing authoritative fishing/cooking success hooks carry actual species/station
  information. Failed catches, burnt/cancelled cooking and repeated feedback do not
  earn credit; a successful action still works at the XP cap.
- Owner/range/region/skill checks, finite command bounds and a strict server intent
  allowlist. Clients cannot supply completion flags or reward contents.
- Personal claim logic: complete the order, reach its cache, preflight every item and
  currency bound, then grant all rewards and mark claimed together. Duplicate claims
  and cross-player lifecycle operations are rejected. Failed preflight changes neither
  rewards nor claim state. The existing world host persists before acknowledging.
- Native Captain's Ledger appended to the existing character journal. Original pages,
  artwork and controls remain. Includes available/completed directives, sealed count,
  cipher input, cache interaction, sealed-item action and confirmed abandonment.
- Character save v3 with v1/v2 migration, retaining existing Mining migration and all
  existing progression. Invalid present order data fails closed; it is never reset.
- Explicit client projection from the acknowledged saved state. Hidden directives,
  answers, cache and preselected rewards are not sent in joined/snapshot packets.
  Applying a public projection cannot replace the private server book.
- Existing backend JSON/revision/idempotency storage is reused; v3 is accepted without
  a database schema migration or a parallel transaction/inventory framework.

## Deliberately not supplied

| Needs content, information or later implementation | What is needed |
|---|---|
| Live world anchors and caches | User-selected locations, valid interaction targets, access and route checks |
| Live directive library | Riddles, descriptions, cipher answers, desired tasks and tier assignments |
| NPC/contact objectives | Existing or separately approved NPCs and dialogue hooks |
| Equipment and combat content bindings | Obtainable gear, actual requirements, eligible enemy targets and attribution rules |
| Cursed crews/captains | Approved lore, art, AI/spawn content, encounter ownership and recovery rules |
| Order acquisition | Approved eligible sources, tier mapping and drop rates; no live sources are bound |
| Reward pools and balance | Approved items, quantities, rates and target completion-time/economy assumptions |
| Crownless and named mega weapons | Artwork, existing-stat counterparts, requirements and purely cosmetic animations |
| Transformation pendants | Grounded creature selection, approved tiers, sprites/animations and transformation rules |
| Balm, resins, Moonlit Bait | Exact effects, consumption/limits, artwork and existing-system integration |
| Waystone Tablet / Thornwake Resin | These remain candidates pending a final item decision and mechanic details |
| Replacements after world/content updates | Controlled migration policy; never a player-triggered free reroll |
| Trade/pet/title/transmog extensions | No new framework is created just for a provisional reward |

The disabled reward manifest records nine Crownless pieces, the three retained mega
weapon names, Wolf/Moonfang/Slime/Golem Titan pendant designs and the retained rare
consumable designs. It is design metadata only, not obtainable reward definitions.
Moonfang is mega rare; other unfinished pendant tiers are not inferred from combat
strength. Flying and spider forms are excluded. Mega rewards must retain the user's
Runite-equivalent combat usefulness (the catalog's historical Runite tier is now named
Starforged); cosmetic rarity does not add stronger attacks.

Removed: ordinary equipment candidates, Dawnblood Tonic, Starwell Ampoule, Wardstone,
Monarch's Seasoning, Oathwax, Stonebite/Sundawn/Rimeglass resins, old gilded/heraldic
armor and the combat-effect mega consumables. Stoneward Ring is not in the selected pool.

## Integration map

- `scripts/orders/order_book.gd`: bounded private save validation and public projection.
- `scripts/orders/orders_definitions.gd`: disabled configuration and enabled-content validation.
- `scripts/orders/orders_service.gd`: generation, activation, directives, claims and abandonment.
- `scripts/orders/orders_targets.gd`: future target resolution through existing authored
  interaction APIs; no coordinates or targets are embedded in this code.
- `scripts/orders/orders_controller.gd`: native journal adapter; online actions are intents.
- `scripts/orders/orders_ledger.gd` / `scripts/ui_inventory_menu.gd`: journal presentation.
- `network/authoritative_region.gd`: command schema, owner context and trusted action adapter.
- `network/character_codec.gd` / `world_host.gd`: durable saves and private/public boundaries.

## Validation and developer inspection

Run `tools/test_orders.py --godot <installed Godot 4.5.1 console executable>`.
It runs definitions, rules (10,000 generations per tier), authority, activity hooks,
journal, character codec and real in-process host transport/persistence tests. Logs/results are written
outside the repository; script/native errors fail the runner even with exit code zero.

`scripts/dev_tools/fixtures/orders_config.json` is synthetic test-only content with
test rewards, text and rates. It is never loaded by normal gameplay. Its location
references use already tracked scene nodes; no map or NPC content is installed.

For UI inspection, use Login's existing developer sandbox, open the character journal
and select Captain's Ledger. It correctly reports that hunts are not available yet.
F6 can inspect the four sealed catalog packets in the unsaved sandbox; opening one
with disabled production content preserves the packet. Real accounts receive no debug
grants. Run the smoke fixtures to test the complete lifecycle without live player data.

Backend validation uses isolated test storage. PostgreSQL-only concurrency tests are
reported separately when skipped; no real saves are rewritten by the framework tests.

Verified results: all seven Orders suites pass (23 definitions, 35 rules including
40,000 generations, 17 authority, 22 activity, 43 UI, 59 codec and 64 host checks).
The existing networking suite passes all 13 suites, and inventory passes 126 checks.
Adjacent fishing/cooking/UI and original online minigame regressions pass. Godot editor
import and Login startup complete without script/native errors. Isolated backend tests
report 27 tests OK with three PostgreSQL-only tests skipped; live PostgreSQL concurrency
was not certified by this run. Independent code review's two findings were fixed and
their failing/passing regressions recorded outside Git.
