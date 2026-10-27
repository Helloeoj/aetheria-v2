# Mandatory worldbuilding checklist

Applies to **every** new environment asset and every placement, move, resize,
replacement, state variant or collision edit of an existing prop, including
PixelLab output. This is the required logic for agents doing worldbuilding.
Read this before editing. An imported image or an attractive screenshot alone
does not complete the task. Preserve existing game interfaces and gameplay.

## 1. Plan the physical object before producing pixels

- [ ] Select the existing area profile and indexed complete prop first. Preserve
  source approval, installation status and generation holds independently.
- [ ] Declare the intended native canvas, visible object size, pixels per world
  pixel, foot anchor and physical base. Use the area's existing density and
  compare the object with the player. A 32-world-pixel gameplay cell does not
  dictate the image canvas. Preserve Golem Kingdom/Catacombs transforms.
- [ ] Record the target scene, world-space placement, floor boundary, nearby
  walls/props, entrances, exits, interaction approaches and reserved lane widths.
  Ore uses canonical scenes, 96px compact/128px route-side spacing, boundary
  placement and clear room centers. Other prop types need their own spacing.
  User-marked positions and colors override default spacing and snapping;
  resolve genuine conflicts minimally and never silently rearrange marked props.

## 2. Make a complete, native-resolution prop

- [ ] Generate missing props at the intended native size in PixelLab with the
  selected area's reference, angle, light and density. Save the untouched
  source, exact prompt/settings and service/job ID. No characters or creatures.
- [ ] A crop is reusable only if it already contains a complete clean native
  object. Do **not** treat a rectangular cut-and-paste from a map, upscaled image
  or blurry concept as a finished prop. Reconstruct missing/occluded parts or
  use PixelLab conversion/redraw at the target resolution; use its correction
  or bounded inpainting tools for dirty edges. Generation holds still apply.
- [ ] Preserve alpha and intentional silhouette pixels. Remove accidental
  disconnected specks, terrain mats, neighboring fragments, halos and clipped
  edges by reviewing the object itself. Never globally delete green pixels,
  blur/smooth/enlarge the export, or merely resize soft art and call it crisp.
  Nearest filtering cannot repair already blurry source artwork.
- [ ] Inspect the exact RGBA PNG at 1x and nearest 4x on light, dark and actual
  ground backgrounds. Check interior pixel clusters as well as the outline.
  Tiny intended detached details or translucent effects require specific
  recorded reasons; a generic blanket exemption is insufficient.
- [ ] Use lossless Godot import, no mipmaps and inherited/explicit nearest
  filtering. Package the whole object as a reusable scene with a reviewed foot
  anchor, feet sorting and an authored collision base. Canvas/foliage height
  is not the solid footprint. Align full/depleted/damaged variants exactly.

## 3. Place against actual geometry

- [ ] Reuse the complete scene. Preserve native scale; specify the actual
  profile density. Do not compensate for a poor source with stretched art.
- [ ] Keep each physical base inside the floor and map bounds and outside
  walls, other props, water and sealed areas. Check transformed shapes, not
  just the anchor. A canopy can deliberately overhang; the base cannot.
- [ ] Keep doorways, arrival/exit points, main lanes and room centers clear.
  Retain the existing route width; 48px is a useful two-body lane for this
  game's 24px actor, not permission to narrow a wider established route.
- [ ] Prove exact interaction approaches and transitions remain reachable via
  32px shared-grid centers with full-body sweeps and diagonal corner protection.
  A point near an interaction being reachable is insufficient. Add anchors for
  every affected station, resource, portal and branch; add alternative loop
  anchors/lanes where that route must be retained. Connected endpoints alone
  do not prove all floor cells or an undeclared side route remain reachable.
- [ ] Test the actual scene after physics registration; clear/rebuild grid
  caches after moves. Reject an inconclusive bounded path search. Never
  auto-clamp, move a prop/player or change gameplay to hide a failed check.

## 4. Run the reusable checks

`tools/worldbuilding/example.json` is a working **lab example**, not a certificate
for an installed map. Copy its contract to a small task record and replace its
scene, bounds, props, anchors, routes and source assets with the actual change.
Use an editable content scene with its real terrain/walls/props, including
parent transforms. Do not run login/combat scenes just to inspect geometry.
All coordinate arrays are **world pixels**, including bounds and grid origin.
Set `world_pixels_per_source_pixel` per asset (default 1; e.g. 0.75 only where
the selected profile actually uses it). List every changed prop's texture.

