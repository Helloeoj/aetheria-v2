# Dead Man's Orders: physical Orders and collection log

The user's latest clarification supersedes the original menu-centric framework:
sealed and opened Orders are physical, nonstacking backpack items. Clicking an
Order reads its available instructions without requiring the Captain's Ledger.
The Ledger is a collection log for rewards exclusive to Orders and also shows
current tasks and held counts per tier.

## Approach and scope

Reuse the existing backpack and its individual-slot presentation (already used
by fish), the authoritative Orders service, private book, public projection and
native journal controls. Opening transforms one sealed packet into its tier's
opened item. One active Order per tier means its saved instance ID identifies
that physical item unambiguously. No second general inventory is needed.
Keeping all opened Orders only in the journal fails the requested experience;
a new general inventory-instance framework is unnecessary for this scope.

Opened Orders are character-bound and cannot be dropped as ordinary loot; the
existing confirmed Abandon action destroys the item and its progress together.
Claiming consumes the opened Order. Reopening the reader cannot generate tasks.
Existing v3 framework saves migrate their active Orders into physical items
once, preserving task identity and progress. New saves require consistent item
ownership. Online reading uses acknowledged public state and leaks no sealed
directives, answers, future cache or rewards.

Only successful authoritative cache claims record collection counts. Generic
inventory additions and transfers do not. Reward definitions must explicitly
identify Orders-exclusive items; the existing deferred reward designs remain
unimplemented and cannot be counted as obtained. Tier completion counts persist
independently of the most recent Order.

Preserve original journal pages, gameplay, interfaces, artwork and unrelated
local work. Production hunts remain disabled until approved world anchors,
directive content, acquisition rates and rewards exist. This change does not
invent locations, NPCs, combat encounters, reward mechanics or economy values.
The supplied Parts 1–21 remain the larger phased feature specification.

## Acceptance

- Two sealed copies occupy two separate slots; opening preserves one physical
  opened item with stable identity across rereads and reconnects.
- Inventory click and Read actions show current tasks and revealed cache clues;
  the Ledger remains optional and reports tier counts and collection progress.
- Claim/abandon consume the correct physical item exactly once; forged drops,
  missing items and duplicate claims cannot lose or duplicate rewards/progress.
- Migration, collection data, and current/public ownership survive saves safely.
- No unavailable live content is presented as playable or already earned.

Routine design/execution approval gates are waived by the active AGENTS.md.
