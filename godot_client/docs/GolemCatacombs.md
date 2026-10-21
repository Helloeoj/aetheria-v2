# Golem Catacombs — Floor One

`res://scenes/CatacombsFloor01.tscn` is the independent first floor. Enter
through the existing southwest corridor door in Golem Kingdom, above its
descending stairflight. This is the door shown in the catacombs art reference;
the royal hall remains a separate building.

Left-click that door to approach and enter. Right-click offers **Enter Golem
Catacombs** and **Walk here**. Walk here never enters. The bottom-left exit
inside the catacombs uses the same deliberate interactions to return to
Golem Kingdom. Standing on either entrance does not trigger travel.
`SceneTravel` keeps the existing character, inventory, equipment, skills,
earned XP and training session through both transitions. The return marker
is on the clear landing outside the kingdom doorway.
The first-floor arrival is at `(1550, 6860)`, on clear ground in front of the
exit gateway, so its foreground art cannot hide the arriving character.

Only Floor One is installed. The northeast descent is visibly marked
**Sealed descent**, has no travel interaction and does not reference a missing
second or third floor.

## Editing

Open `CatacombsFloor01Content.tscn` to edit the environment. Ground,
FloorDetails, VolcanicRock and Walls are separate TileMapLayers; props remain
separate scene objects. The content's 0.75 scale displays each native artwork
pixel at the same density as the actor. A native 32-pixel tile therefore
occupies 24 world pixels. The padded independent world is 9216 × 7200.
No characters or creatures are baked into the art.

The northern gallery retains its island. Both islands removed from the
Great Crucible Cavern are open floor and have no remaining collision.

The approved overview and the bounded pillar edit are saved under
`art_sources/golem-catacombs-floor01/`. The playable assembly uses native
reusable materials rather than enlarging the low-resolution overview.
`tools/build_catacombs_floor.py` rebuilds the TileSets, content scene, collision
mask and navigation data together. Run it from the repository root with Python,
Pillow and NumPy. `--preview <outside-repository PNG>` optionally writes an
overview for inspection. FloorDetails starts empty for future local decals;
Props contains individual native braziers, stairs and the exit gateway.

`Assets/Maps/GolemCatacombs/Floor01/layout.json` records the walkable floor
cells, entry, descent and rooms. Generated physical barriers follow that
floor mask and solid footprints. `catacombs_navigation.gd` routes on the same
24-pixel cells, with a full-cell margin around barriers and no diagonal
corner cutting. A physically clear start or exact destination inside that
extra margin connects to a nearby safe cell only after checking the actual
body can sweep between them without touching a barrier. When changing floor
topology or solid footprints, update
the layout mask and generated collision together. Painting tiles alone does
not change navigation. Preserve manual scene edits before regenerating.

The floor's camera starts at 3× and clamps the mouse wheel to 3×–4×.
The area-specific `catacombs_floor.gd` subclass leaves other areas' camera
settings intact.

## Validation

From the repository root with Godot 4.5.1:

```text
Godot --headless --editor --path godot_client --quit
Godot --headless --path godot_client res://scenes/dev_tools/catacombs_integration.tscn
Godot --headless --path godot_client res://scenes/dev_tools/scene_travel_unit.tscn
Godot --headless --path godot_client --script res://scripts/dev_tools/cave_portal_unit.gd
Godot --headless --path godot_client res://scenes/dev_tools/golem_portal_integration.tscn
```

The catacombs integration exercises real projected pointer clicks and context
menu buttons, a round trip, exact character state retention, clear arrival
points, camera limits, room routes with the actual player collider, barriers,
corner clearance and the two cleared island areas. Optional `--capture` and
`--output=<absolute directory>` arguments capture rendered evidence outside
the project.