From the repository root, using the installed Python/Pillow and Godot 4.5.1:

```powershell
& $PythonExe tools/worldbuilding.py --manifest <task-contract.json> --godot $GodotExe --report <outside-repo>/placement.json
& $PythonExe tools/worldbuilding.py --self-test --godot $GodotExe --report <outside-repo>/validator-tests.json
```

The placement check reads native PNGs/import settings and the installed scene's
actual static shapes. It rejects wall/peer overlaps, bases outside the floor,
blocked exact anchors, disconnected required routes and narrow reserved lanes.
It binds the actual installed sprite PNG, world density and foot anchor to the
source contract, and checks effective inherited nearest filtering.
The loaded texture's dimensions and visible RGBA pixels must match the current
source PNG, so an old imported cache cannot pass against a newer clean source.
Negative fixtures deliberately demonstrate those rejections with canonical ore.
It never edits the art or scene. The report lists precise issues and remains
`rendering_verified: false`. Self-tests certify the tool, not an area.

Asset records require `texture`, `native_size`, `anchor`; optional
`min_component_pixels` defaults to 3. `alpha_reason`, `edge_reason`, and
`components_reason` are explicit, visible review exceptions for the corresponding
heuristics. Small-component and alpha checks are leads: they cannot discover
every opaque blurry pixel, missing object face or wrong perspective.

Contracts use `schema_version: 1`, a `.tscn` `scene`, rectangular `bounds`,
`grid_origin`, nonempty `props`, at least two named `anchors`, and at least one
named `routes` entry with two or more points and `width >= 24`. Each blocking
prop must have enabled static collision on world layer 1; a deliberately
nonblocking decoration needs `blocking: false` and a specific `reason`.
`floor_polygon` optionally supplies the actual irregular ground boundary; a
rectangular map bound alone cannot prove a base sits on walkable terrain.
Always supply it when walls/collision alone do not describe the floor edge.
The Python combined command additionally requires nonempty `assets`.

Current scope: passive content scenes with standalone Sprite2D PNG props and
static bases. Select individual reusable PackedScene prop instances, never an
entire Props folder that could hide peer overlaps. The command checks script
dependencies before loading content, including custom Resource constructors.
Rectangle/convex bases use their transformed polygons; circles
and capsules use conservative transformed bounds for floor containment and
their exact physics shape for overlap. This can reject a curved base very close
to an irregular floor edge. Scripted content, atlas/region/sheet/animated props
and other shape types fail clearly and require a deliberate validator extension
plus the relevant runtime integration test. Do not bypass the gate with a fake
passive scene or unrelated PNG. Headless validation does not replace gameplay
review of scripted interactions or real 4x rendering.

## 5. Observe the real game and record acceptance

- [ ] Import/parse with the installed engine and run relevant existing area,
  grid, interaction and ore-library regressions. Inspect error output as well
  as exit codes. Save generated evidence outside Git.
- [ ] Save and inspect a **real Godot render at Camera2D zoom 4x alongside the
  player**, plus normal gameplay zoom. Check source crispness, wall seams,
  visual cut-ins, ground contact, foot depth sorting and approach visibility.
  Test walking/click paths through the changed area, close to each base and
  doorway; test transitions and affected interaction/state variants.
- [ ] Inspect both the physical debug overlay and normal artwork. Physics does
  not certify that a prop visually cuts into a wall or floats above the floor.
- [ ] Record asset IDs/hashes, contract/report path, scene revision, render
  evidence and what was visually inspected. Keep **automatic checks**, **visual
  approval** and **installation** separate. A green machine report never grants
  image approval, resumes a hold or certifies an unchanged legacy area.
- [ ] Any missing check or evidence keeps the change pending. Fix within scope,
  rerun affected tests and review before calling worldbuilding complete.

Task record minimum: request/profile; reused/generated sources and native
size/density/anchor; changed nodes/world rectangle; floor/collision/route
contract; automatic results; 1x/background and real 4x visual evidence; review
and installation statuses; remaining defects/holds; next action.
