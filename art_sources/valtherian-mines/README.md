# Valtherian Mines — larger-room layout candidate

The user requested an original dungeon for combat and mining, with its own
east-facing entrance beside Valtheiris's wall. V3 enlarges the chambers while
preserving the liked east-to-west journey and five separate side branches.
The opaque dark background stays; the remove-background action was canceled.

## Current room and tile plan

`planning/tile-layout-v3.json` uses the game's fixed 32-world-pixel cells and
origin (0,0). The proposed world is 192×104 cells (6144×3328 pixels). More space
comes from more native tiles; player and prop sizes stay unchanged.

| Space | Clear floor in cells | Clear floor in world pixels |
| --- | --- | --- |
| West terminal | 24×20 | 768×640 |
| Side combat chambers | 20×16 to 22×18 | 640×512 to 704×576 |
| Mining galleries | 18×14 | 576×448 |
| Main-route combat halls | 22×16 and 24×16 | 704×512 and 768×512 |
| Main corridors | 6 wide | 192 wide |
| Branch corridors | 4 wide | 128 wide |

These are clear rectangles before prop placement, with an additional one-cell
perimeter allowance for uneven stone. Junctions are farther apart so enlarging
the chambers does not join the branches into a compact cluster. Roles are
proposals only; no monster populations, ore roster or skill rules were chosen.

Run `planning/build_tile_plan_v3.py` to reproduce the JSON and SVG. It verifies
5498 cardinally connected floor cells, every declared room rectangle, and
three main-route cut gates that prevent branches bypassing early/middle/late
progression. These are structural checks, not installed-map collision tests.
The west combat hall has a 64px rock band beside the adjacent main passage
(cells x99–100,y60–64). Check the actual native wall silhouettes there during
assembly; a universal 96px rock-separation pass is not claimed.

The two `planning/*tile-scale-4x.png` images show the minimum combat and mining
rooms on a diagnostic grid with the original character, rendered by Godot at
4×. Reproduce them with `planning/render_room_scale_v3.gd` using the active
Godot project. This is a room-size demonstration; the flat debug floor is not
the final mine art. Actors appear only in these quality checks.

## Preserved artwork and review states

- `unapproved/whole-map-v3.png`: current larger-room artwork proposal. The
  generated overview is smaller than the planned native world. It must not be
  enlarged into a runtime background or treated as proof of tile alignment.
- `unapproved/whole-map-v2.png`: the user liked its direction and branching,
  then requested larger rooms. Preserved as the style/topology reference.
- `unapproved/whole-map-v1.png`: rejected by the user for its compact room
  cluster and insufficient end-to-end progression; kept unchanged for history.
- `unapproved/entrance-east-v1.png`: clean native 256×192 PixelLab source,
  109×91 visible silhouette. The mouth faces right/east. An actual-world,
  in-memory Godot4× preview with the original character was inspected earlier.
  Final collision, anchor and reciprocal travel contract remain pending.

Exact prompts, native dimensions, hashes and service IDs are in `manifest.json`.
Sources are copied byte-for-byte. No actors or ore nodes are baked into the map.
The larger entrance study remains rejected for production because of its
incorrect native canvas and edge artifacts. PixelLab has no remaining credits.

## Approval and installation checkpoint

**V3 whole-image approval is pending.** Follow
`godot_client/docs/map-art/PLAYABLE-MAP-PIPELINE.md` before final decomposition
and installation. After artwork approval, build native terrain on the authored
grid, use whole canonical props at their approved density and anchors, and run
`tools/worldbuilding.py` against the actual assembled scene/placement contract.
Inspect actual-map Godot4× renders with the player for crispness, wall cut-ins,
approaches, reserved paths and depth sorting before calling installation done.

No runtime game files or permanent scenes/placements were changed. Existing
Bracken Mine artwork, its 15 marked ores, entrances, city wall, roads, trees,
interfaces, saves and all gameplay are preserved. The proposed exterior entrance
spot remains northeast of the wall's northern cap; the original compact source
and exact final geometry must be tested before installing that entrance.
