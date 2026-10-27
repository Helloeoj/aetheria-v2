# Dead Man's Orders — framework status

## Scope and authority

The user authorized implementation after a compatibility audit, then narrowed it to
the major framework. The next clarification requires physical nonstacking inventory
Orders, an inventory reader, and a Captain's Ledger collection log with task and tier
counts. The supplied Parts 1–21 remain the larger phased feature specification.
Actual hunt locations, NPCs and new world content are still deferred. Missing systems
must remain disabled rather than invented. The conversation's reward decisions
supersede the attachment's example rewards.

Production `data/dead_man_orders.json` is deliberately `enabled: false`, with empty
anchors, directives and reward pools and zero acquisition probabilities. There are
no live hunts or normal-game order drops. This is a tested framework, not a completed
treasure-hunt content release. Existing login, saves, gameplay, maps and artwork stay.

## Implemented

- Four tier definitions from the supplied brief: Deckhand (2–3 directives/2 available),
  Smuggler (3–4/2), Corsair (4–5/2), Dread Captain (5–7/3). Proposed gate probabilities
  and ranges remain data, not final economy commitments.
- Four sealed packet catalog definitions, IDs 9001–9004, plus their physical opened
  versions, IDs 9005–9008. All eight are excluded from generic loot and crafting and
  occupy individual backpack slots. Existing ordinary inventory stacking is retained.
- Opening atomically replaces one sealed packet with its character-bound opened
  Order. Its saved instance ID is exposed on its inventory slot; the existing limit
  of one active Order per tier makes that physical copy unambiguous. Reading again
  never rerolls. Claiming or confirmed abandonment consumes the opened item.
- Direct inventory clicks open a scrollable native Order sheet; right-click and
  item details also offer Read. Reading does not force a switch to the Ledger.
  Available instructions, requirements, cipher input and revealed cache actions use
  the same authoritative controller. Sealed text and future rewards stay hidden.
- Opened Orders cannot be transferred through offline or server generic drops.
  Progress and claims require the physical item; inconsistent current saves fail
  closed rather than silently recreating copies.
- Authored-template generation with weighted choices, optional order-level gates,
  randomized reveal order, bounded concurrent directives and final cache selection.
  No runtime AI, generated lore, map fragments, fixed quest chain or new skill.
- Part 5 selection pass: task families are weighted independently of how many
  alternative clue texts they contain. Optional `family_weights` accepts known
  directive kinds with finite weights from 0 to 1,000,000; omitted kinds use neutral
  weight 1, and zero excludes a family. No production weight values were chosen.
  Within a chosen family, existing authored template weights still select the text.
- Alternative template IDs/texts for the same objective binding cannot appear twice
  in one Order. Generation prefers another task kind when available, then minimizes
  adjacent identical kinds in the reveal order with randomized ties.
- Cache eligibility counts distinct ordinary objectives after excluding that cache
  and disabled families. Invalid libraries fail validation before a packet is used.
  Configuring a gate chance does not require inventing gated content: when no eligible
  gate exists, generation uses ordinary tasks; an undersupplied gated library uses
  only its available distinct gates. Gate chance is still rolled once per Order.
- Disabled future templates are excluded before resolving their world references.
  Enabled flags must be actual booleans. Skill ranges and gate limits apply to all
  enabled templates, including skill-gated riddles. Deckhand stays ungated, concurrent
  slots cannot exceed minimum task count, and malformed requirement/count types are
  rejected without script errors.
- Durable per-tier lifecycle counters prevent a stale activation from consuming a
  second item, including after abandonment/claim. At most one active instance per
  tier; additional sealed packets can remain in the backpack.
- All directives, cache and base reward selections are generated once. Activation
  fails without consuming the packet when content is unconfigured or invalid.
- Shared riddle/search/cipher/equipment interaction handlers and fishing/cooking/
  Mining/crafting/combat action handlers. Action events cannot bypass a cipher answer
  or equipment interaction. Available directives can complete in either order;
  completing one reveals the next sealed directive. Earlier or sealed actions do
  not grant credit.
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
  artwork and controls remain. It shows sealed/opened/total counts per tier, current
  tasks, and durable completion totals. The inventory reader is an independent entry
  point into those instructions.
- Durable collection counts record only rewards granted by a successful Orders cache
  claim and explicitly marked `orders_exclusive` in the item catalog. Generic adds,
  pickups and ordinary cache supplies never fill the log. Failed/replayed claims do
  not increment it. Counts survive sale/use of the item and subsequent Orders.
  Retired earned entries remain visible. No exclusive rewards are implemented yet,
  so production currently explains the empty collection rather than inventing entries.
