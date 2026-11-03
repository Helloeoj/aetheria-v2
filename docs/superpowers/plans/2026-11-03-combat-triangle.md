# Combat triangle implementation plan

**Goal:** Make melee, ranged and magic equipment produce the requested classless combat triangle, primarily through hit chance.
**Architecture:** Retain five existing armour ratings and their diminishing returns. Extend the melee roll comparison to player ranged/magic; snapshot offensive rolls in projectiles and resolve against the actual target's current defences. Retain authored NPC non-melee attacks and explicit accuracy overrides.
**Tech stack:** Godot 4.5.1, GDScript, existing JSON item catalog.
**Spec:** User request and answer: free multiclass swapping; plate beats arrows, ranged armour beats magic, robes trade physical protection for magic power; player magic defence uses 70% Magic and 30% Defence. OSRS-style armour primarily changes hit chance.

## Constraints and decisions

- Work in the active project, preserve unrelated edits, saves, controls, artwork, special-effect metadata and existing monster absorption. No new classes, gear tiers, artwork or acquisition systems.
- Keep melee damage/accuracy and standard physical plate ratings. Set explicit combat roles on existing body armour/shields, with cross-style attack penalties and distinct defence profiles. Mage armour grants explicit magic damage separately from accuracy.
- Player magic defence effective level is 0.7 * Magic + 0.3 * Defence + 8. Monster magic defence uses authored Magic, falling back to encounter level until separately authored. Existing fractional NPC resistance data remains compatible.
- Armour attack bonuses/penalties affect accuracy; their magic damage bonus independently affects automatic magic and selected damaging spells. Legacy weapon/jewellery damage scaling is retained.
- Two failed fixes for the same problem is a hard stop. No subagents. Routine design/execution approval gates are overridden by project instructions.

## Review focus

Projectiles retain launch-time attack rolls after swapping; impact uses current actual target defences. Area and elemental spells use magic even with another weapon. Actor creation, refresh and serialization carry all new values, including online refresh via configure. Magic/Defence enter only once; hurricane changes only the Defence component. Existing explicit overrides and NPC absorption remain intact.

## Task 1: Combat and armour integration

- [x] Add a focused real-engine smoke scene for five defence channels, 70/30 skill weights, armour roles, target-dependent projectile accuracy, actual seeded hits with unchanged landed damage, spell power, swaps and runtime actor adapters.
- [x] Run before implementation and confirm intended assertions fail.
- [x] Extend stats, player/monster stats, combat actors, projectile snapshots and real impact/area paths. Update existing item profiles and journal stat explanations.
- [x] Run the focused smoke and relevant bronze/runite combat regressions. Adapt obsolete assertions only where the approved behaviour changed.
- [ ] Run editor import/parse and main startup. Review only this task's delta against saved pre-existing dirty files, stage that delta, commit and push codex/combat-triangle to origin after verifying the authoritative push URL.

## Progress

Initial state saved outside the repository. Base commit c877b63; existing branch was codex/astral-lance-cast-anchor, 59 commits ahead of origin/main. Existing dirty Titan/map/tool work must remain unstaged.

Validation: triangle smoke 37/37, bronze combat 3040/3040, Runite equipment 4453/4453, orb combat 213/213. Godot editor import/parse and default main startup exited 0 without script errors. Parallel diagnostics pruning caused transient directory errors in the first orb run; the isolated rerun passed cleanly. Inline code/catalog review retained all 329 item IDs and changed only combat fields on 83 existing armour/shield items. No product fix was needed after implementation; one new test was corrected because a weapon swap should remove the staff's equipment bonus while retaining trained Magic and magic defence.
