# Bracken Mine Implementation Plan

> **For agentic workers:** Use the approved-image map workflow with parallel bounded tasks in the active project. The user explicitly authorizes local implementation, testing, commit and push without further routine approval gates.

**Goal:** Install the approved fantasy cave as a separate playable mining-area scene with a two-way overworld cave entrance and reusable canonical ore props.

**Architecture:** Preserve the approved1536×1024 layout and original master. Continuous floor/rock artwork stays in terrain layers; existing ore scenes and extracted supply/lantern props remain individual instances. Hand-authored physical boundaries and the existing32px HiddenGrid adapter govern traversal; reuse existing main/UI/portal/network systems.

**Tech Stack:** Godot4.5.1, existing GDScript game, lossless PNGs/native nearest textures, portable asset assembly tools.

**Spec:** Approved2026-10-27 by the user in chat: cave-base-v1.png and cave-candidate-v1.png in supporting work/map-planning/tasks/2026-10-26-mining-cave/. Follow godot_client/docs/map-art/PLAYABLE-MAP-PIPELINE.md. Approval is conditional on fitting the canonical ore sprites; refine placements accordingly.

## Global constraints

- Active project on this PC; preserve unrelated dirty files and existing Golem/Catacombs entrances, UI, saves and game mechanics.
- Environment-only artwork. Reuse scenes/MapProps/OreNodes at scale1; never regenerate ore.
- Native1536×1024 world bounds, immutable gameplay grid origin(0,0),32px cells,24px actor body.
- Preserve original approved master. Pixel cleanup and hidden-floor repair must preserve approved visible geometry and routes.
- No new mining skill logic, recipes, item/tool definitions, rewards, progression or depletion rules.
- Final user roster: copper, tin, iron and coal only. Place these canonical props in suitable pockets after layering; exclude all higher ores and catalysts.

## Review focus

- Door frames in decorative alcoves must not advertise unimplemented routes; keep them as lantern supports.
- Safe two-way portal arrivals and no collision gaps outside the illustrated floor.
- Same navigation geometry offline and online; movement, saves and reconnect preserve state.
- Ore approaches remain reachable; wall depth sorting must match physical bases.
- Source art itself must look crisp beside the character at4x, beyond texture filtering alone.

### Task1 — Preserve and prepare approved art

Files: art_sources/bracken-mine/; godot_client/Assets/Maps/BrackenMine/; tools/build_bracken_mine.py (or an equivalent portable builder).

- [x] Archive exact approved base/candidate with prompt, provenance and mapping.
- [x] Correct soft source pixel clusters deterministically without changing layout; retain original.
- [x] Separate supply props/lanterns and repair only newly hidden floor; retain complete silhouettes/anchors and exact visible master pixels where possible.
- [x] Compose native ore props at safe positions and render real Godot4x comparison.

### Task2 — Authored collision and shared-grid navigation

Files: godot_client/scenes/BrackenMineContent.tscn; Assets/Maps/BrackenMine/layout.json; scripts/dev_tools/bracken_mine_geometry.gd.

- [x] Write a failing geometry integration check for the missing area.
- [x] Hand-author floor boundary, central rock/pool exclusions and physical prop bases using the approved image; do not infer walkability from colors.
- [x] Add GridProbes and native canonical ore instances; prove spawn-to-room and ore-approach routes, diagonal/swept24px clearance and wall/pool exclusion.

Interfaces:1536×1024 content at identity transform; primary arrival(768,928), exit approach near(768,896), exact final points resolved against geometry. Root content supports GridProbes; canonical ore instances retain metadata and paired colliders.

### Task3 — Scene and portal integration

Files: scenes/BrackenMine.tscn; scenes/BrackenMineEntrance.tscn; scenes/EastOutskirtsLayered.tscn; network/world_protocol.gd; scripts/scene_travel.gd (scoped hunk only).

- [x] Write a failing integration check for registered scene, entrance and reciprocal destination.
- [x] Reuse current main/UI/cave_portal and shared HiddenGrid behavior. Add distinct BrackenMine region, safe Entrance and BrackenMineReturn markers.
- [x] Choose a clear unoccupied overworld approach without moving/removing existing art; preserve current Golem portal.
- [x] Check offline two-way travel and character state; authoritative admission, safe arrivals and region mapping; input/click movement.

### Task4 — Review, verify and publish

- [x] Reimport, run geometry/portal/grid checks and existing relevant transition regressions; render full scene and4x details.
- [x] Independent review of scoped changes and visual/geometry alignment; fix material issues.
- [x] Document placement/exit, art provenance, editable props and validation limits. Update this ledger and task record.
- [x] Commit only mine changes and push to verified Helloeoj/aetheria-v2 codex branch; leave unrelated files untouched.

Ruling: The user approved the cave images and remaining workflow on2026-10-27. Routine implementation gates are overridden by standing workspace instructions. Work is performed in the active project, without an isolated checkout. The working ore roster is an art/layout proposal only and does not create production MiningDeposit rewards or rules.

Completion evidence: geometry2248/0; native travel58/0 (GPU capture run61/0); existing portal19/0, scene-state26/0, online-region111/0. Installed GPU composition0backgrounddifferences,23256opaqueorepixels0RGBmismatches,4x0nonuniformblocks. All328clearcentersreachable;22authoredprobes/25mainadapterchecks. Exteriorentrance(672,-96), return(672,0), cleargrasswestofriversideroad. Reviewfoundnoimportantissues. Originalmasterandorepixelsretained; sourceexport/decompositionprovenancekept.
