# Valtherian Mines — artwork/layout draft

The user requested an original Edgeville-inspired dungeon for both fighting
monsters and mining, with its **own east-facing entrance beside Valtheiris's
city wall**. These are first artwork candidates, not an installed area.

## Candidates

- `unapproved/whole-map-v1.png`: untouched 1086×1448 whole-map draft. A winding
  spine connects approximately eight main chambers/gallery spaces and two
  return circuits. The sole entrance approaches from the east in the lower-right
  portion. Stone, tan floor, amber lamps and restrained teal accents follow the
  existing mine reference. No characters, creatures or ore props are baked in.
- `unapproved/entrance-east-v1.png`: native 256×192 PixelLab RGBA canvas,
  109×91 visible silhouette, scale 1. The open mouth faces right/east. One
  connected opaque silhouette, binary alpha, no disconnected specks. A real
  Godot 4× preview with the original character was inspected beside the existing
  wall; this preview adds no persistent scene/portal/collision.

Exact generation prompts, native dimensions, hashes, service IDs and separate
review/installation statuses are in `manifest.json`. Originals remain unchanged.
The larger entrance revision is retained only in the supporting task as a
rejected study: it ignored the native canvas and has edge artifacts. It must
not be resized and called a finished prop.

## Proposed use of the layout

Keep the entrance workings as a clear arrival/junction space. Use the larger
central and northern chambers for combat, and peripheral western/eastern
galleries for mining. Keep the through-routes open, with canonical ore scenes
placed beside room boundaries after the image and placements are reviewed.
These room roles are the builder's proposal; monster types, populations, levels
and the final ore roster have not been chosen by the user.

The proposed exterior spot is northeast of the wall's northern cap. A compact
visible envelope beginning at world (240,-92) avoids existing opaque prop art
in read-only scouting. Keep the wall, gate road, trees and the existing Bracken
Mine entrance. Exact final footprint, east approach and reciprocal portal
arrival must be tested against the actual assembled source before installation.

## Current checkpoint

**User whole-map image approval is pending.** Follow
`godot_client/docs/map-art/PLAYABLE-MAP-PIPELINE.md`: approve/revise the whole
image before final decomposition or scene implementation. The tool returned a
smaller native map than requested; do not enlarge it to pretend it has more
detail. Confirm the native world extent, floor and room widths at the next
stage, and return for a bounded revision if an intended route is incompatible.

No runtime game files, world placements, ore/mining rules, combat systems,
character saves, current maps or existing entrances were changed. The final
`tools/worldbuilding.py` scene/placement contract and real installed-map 4×
review remain pending; source previews and preliminary route scouting are
not a placement certificate. PixelLab currently has no remaining generation
credits for further native revisions.
