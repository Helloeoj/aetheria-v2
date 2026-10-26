# Approved image to playable map

User-established process, 2026-10-25. Applies to new map sections and substantial
area redesigns throughout Aetheria. It does not authorize generating an area,
changing an approved layout, or resuming a held asset batch by itself.

## 1. Discuss the area with the user

Use the user's text and supplied images to establish what the area contains,
how it connects to the world, and what the player can walk through and interact
with. Read only the relevant art profile and reusable asset entries.

Record the established camera angle, style references, native image density,
world dimensions, stable map origin, entrances/exits, important landmarks,
walkable floor, obstacles, and intended interaction locations. Clarify only
missing choices that materially change the design. Existing references govern
the angle; do not substitute a scenic perspective that cannot support play.

Design for the actual character footprint and shared 32-world-pixel gameplay
grid from the outset. The character's 64px source art is not its collision size
or a 64px gameplay cell. Art profiles may use other native cell sizes/scales.
See [HiddenGridMovement.md](../HiddenGridMovement.md) for movement rules.

## 2. Generate the whole-map image as a usable world

Generate the agreed area at the established angle using the discussion and
references. This image is intended to become the map after decomposition and
assembly, not merely inspire a different map later. Reuse established materials
and props where appropriate; list genuinely missing assets.

Make traversable space, doors, bridges, stairs, passage widths and interaction
approaches readable and physically plausible at the chosen world scale. Allow
clearance for the 24px body, tile centers and swept steps, including diagonal
corner clearance. Plan reachable centers rather than relying on visually open
but grid-incompatible gaps. Avoid ambiguous painted crossings or stairs that
cannot be represented by the planned floor/transition model.

Keep the artwork environment-only: no baked characters, NPCs, enemies, golems,
animals or creature sprites. No visible gameplay grid, labels or editor marks.
Retain original generation output, prompt/settings and image-to-world mapping.

## 3. User approves or rejects the image

Show the whole-map candidate. The user approves it or requests changes; return
to step 2 until approved. Record the exact approved image/version and keep that
master unchanged. Do not proceed to final decomposition or scene implementation
from an unapproved candidate. Discussion and feasibility analysis may happen
earlier, but generation/installation holds remain in force.

Image approval establishes art/layout intent; it is not evidence that collision,
pathing or the finished scene has passed gameplay validation. If later analysis
reveals an incompatible passage or interaction, explain it and return for a
bounded revision when the approved layout must change. Never silently widen a
doorway in collision only, shift geography, or block an intended route.

## 4. Analyze and separate ground and reusable props

Use the approved image to identify ground, floor boundaries, structures,
walk-behind surfaces, obstacles and interaction props. Prefer complete individual
props over whole flattened object layers: trees, rocks, furniture, columns,
gateway pieces and similar objects should be reusable scene assets where useful.
Ground/continuous terrain may remain in appropriate layers; do not split every
pixel into a prop or flatten the assembled map and re-extract existing assets.

Each prop needs a complete silhouette, true transparency, native size, reviewed
foot/root anchor, placement and depth-sorting behavior. Keep floor beneath it
clean so it can move or be reused. Covered floor or hidden object portions cannot
always be recovered exactly from a flattened image: repair/regenerate only those
bounded missing parts with the approved reference, preserving visible layout and
style. Do not claim a flat source contains unavailable hidden pixels.

Record collision footprint separately from artwork bounds. Tall art need not
block its entire rectangle; a walk-behind crown/roof is distinct from its base.
Reuse existing props first and generate only missing pieces. Ground shadows,
terrain mats and neighboring fragments must not contaminate reusable cutouts.
Follow [RECIPES.md](RECIPES.md) for extraction, import and preservation checks.

## 5. Author tile paths and implement the full map scene

Build the area's collision and traversal meaning from the approved whole layout
and the actual assembled props. Images guide authoring; pixel colors alone are
not authoritative walkability. Keep ground, props, collision, interaction anchors
and actors separate. Recompose the approved layout in the active Godot project
with appropriate feet-based depth sorting and real floor/portal connections.

Use the shared hidden 32px movement/AoE lattice and stable map origin, regardless
of native art-cell size. Geometry-derived clearance, swept connections and
diagonal corner prevention must reflect the installed collision. Do not invent
a separate per-map movement size or a second spell grid. Objects may remain
off-grid: route to reachable centers within their existing interaction ranges.
AoE uses that same lattice and shared configurable footprint calculation;
provisional spell sizes and existing wall behavior remain unchanged.

Validate before activating grid movement in the area:

- Authored arrivals and saved positions can be placed safely without rounding
  through walls or moving the user onto another floor.
- Entrances, exits, rooms and intended routes connect; narrow passages admit
  the full body and tile-center travel, not just a point-sized route.
- Fishing, cooking, mining, pickups, crafting, portals and other planned
  interactions have valid approaches and retain their original interfaces.
- WASD/arrows and point-and-click work smoothly; enemies and auto-chase obey
  the same geometry; offline and server-authoritative online behavior agree.
- Occlusion, foreground/background ordering and seams match the approved image
  at gameplay zoom; actors can walk behind props without walking through bases.
- Movement and spell footprints use the same cell origin. Development-only
  inspection may show cells; the normal game keeps the grid invisible.

Run relevant existing tests plus actual scene/input/path checks. Compilation or
an image composite alone is not gameplay validation. Report tested routes,
incompatibilities, remaining visual work and area-adoption status honestly.
Commit/push only completed authorized task changes, preserving unrelated work.

## Whole-game adoption, not a claim of finished areas

This process is the standard for future sections across the entire game.
Existing maps require area-by-area completion and validation, not an automatic
global switch. Golem Kingdom currently adopts the grid against its existing
geometry, but its full art layering/collision design is not thereby finished or
approved. The user subsequently approved a collision-only Tavern exception:
block the whole hearth/seating island, preserving every artwork pixel. With
that exclusion and its fixed `(8,0)` map-grid origin, Tavern circulation now
passes grid adoption. This is not permission for a visual redesign. Preserve
existing Catacombs work and its separate native navigation/art scale. No area
art, collision or gameplay is redesigned by saving these instructions.
