# Mandatory worldbuilding validation

**Goal:** Make every new/reused environment prop pass native-art preparation,
actual physics placement tests and recorded visual review before acceptance.
**Authority:** User request of 2026-10-27; routine implementation, local tests,
commit and push are authorized. Preserve all existing art, maps and gameplay.

**Design:** Extend existing HiddenGrid logic with a development-only live-shape
audit and a small portable Python entry point. Read-only checks never reposition
objects, clean pixels, rebuild maps or infer collision from image colors.
A checklist alone would not catch placement errors; blanket map regeneration
would destroy unrelated work. Use explicit contracts for the changed area.
Do not claim automatic blur detection or automatic artistic approval.

**Constraints:** Godot 4.5.1; shared 32-world-pixel grid; actual 24x24 actor body;
nearest/lossless/no-mipmap art; profile-specific native density; environment
only; existing generation holds and separate candidate/approval/install states.
Active checkout has unrelated WIP; commit only this task's changes.

## Task 1: Native prop checks (Python/Pillow)

- [x] Write failing fixtures for wrong canvas, empty art, clipped silhouettes,
  disconnected specks, partial-alpha edges and bad import settings.
- [x] Implement tools/prop_asset_check.py and tools/test_prop_asset_check.py.
  API: check_asset(project: Path, spec: dict) -> dict with passed/checks/issues.
  Each issue has code/detail. Spec: texture res:// PNG, native_size [w,h],
  anchor [x,y], min_component_pixels (default 3), optional explicit exceptions
  alpha_reason, edge_reason, components_reason; each nonempty review reason.
  Check source PNG without mutating it; dimensions, alpha, 8-connected small
  islands, import lossless/mipmap settings. These are evidence leads, not a
  universal automatic artistic quality detector. Exemptions remain visible.
- [x] Run fixtures and canonical approved ore assets; investigate real failures.

## Task 2: Live scene placement audit (Godot)

- [x] Add tools/worldbuilding_audit.gd (RefCounted) and a SceneTree CLI runner
  tools/check_worldbuilding.gd under godot_client; add negative regression suite
  tools/worldbuilding_audit_test.gd. Write/run failing test before implementation.
- [x] Contract v1: schema_version=1, scene=res://scene.tscn, bounds=[x,y,w,h],
  grid_origin=[x,y], props=[{node: relative NodePath, blocking: bool}],
  anchors=[{id, point:[x,y]}], routes=[{id, points:[[x,y],...], width:48}],
  optional floor_polygon=[[x,y],...], optional assets=[asset specs from task 1].
  Coordinates/bounds/grid origin are WORLD pixels; author them explicitly for
  the installed scene including parent transforms. At least one prop, two
  anchors and one protected route required; no empty pass. Nonblocking props
  need a reason. Reject nonfinite/malformed values with structured failures.
- [x] API audit(map: Node2D, spec: Dictionary) -> Dictionary containing passed,
  checks, issues (code/node/detail), rendering_verified=false. Must run after
  physics registration. Enumerate actual enabled body shapes/transforms;
  exclude only each audited prop's own bodies from overlap queries. Reject
  solid bases overlapping walls/peers or outside bounds/floor polygon. Reject
  missing footprints for blocking props. Reject blocked exact anchors, broken
  32px HiddenGrid routes with actor swept edges, blocked reserved lane sweeps
  at requested width (>=24). Exact anchor-to-grid joins must also be swept.
  Route search failure is a rejection, never silent adoption or auto-move.
- [x] Tests use real canonical CopperOreFull props in an isolated fixture:
  valid placement, wall/peer overlap, out of bounds, narrow lane, blocked exact
  goal, disconnected room, absent collider, scaled parent, malformed contract.
  CLI accepts --manifest <absolute JSON> --report <absolute JSON> after --,
  loads editable content only, waits for physics, writes report outside project.

## Task 3: Required workflow and one command

- [x] tools/worldbuilding.py validates the contract, lints referenced assets,
  invokes Godot placement CLI with timeout and error-output checks, combines
  JSON evidence, and returns failure for any failed/incomplete stage. Provide
  --self-test for reusable checks without certifying any installed world.
- [x] Add WORLD-BUILDING-CHECKLIST.md, contract example, and entry-point links
  in AGENTS.md and START-HERE.md/TASK-TEMPLATES.md. Preserve prior edits.
  Require complete native PNG prep or PixelLab redraw/conversion when crop is
  dirty; no cut/paste declaration of completion, no smooth scaling or color-key.
  Require light/dark/ground checks and real 4x render with character, sorting,
  wall seams, full/depleted variants and visual-only clipping inspection.
  Record machine results separately from visual approval and installation.
- [x] Run unit/negative tests, ore-library smoke, editor parse, startup and
  representative actual-map geometry checks. Review new code independently.
- Completion: stage explicit task files, commit, verify origin push URL, push task branch
  and verify remote SHA. No generated output or unrelated WIP in commit.

## Review focus

Shape-owner transforms, concave walls/floor regions, malformed/vacuous manifests,
routes whose nearby goal is clear but exact endpoint is blocked, intentional
visual overhangs, disconnected rooms, narrow paths, and stale grid caches.
Do not certify untouched legacy maps or pending artwork from self-test results.

## Implementation verification

The combined checker accepts the declared canonical-prop lab and rejects its
wrong-resolution, blocked-exact-anchor and obstructed-lane variant. Final
regressions: 16 runner tests; 22 asset fixtures (one Windows symlink-privilege
skip); 49 live-geometry checks; 776 canonical-ore checks; 21 shared-grid checks.
Installed Godot editor import and main startup passed without script errors.
The PowerShell grid runner parses and now includes the worldbuilding suite.

Fresh review identified three false-green paths. Each was reproduced before
fixing: folder scopes excluding overlapping peers, stale imported textures,
and scripted Resource constructors executing before node-script inspection.
They now have passing regressions: real prop-instance scopes, loaded/source
visible RGBA and canvas matching, and dependency preflight before resource load.
Actual sprite source/anchor/density bindings are checked by the combined runner.
No optional review findings remain. Visual approval stays pending per actual
future worldbuilding task; this implementation changes no installed map or art.