- Character save v4 / Orders book v2 with v1/v2/v3 save migration, retaining existing
  Mining migration and all progression. Old book-v1 active Orders receive exactly
  one physical opened item without rerolling or rewriting their tasks. Current saves
  never repair missing/duplicate physical copies automatically. Invalid present order
  or collection data fails closed; it is never reset.
- Explicit client projection from the acknowledged saved state. Hidden directives,
  answers, cache and preselected rewards are not sent in joined/snapshot packets.
  Applying a public projection cannot replace the private server book.
- Existing backend JSON/revision/idempotency storage is reused; v3 is accepted without
  a database schema migration or a parallel transaction/inventory framework; v4 is
  also accepted with inventory and collection state in the same durable operation.
- Activation errors appear in the reader instead of leaving an endless waiting
  message. Existing server result messages now include their command sequence and
  success flag so rejected online activations are correlated to the right request.
  Successful activation still waits for the acknowledged saved-state projection.
- Real game Escape closes the reader first. Window resizing keeps the reader's Close
  and action controls on-screen.

## Part 6 directive handlers

These are reusable framework capabilities. Actual tasks, locations and NPCs remain
deferred, and production Orders remain disabled.

| Type | Completed framework | Still needed before live use |
|---|---|---|
| A: Landmark riddle | Existing authored-text interaction with server location/range validation | Approved riddle text and real landmark bindings |
| B: Hidden stash | Existing nearby search interaction; no shovel or fragments invented | Approved searchable objects and bindings |
| C: Contact | Explicitly unavailable; enabled templates fail validation | NPC selection, established lore and an actual dialogue/completion system |
| D: Skill trial | Existing fishing/cooking hooks plus native Mining success and crafting recipe transactions | Approved tasks and stable station/deposit bindings; Mining also needs an obtainable approved pickaxe |
| E: Equipment | Actual nonzero equip requirements, correct worn slot, obtainable-item and tier validation; requirements displayed in the reader/Ledger | Approved gear/task/tier/location choices |
| F: Cipher | Existing authored answer comparison with normalized text; generic events cannot bypass it | Original cipher texts, answers and targets |
| G: Ordinary combat | Existing authoritative death/attacker attribution; actual dead catalog monster, explicit target binding and player/monster proximity; duplicate deaths excluded | Eligible enemies and authored location bindings |
| H: Cursed crew | Explicitly unavailable; ordinary combat cannot substitute approved bosses | Approved lore, encounters, ownership, recovery and art |

Mining credit follows the committed ore transaction and works at the XP cap. Deposit
identity and generation suppress replay credit. The approved pickaxe metadata is
currently empty, so enabled Mining templates fail validation rather than receive a
fabricated tool. The native Mining test prerequisite double is used only in isolated
tests and grants no production tool.

Crafting credit follows one successful native recipe transaction at its actual
station. A batch grants at most one directive completion; missing ingredients or
failed transactions grant none. Crafting has no trainable skill, so its directives
cannot borrow another skill or introduce a made-up crafting level/XP requirement.
The existing dynamic station setup is unchanged; future authored bindings need stable
nodes. No general harvesting system was added.

The new action connections run in the authoritative region. They do not add offline
sandbox activity completion hooks. No wire command accepts a supplied completion
event, and no normal scene, spawn, loot rule, recipe, rate or item catalog changed in
this phase. Native death attribution continues to determine the credited player.

## Deliberately not supplied

| Needs content, information or later implementation | What is needed |
|---|---|
| Live world anchors and caches | User-selected locations, valid interaction targets, access and route checks |
| Part 5 world-dependent constraints | Authored access/travel metadata and backtracking budgets after locations are selected |
| Live directive library | Riddles, descriptions, cipher answers, desired tasks and tier assignments |
| NPC/contact objectives | Existing or separately approved NPCs and dialogue hooks |
| Equipment and combat content bindings | Approved obtainable gear/tier choices, eligible enemy targets and locations; handlers reuse actual equip rules and native death attribution |
| Mining prerequisites and crafting bindings | Approved obtainable pickaxes, task choices and stable authored deposit/station nodes |
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
- `scripts/orders/orders_selection.gd`: shared eligible pools, objective identity,
  family filtering and varied reveal order for the Part 5 selection rules.
- `scripts/orders/orders_directives.gd`: shared interaction/event capabilities,
  actual equipment requirements and action-specific enabled-template validation.
- `scripts/orders/orders_service.gd`: generation, activation, directives, claims and abandonment.
- `scripts/orders/orders_targets.gd`: future target resolution through existing authored
  interaction APIs; no coordinates or targets are embedded in this code.
