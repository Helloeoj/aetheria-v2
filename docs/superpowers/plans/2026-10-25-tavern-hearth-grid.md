# Tavern hearth exclusion implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Block the entire central hearth/seating island without changing artwork, and validate Tavern shared-grid movement.

**Architecture:** Add one source-space collision rectangle encompassing the existing hearth and four benches. Feed the same obstacle into physical collision and legacy navigation, remove the unconditional Tavern grid exclusion, and use the ordinary physics audit plus authored circulation probes. Tavern authors a fixed (8,0)-pixel lattice origin so the existing bartender aisle fits, shared by movement/AoE/server/prediction; other maps keep (0,0).

**Tech Stack:** Godot 4.5.1, GDScript, existing Python scene builder.

**Spec:** User request: "make it so the player cant step in that entire area around the central hearth"; "do not change the rtwork at all". The bounded interpretation is the hearth plus its four surrounding benches, source rectangle (395,486,444,318), with outside circulation preserved.

## Global Constraints

- No artwork, UV, scale, furniture-placement or interface changes.
- Shared gameplay grid stays 32 world pixels; body stays 24 pixels; speed unchanged.
- Keep stove/portal ranges, character state, and unrelated/Catacombs changes intact.
- Active-project implementation and validated task-only commit/push are authorized.

## Review Focus

- The formerly clear gaps around all four sides of the hearth must physically block movement.
- Outside circulation and bartender/kitchen access must remain reachable.
- WASD, click walking and authoritative online walks must use the same exclusion.
- Portal arrivals must be safe tile centers; cooking UI/rewards remain unchanged.
- Source/runtime image hashes and visual scene bindings must remain unchanged.

### Task 1: Solid hearth island and validated grid adoption

**Files:**
- Modify: tools/build_tavern_scene.py; generated TavernContent.tscn and layout.json.
- Modify: scripts/grid_map_adapter.gd; scenes/TavernInterior.tscn.
- Test: scripts/dev_tools/tavern_grid_integration.gd; hidden_grid_maps.gd; grid_interaction_integration.gd; tavern_integration.gd; cooking_ui_smoke.gd; tools/test_hidden_grid.ps1.
- Docs: Taverns.md; HiddenGridMovement.md; map-art/PLAYABLE-MAP-PIPELINE.md.

**Interfaces:**
- Consumes: existing builder obstacles, GridMapAdapter.audit(), WorldInteraction and AuthoritativeRegion.
- Produces: one physical/navigation exclusion and optional GridProbes child markers audited by the shared adapter.

- [ ] Write and run tavern_grid_integration.gd: four aisle points blocked, grid adopted, outside routes/keys/clicks/server/stove/exit preserved; expect failure before changes.
- [ ] Add the exclusion to builder obstacles, regenerate only clean generated resources, remove Tavern special hold, and audit optional GridProbes markers.
- [ ] Update prior Tavern integration expectations from exact off-grid pixels to safe centers within unchanged interaction ranges; retain original UI/transaction assertions.
- [ ] Run focused test, full hidden-grid runner, cooking suite and networking suite; inspect errors and unchanged artwork hashes.
- [ ] Obtain read-only final review, review scoped staged diff, commit/push and verify remote hash.
