# Part 6: Orders directive handlers

> **For agentic workers:** Use superpowers:executing-plans inline, test-driven-development and one final independent review.

**Goal:** Reuse existing game systems for directive validation and authoritative
action completion, with locations and NPCs still deferred.

**Architecture:** A shared directive registry distinguishes interaction handlers
from trusted action handlers. Definition validation, lifecycle rules and public
requirement display consume it. Existing region success/death events forward
verified actions; no completion flags or new client event commands are accepted.

**Tech Stack:** Godot 4.5.1/GDScript, existing Orders book/configuration and smoke runner.

**Spec:** User-supplied Part 6 Types A–H and Part 7 equipment rules. User authorized
this phase with “do it up” and explicitly keeps locations/NPCs deferred.

## Global constraints

- Preserve existing mechanics, artwork, minigames, interfaces, saves and unrelated work.
- No live locations, NPCs, encounters, tools, recipes, rewards or rates are invented.
- Production Orders stay disabled. Work in the active PC project and push verified changes.
- Existing player ownership, available-state, region/range and claim protections remain.

## Audit and design

Riddles, searches and ciphers already have interaction rules. Equipment checks need
real nonzero equip requirements, correct worn slot, obtainable catalog items and
tier checks. Skill trials can reuse fishing/cooking success plus native Mining.
Crafting is an actual recipe transaction but has no trainable crafting skill;
support recipe-success objectives from Medium without fabricated level/XP gates.

Mining has native success transactions and a Bronze Ore definition, but the approved
pickaxe catalog is empty and no deposits are placed in normal scenes. Implement its
success bridge while rejecting enabled templates without real tool prerequisites.
Crafting stations are created dynamically; future authored bindings must be stable
and validated against actual nodes. No station placement/naming is changed here.

Ordinary combat uses existing `entity_died.attacker_id` attribution, not invented
party credit. Require an actual dead monster actor, catalog identity, an explicitly
declared target at a configured anchor, and player/monster proximity. Keep native
loot/spawns untouched and suppress duplicate death credit through existing lifecycle.

No implemented NPC dialogue or cursed-pirate encounter system was found. Contact and
cursed handlers remain explicitly unavailable; disabled future templates are allowed.
No general NPC, encounter, marker or harvesting framework is created.

## Review focus

- Manual interaction cannot complete action objectives or bypass cipher/equipment rules.
- Bronze/zero-level gear, carried-but-unworn gear and wrong-slot gear never satisfy equipment.
- Only successful native mining/recipe transactions count, including at the XP cap;
  failed/cancelled/replayed actions and unrelated target/species/recipes do not.
- Combat never counts another character's kill, PvP, live actors, remote monsters,
  duplicate death notifications or a newly revealed task from the same event.
- New directive kinds persist and project safely without exposing unrevealed content.

### Task 1: Shared handlers and definitions

**Files:** new `scripts/orders/orders_directives.gd`; definitions/service/book,
Ledger requirement formatting; new `orders_directives_smoke.gd`/scene/runner entry.
**Interfaces:** known kinds, interaction/event classification, template validation,
and actual equipment requirements. No new private order fields or save version.

- [x] Write and run failing handler, equipment, kind-boundary and persistence checks.
- [x] Implement shared rules and safe enabled-template validation.
- [x] Verify unsupported contacts/cursed content and missing mining prerequisites fail closed.

### Task 2: Native action bridges

**Files:** existing MiningService success metadata and authoritative_region adapters;
directive smoke tests use isolated real native classes and test-only state/geometry.

- [x] Add failing mining success, real recipe and ordinary death attribution regressions.
- [x] Forward only confirmed server-side actions with target and station/deposit identity.
- [x] Verify no new wire completion command or fabricated skill/loot/spawn behavior.

### Task 3: Verify and synchronize

- [x] Run all Orders suites plus relevant Mining/crafting/networking regressions.
- [x] Check import/startup, obtain independent review and resolve substantive findings.
- [x] Update completed/deferred report and review task-only diff.

## Validation and completion

- All 11 Orders suites pass; new directive suite has 49 checks and the existing
  rules suite generates 40,000 Orders.
- All 8 Mining suites and all 13 networking suites pass. Native crafting service
  and UI report 1,202 and 18 checks respectively, with zero failures.
- Editor import and Login startup pass without script/native errors; script UIDs
  are preserved. Independent read-only review found no requested changes.
- Targeted failing/passing regressions cover generic-event cipher bypass, missing
  native mining/crafting/combat credit and malformed level types.
- Synchronization is recorded by this task's Git commit and remote development
  branch. Unrelated local work is excluded; production Orders remain disabled.