- `scripts/orders/orders_controller.gd`: inventory/journal adapter and correlated
  activation feedback; online actions remain intents.
- `scripts/orders/orders_reader.gd`: native physical-Order reading surface.
- `scripts/orders/orders_ledger.gd` / `scripts/ui_inventory_menu.gd`: collection,
  current-task overview and existing inventory integration.
- `network/authoritative_region.gd`: command schema, owner context and trusted action adapter.
- `network/character_codec.gd` / `world_host.gd`: durable saves and private/public boundaries.

## Validation and developer inspection

Run `tools/test_orders.py --godot <installed Godot 4.5.1 console executable>`.
It runs focused directive/native-action and generation selection, physical inventory/
collection, reader/input, definitions, rules (10,000 generations per tier), authority,
activity hooks, journal, character codec and real
in-process host transport/persistence tests. Logs/results are written
outside the repository; script/native errors fail the runner even with exit code zero.

`scripts/dev_tools/fixtures/orders_config.json` is synthetic test-only content with
test rewards, text and rates. It is never loaded by normal gameplay. Its location
references use already tracked scene nodes; no map or NPC content is installed.

For production UI inspection, use Login's existing developer sandbox, open the
character journal and select Captain's Ledger. It correctly reports that hunts are
not available yet and no exclusive reward catalog has been installed. F6 can inspect
the catalog packets in the unsaved sandbox; opening a sealed packet with disabled
production content preserves it. Manually granting an opened catalog item does not
create a valid hunt. Real accounts receive no debug grants.

For a complete isolated inventory flow, run the `orders_reader_smoke.tscn` developer
scene. It uses synthetic authored test data, clicks the packet from the actual grid,
reads/rereads its persistent opened item, exercises delayed/rejected activation,
checks the Ledger and actual game Escape/offline-drop path, then exits. The physical
inventory suite completes real service directives and claims, tests legacy migration,
duplicate/missing items, exclusive-only collection accounting and bounded atomic
failure. These fixtures never enable production content or touch live account saves.

Backend validation uses isolated test storage. PostgreSQL-only concurrency tests are
reported separately when skipped; no real saves are rewritten by the framework tests.

Verified results for physical Orders: all nine Orders suites pass (34 physical
inventory/collection checks, 35 reader checks, 23 definitions, 35 rules including
40,000 generations, 17 authority, 22 activity, 43 journal UI, 59 codec and 66 host
checks). The reader's final duplicate-rejection regression was rerun after its fix.
The existing networking suite passes all 13 suites, and inventory passes 130 checks.
Godot editor import and Login startup complete without script/native errors.
Isolated backend tests report 28 tests OK with three PostgreSQL-only tests skipped;
live PostgreSQL concurrency was not certified by this run. Review findings for failed
activation, actual-game Escape, viewport resize and stale duplicate rejection were
reproduced in failing regressions and fixed. Combined collection capacity also has a
failing/passing atomicity regression. Machine logs and screenshots stay outside Git.

This validates inventory/Orders framework behavior, not live content or economy
balance. New v4 saves require the matching updated authoritative host/backend code;
the existing database schema needs no migration.

The Part 5 selection pass adds focused regressions for unavailable/partial gates,
disabled and malformed definitions, family weight filtering/frequencies, alternative
wording, duplicate bindings, cache feasibility and minimum-repeat reveal order. The
40,000-Order simulation also checks actual per-tier gate frequencies, requirement
ranges, gate maxima and concurrent available slots. This pass leaves actual locations,
NPCs, equipment/contact/combat/cursed content and travel constraints deferred.
Fresh Part 5 verification: all ten Orders suites pass, including 28 focused generation
checks and 43 rules checks plus 40,000 generated Orders. Inventory reading, physical
item lifecycle, definitions, authority, activity integration, journal, codec and real
host persistence/transport regressions pass. Editor import and Login startup also
pass without script/native errors. Independent review reports no remaining findings.

Fresh Part 6 verification: all eleven Orders suites pass, including 49 focused
directive checks, the existing 40,000-Order rules simulation, inventory reader,
ownership, activities, journal, codec and real host persistence/transport. All eight
Mining suites and all thirteen networking suites pass. Native crafting reports
1,202 transaction checks and 18 UI checks with zero failures. Editor import and Login
startup complete without script/native errors. Independent read-only review found
no issues requiring changes. The focused regressions first reproduced event-based
cipher bypass, missing action credit and malformed requirement handling, then passed
after their fixes. Test geometry/content never changes normal maps or real saves.
