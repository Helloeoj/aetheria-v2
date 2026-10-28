# Tile Teleport Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans for inline implementation. Steps use checkbox syntax for tracking.

**Goal:** Stable tile inspection and Moparscape-style developer teleport.
**Architecture:** Reuse HiddenGrid's address/center transform and physics adapter. A small per-game controller handles commands/overlay; Social intercepts commands before socket sends. Keep server authority for online characters.
**Tech Stack:** Godot 4.5.1, GDScript, existing Godot smoke tests.
**Spec:** `docs/superpowers/specs/2026-10-27-tile-teleport.md`

## Global Constraints

- One cell is 32 world pixels; X east, Y north; no depth coordinate.
- Preserve existing game, all unrelated local changes and character saves.
- No prop, map or collision changes.
- Validate destinations exactly; never relocate to a neighboring tile.
- Commands and results must never be broadcast as player chat.

## Review Focus

- Negative/boundary coordinates round-trip on the authored lattice.
- Wall, unsupported floor and out-of-bounds destinations leave state untouched.
- Old click/chase/held input cannot resume after teleport.
- Offline chat and every chat channel handle commands locally.
- Online commands cannot bypass server permissions or overwrite authoritative state.

### Task 1: Coordinates and sandbox teleport

**Files:** New `godot_client/scripts/dev_tools/tile_commands.gd`, `tile_commands_smoke.gd`, `tile_floor_support.gd`, `tile_floor_smoke.gd`; modify `godot_client/scripts/main.gd`, `godot_client/scripts/social/social_client.gd`, `godot_client/scripts/social/social_panel.gd`.
**Interfaces:** Controller `configure(game)`, `execute(text) -> String`, `cell_at_global(point) -> Vector2i`, `teleport(cell) -> String`; Social `send_chat` consumes :: commands locally.

- [x] Write real-game regression tests for commands, exact center placement, movement cancellation, malformed/blocked/occupied cells, overlay/cursor transforms and online rejection.
- [x] Run tests; observed controller-missing failure before implementation.
- [x] Add minimal controller, integrate into game and existing chat; add concise usage documentation.
- [x] Run test again; 59 real-map command checks and 10 floor-coverage checks, 0 failures, no script errors.

### Task 2: Confirm online scope, validate and synchronize

- [x] User confirmed developer-only scope for now; admin commands are much later work. Preserve existing sandbox permission boundary. Online coordinate inspection works; teleport rejects online/authenticated state.
- [x] Run grid/movement/social regressions, editor import and main startup. Inspect a real rendered coordinate overlay. Real 4x capture exposed HUD overlap; added failing layout checks at 1280x720 and 960x540, moved the label below existing rows, then verified both checks and the corrected render.
- [x] Fresh read-only review found collision-free catacombs void; reproduced before fixing full-body floor support, then passed real Catacombs and permanent floor-hole regressions. No other actionable findings.

Final synchronization: review/stage explicit feature paths, commit and push
`codex/tile-teleport` to verified v2 origin, then verify the remote hash. Report
the final commit URL. The branch inherits the existing unmerged worldbuilding
history, so a feature-only PR to main is not appropriate from this base.
