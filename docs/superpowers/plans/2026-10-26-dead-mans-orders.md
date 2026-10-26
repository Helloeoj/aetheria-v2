# Dead Man's Orders implementation plan

User authorization: proceed with phased implementation after compatibility audit.
The attached complete system brief is amended by the conversation's reward decisions.
Use the active checkout; preserve unrelated local edits. No new worktree, redesign,
NPC lore, map artwork, or parallel inventory/persistence architecture.

**Latest scope ruling:** user explicitly requested only the major framework, without
actual locations/NPCs, and asked that missing systems be worked around rather than
invented. Production content, rewards and acquisition remain empty/disabled. Authored
example data is confined to test fixtures. The content/playable-hunt parts below are
future integration interfaces, not live bindings. Report those dependencies clearly.

## Compatibility audit

- Godot 4.5.1; Login remains the main scene. `AuthoritativeRegion.submit` validates
  gameplay intents. `world_host._process_commands` persists successful mutations
  before acknowledgement; backend saves use revisioned idempotent transactions.
- `PlayerState.backpack` stacks names/counts. Opened orders therefore require bounded
  instance state in the existing character save, not normal stacked items.
- `CharacterCodec` v2 saves need a backward-compatible v3 migration. Full state is
  currently sent to clients: a separate committed public projection must hide sealed
  directives, cache and reward selections. Never project mutable uncommitted state.
- Actual anchors: outskirts tavern/cave doors and two river fishing spots; tavern
  exit/stove; golem exit/catacombs entrance; catacombs exit. Use authored approach
  APIs and runtime reach/path checks. No guessed coordinates or Dreadmoor.
- Existing journal has Inventory/Skills/Spells/Equipment/Combat pages, no quest
  framework. Append Captain's Ledger with the same controls/theme.
- Real fishing/cooking/combat success hooks exist. XP changes alone cannot prove
  an action: capped skills still complete tasks, failed actions never do.
- No implemented pirate contacts, cursed crew, party credit, pets, transmog, titles,
  shapeshifting, coatings or exclusive reward artwork. Unsupported content remains
  disabled and explicitly reported. Do not invent its existence.
- Base rewards use a small explicit existing-item whitelist. Boss-only Starforged
  materials and pending Celestial materials are excluded. User's Runite reference
  corresponds to the renamed Starforged equipment tier; exclusive stats are deferred.

## Interfaces and tasks

1. Definitions (`data/dead_man_orders.json`, `scripts/orders/orders_definitions.gd`):
   four tier rules, stable anchor references, authored templates, conservative base
   reward/acquisition settings and deferred reward manifest. `load_data` returns
   `{ok,errors,config}`; `validate(config)` rejects broken content.
2. Private book and rules (`scripts/orders/order_book.gd`, `orders_service.gd`):
   `empty_book`, strict `validate_book(value,owner_id)`, `public_book`; configurable
   random generation and lifecycle. Book holds four per-tier monotonic generations
   and at most one latest instance per tier. A stale activation generation cannot
   consume another sealed item. Generate directives/cache/rewards once before
   consuming; failed generation leaves inventory untouched. Claim preflights the
   whole reward and marks terminal state with the same inventory mutation.
3. Persistence: add `PlayerState.dead_man_orders` and public `orders_view`; v1/v2
   migrate into v3. Backend accepts v3. Both joined/snapshot messages use public
   projection of acknowledged save. Client decode_public never validates a projection
   as a private save. Tests cover corruption, migration, projection and replay.
4. Native integration (`orders_anchors.gd`, `orders_controller.gd`, region/activities,
   main and sealed item definitions): position/region/line-of-sight checks from actual
   node approaches; server-only completion/acquisition hooks; one event credits one
   matching available directive. Server command schema rejects injected fields.
   Fishing/mining/cooking UI and existing actions remain unchanged.
5. Ledger (`orders_ledger.gd`, existing inventory journal): append page and sealed
   item action. Available directives can be completed in any order. Search/cipher
   and personal cache interactions validate the player's current nearby anchor.
   Abandon uses a confirmation dialog. No client-side reward/progress mutation.
6. Validate with deterministic rule tests and 10,000 generations per tier; real
   scene-anchor, authoritative multiplayer, save round-trip, replay, wrong-position,
   full-count and UI tests; relevant existing inventory/activity/network regressions,
   editor import and Login startup. Record disabled content honestly.
7. Review only task changes, commit explicit files and push `codex/dead-mans-orders`
   to verified `Helloeoj/aetheria-v2`, preserving all unrelated local work.

## Verification commands

Use the installed Godot 4.5.1 console executable.
New runner `tools/test_orders.py --godot <engine>` must reject script/native errors
and require positive pass markers. Evidence goes to temporary directories outside Git.
Run `tools/test_inventory_items.py`, relevant existing fishing/cooking/network suites,
`--headless --editor --path godot_client --quit`, and Login startup. Backend tests
use isolated test storage; never modify live player saves.

## Completion reporting

Report shipped order tiers/types, tested limitations, deferred exclusive rewards and
pirate content, exact validation, commit and push URL. Do not call deferred templates
or art complete. Rates are provisional test configuration, not an economy guarantee.

## Execution record

- Audit complete; native journal and authoritative/save APIs reused.
- Framework modules, private/public save migration, server commands and journal implemented.
- Production content remains deliberately disabled under the user's later scope ruling.
- Read-only review found incompatible-anchor validation and terminal-journal controls;
  both received failing regression tests and passing fixes. Reviewer reports no remaining findings.
- Rules generated 40,000 orders; targeted lifecycle, privacy, activity and UI checks pass.
- Existing inventory/activity/network suites and isolated backend tests validated.
- Final task paths reviewed and staged for release; unrelated workspace edits excluded.
