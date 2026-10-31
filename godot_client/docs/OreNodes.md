# Place ore nodes on the map

The **Ore Nodes - Full and Depleted** palette contains the game's ten reusable
ore/catalyst props: Copper, Tin, Iron, Coal, Silver, Gold, Mithril, Adamantite,
Runite and Blackstone. Each has a full and depleted stamp. Every node uses the
same rock shape; mineral streak colors distinguish the ore. Tin now follows
this shared design too. Bronze is an alloy, so there is no Bronze node.

## Stamp a node in the existing map

1. Open `res://scenes/ValtheirisWorldContent.tscn` in Godot's 2D editor.
2. Select the **Rocks** layer (the **Props** layer also works).
3. Open the bottom **TileMap** panel. Select source **2**, named
   **Ore Nodes - Full and Depleted**.
4. Choose a named ore scene. Full/depleted variants are adjacent. Use **Paint**
   and click the map to place the complete prop.
5. Right-click to erase a stamp. Paint the other state over the same cell to
   replace it without moving its base. Save the scene normally.

No asset regeneration or world-merge command is needed. Existing map contents
are preserved; installing this library did not place any nodes on the world.

## Other maps and direct placement

For another map's `TileMapLayer`, use
`res://Assets/Tilesets/OreNodes.tres`. Its source **0** provides the same twenty
stamps. The world palette uses source **2** because **0/1** already contain the
original and wilderness objects.

For direct scene placement, drag a named `.tscn` from
`res://scenes/MapProps/OreNodes/` into the map. Enable **32 x 32** grid snapping
and retain native scale **1**. Place under the map's normal y-sorted object
parent at Z index **0**. The scene carries its artwork, foot anchor and physical
rock-base collision together.

## Spacing guide

Place nodes **against room boundaries**, with access from the room. Keep room
centers, entrances and main walking routes clear. Do not scatter nodes across
the middle of a room. Verify the physical bases and shared-grid routes after
placement; an empty-looking gap in the image does not prove actor clearance.

Use **96 world pixels / three grid cells between node centers** for compact,
RuneScape-inspired ore clusters. Leave clear access along the south/front side.
Use **128 pixels / four cells** along walking routes so a full character-width
path fits between physical bases. These are Aetheria placement guidelines,
not a measured copy of RuneScape's map. Keep busy entrances and main paths clear.

The **96 x 96 world-pixel** canvas is separate from the **32 x 32** placement grid.
Current sprites are **128 x 128 native pixels**, with image anchor **(64,96)**
and Visual scale **0.75**. Keep the scene root at scale **1**: its world canvas,
world anchor **(48,72)** and paired base colliders are unchanged. Full/depleted
states stay aligned. Do not shrink the prop into one grid cell or enlarge it
to compensate for its higher source resolution.

## Canonical library and scope

Whenever an ore node is requested, reuse this library's named prop. Do not paint
a substitute random rock cluster or generate a replacement unless explicitly
asked. The pairing, texture paths, scene IDs, anchors and spacing are recorded
in `res://Assets/MapTiles/OreNodes/manifest.json`.

Runtime `Detail128/` PNGs are byte-identical copies of
`art_sources/ore-nodes/detail-v1/`. The original 96px art, PixelLab operations
and superseded different-shaped tin remain preserved. The detail revision uses
one restored host and one embedded-vein template; mineral colours retain the
original palettes. All 20 states share alpha, all depleted states are identical,
and non-mineral host pixels are identical. Exact prompts, raw inputs, source
references and registration are saved with the revision. Rebuild into a new
empty folder using `python tools/build_ore_clarity.py --output <folder>`;
`tools/install_ore_clarity.py` checks the complete family before installation.
Nearest filtering, lossless import, no mipmaps and real Godot 4x review retain
the character's detail density. Automatic checks and user artwork approval
remain separate.

These are placeable visual props with physical bases. This library does not
implement mining rules, levels, tools, rates, drops, respawns, item definitions
or smelting recipes. Those require the user's gameplay specification.
