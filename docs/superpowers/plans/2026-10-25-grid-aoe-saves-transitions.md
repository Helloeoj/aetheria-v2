# Tile AoE, saved positions and transitions implementation plan

> **For agentic workers:** Use superpowers:executing-plans inline, with test-first steps and a final independent review. Work in the active checkout as required by AGENTS.md.

**Goal:** Finish phase 5 and incorporate the omitted phase-2 requirement that AoE sizes remain undecided, configurable and visibly provisional.

**Architecture:** A shared SpellFootprint produces deterministic cells for combat and a debug overlay. WorldState retains the map's cell lattice even when movement adoption is held. Collision-swept placement resolves valid legacy coordinates and authored arrivals without changing durable save format or crossing walls.

**Tech Stack:** Godot 4.5.1, GDScript, existing physics and network snapshots.

**Spec:** User's phase-5 request and provisional-size amendment; godot_client/docs/HiddenGridMovement.md.

## Global Constraints

- Preserve existing controls, interfaces, art, IDs, resources, damage, cast timing and saves.
- Existing area_radius values are provisional, not approved balance.
- Retain existing AoE wall behavior: no wall filtering.
- One 32px map-local lattice; committed actor occupancy decides hits.
- Tavern retains its movement compatibility hold. Never change geometry to hide failures.
- Preserve all unrelated dirty files and Catacombs work; do not modify scene_travel.gd's existing changes.

## Review Focus

- Target moving during cast: capture its committed cell once, never retarget at resolution.
- Displacement and unfinished steps: hits use current committed occupancy, not rendering.
- Online preview: display authoritative captured cell, not a moving target guess.
- Invalid saved coordinates: reject unsafe migration without overwriting progress or jumping floors.
- Region replacement: no held keys, old routes, prediction, casts or preview survive.

## Task 1: Shared AoE cells and provisional spell data

Files: new scripts/spell_footprint.gd; scripts/world_state.gd, combat_system.gd; data/spells.json; new dev_tools/grid_aoe_unit.gd.

Interfaces: SpellFootprint.cells(grid, center_cell, spell) -> Array[Vector2i]; WorldState.occupied_cell(id) -> Vector2i; WorldState.cell_grid holds the same lattice as movement.

- [x] Write/run failing tests: circle counts radius2=13,2.5=21,3=29,3.5=37; zero/negative/nonfinite inputs; negative/map-edge cells; immutable cast cell; actors enter/leave on arrival; wall behavior unchanged.
- [x] Implement inclusive center-distance circle; per-spell optional explicit offsets; mark each area definition area_size_status=provisional, area_shape=circle, area_wall_behavior=ignore.
- [x] Run the unit suite and existing spell/orb/combat regressions.

## Task 2: Development-only in-game preview

Files: new scripts/dev_tools/aoe_tile_preview.gd; scripts/main.gd; network/authoritative_region.gd, world_host.gd, online_world_view.gd.

Interfaces: preview uses SpellFootprint.cells; server supplies own active area_cast descriptor with captured cell and spell definition; Ctrl+Shift+V toggles overlay only in debug non-tester builds.

- [x] Write/run failing tests: preview initially off, selected-target footprint, cast locks footprint, server snapshot descriptor and preview agreement.
- [x] Implement tile outlines/fill and provisional label, no new targeting UI or final art; serialize only recipient's cast descriptor.
- [x] Verify existing spell controls and capture a real rendered preview for inspection.

## Task 3: Collision-safe migration and arrival placement

Files: new scripts/grid_placement.gd; scripts/main.gd; network/authoritative_region.gd, world_host.gd; new dev_tools/grid_placement_unit.gd; update affected legacy spawn fixtures.

Interfaces: GridPlacement.resolve(grid, point) -> Vector2, nonfinite on unsafe placement. Admission and portal placement share it. Existing codec versions remain readable; migration happens after map physics is available.

- [x] Write/run failing tests: old off-grid save retains inventory/stats, idempotent center placement, thin-wall nearest-center trap, disconnected/invalid location rejection, real portal center arrivals, Tavern hold.
- [x] Implement checked local recovery, not coordinate rounding or arbitrary spawn fallback; preflight travel placement before removing source actor.
- [x] Clear presentation/held input at scene replacement and verify real transitions.

## Task 4: Verification and synchronization

- [x] Add suites to tools/test_hidden_grid.ps1; update HiddenGridMovement.md with corrected design, sizes, edit locations, preview toggle and migration limits.
- [x] Run full grid runner, cooking/fishing, inventory, spell/orb regressions; inspect editor/startup output.
- [x] Independent read-only review; fix important findings with failing regression first.
- [ ] Stage only task changes; inspect staged diff/check; commit and push codex/grid-aoe-saves-transitions; verify remote hash.

## Execution record

- Task 1: shared helper missing RED; inclusive footprint/committed occupancy GREEN, 20 checks.
- Task 2: missing debug preview RED; real-map preview and cleanup GREEN, 14 headless checks / 15 with real rendered capture. Capture inspected outside repository.
- Task 3: missing placement helper RED; migration GREEN, 13 checks. Invalid portal arrival RED (orphaned source), preflight GREEN, 78 travel checks.
- Full grid/server runner: 27 suites, zero failures, including editor/startup, real maps, movement, AoE, orb combat, interactions, authority, portal arrival and local Catacombs checks. Cooking/fishing: 12 suites passed. Inventory: 122 checks passed.
- Independent scoped review: no critical, important or minor findings. Rendered preview visually inspected. No final spell art or interface redesign added.
- Synchronization step is completed by the commit containing this file and remote-hash verification reported in the task response; unrelated working-tree changes remain separate.
- Ruling: keep the save schema at version 2, accepting version 1; geometry-dependent migration belongs at admission, not data decoding.
- Ruling: invalid/out-of-map/overlapping saved positions cannot establish a floor, so reject without overwriting the save rather than silently relocate to a spawn.
- Ruling: keep Tavern's continuous movement compatibility hold but use the map's same anchored lattice for AoE; occupancy there follows authoritative continuous position.
- Ruling: work in the active project, no isolated checkout; the user's AGENTS.md expressly requires local installation and preservation of existing dirty work.
