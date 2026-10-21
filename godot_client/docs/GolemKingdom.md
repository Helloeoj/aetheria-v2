# Golem Kingdom and cave travel

The Golem Kingdom is an independent dungeon scene at
`res://scenes/GolemKingdom.tscn`. It has its own camera, movement bounds,
collision, and editable map content. It is not an extension of Valtheiris's
world coordinates.

## Enter and return

The overworld cave is beside the western branch of the northern woodland
road. `EastOutskirtsLayered.tscn` instances `GolemCaveEntrance.tscn` at
`(128, -2520)`. A short path joins its approach to the existing woodland road.
The cave artwork and its rock collisions move together with that instance.

- Left-click the cave to enter. If necessary, the character walks into range
  before the loading transition starts.
- Right-click the cave for **Enter Golem Kingdom** and **Walk here**. Walk here
  approaches the cave without entering. A different movement command cancels
  a queued entrance interaction.
- Arrival uses `SpawnPoints/EastCave` inside the pictured eastern cave mouth.
- The dungeon's eastern exit has the same interaction options and returns to
  the overworld's `SpawnPoints/GolemCaveReturn` at `(128, -2430)`.

There is no automatic teleport simply from standing on an entrance. Arrival
markers are outside the interaction geometry and on player-sized clear ground.

## Loading and character state

The `SceneTravel` autoload owns the running session's existing `PlayerState`
and skill-training session. It preserves inventory, equipment, quiver, gold,
skills, XP, health, mana, and selected spell while scenes change. Initial
health, testing levels and starter supplies are initialized only for a new
character. This is in-session continuity, not a new disk-save system.

Transitions show a fade/loading overlay, block input while loading, and load
the destination on a background loader before replacing the old map. Nested
resource subthreads are disabled for compatibility with Godot 4.5.1 on the
installed Windows renderer. A failed load restores the departing area. Held
movement, queued interactions, and combat targets are cleared when changing
areas. Dead characters and active fishing cannot initiate travel.

`CavePortal` exposes the destination scene, destination spawn ID, safe approach
offset, interaction radius and click polygon in the Inspector. `WorldInteraction`
uses these for both pointer shortcuts and context-menu actions. Portals are
restricted to the currently active map.

## Editing the dungeon

Open `GolemKingdomContent.tscn` for the five terrain TileMapLayers and 249
individual foreground objects. Art remains aligned at integer 3× scale,
making the area 3762 × 3762 world pixels. Ground, lava, falls, cavern rock and
entrance light are paintable; buildings, walls, bridge parts, stairs and props
retain their separate foot anchors. Keep bridge decks and stairs on the ground
draw plane, and solid object bases on the shared actor depth plane.

The content has authored terrain barriers and object footprints. Painting
terrain does not automatically update these collisions. See
`Assets/Maps/GolemKingdom/README.md` for the art and collision editing details.
No golems or other actors are baked into the artwork.

## Validation

With the installed Godot executable, run from the repository root:

```text
Godot --headless --path godot_client res://scenes/dev_tools/scene_travel_unit.tscn
Godot --headless --path godot_client --script res://scripts/dev_tools/cave_portal_unit.gd
Godot --headless --path godot_client --script res://tools/golem_map_smoke.gd
Godot --headless --path godot_client res://scenes/dev_tools/golem_portal_integration.tscn
```

The integration test exercises projected mouse clicks and actual context-menu
buttons through repeated real scene replacements, physical walking, safe
arrival positions and exact character-state retention. Optional `--capture`
and `--output=<absolute directory>` user arguments write GPU-rendered evidence
outside the project. Tests and GPU renders also verify that the dungeon's
assembled artwork matches the approved image without pixel changes.
