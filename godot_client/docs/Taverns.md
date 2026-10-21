# Roadside tavern

The existing Royal Road Tavern in the northwest countryside is the first test
tavern. Its exterior artwork and collision are retained. The door in
`EastOutskirtsLayered.tscn` now has a deliberate `CavePortal` interaction:

- Left-click the door to approach and enter.
- Right-click for **Enter Tavern** or **Walk here**. Walking there alone never enters.
- The interior south door returns to **Valtheiris** through the same click/context
  behavior. Arrival is outside the respective doorway and collision.

`SceneTravel` retains the running player and training session, including inventory,
gold, equipment, health, mana and skill progress. Loading labels identify the tavern.

## Interior and artwork

Runtime: `res://scenes/TavernInterior.tscn`.
Editable content: `res://scenes/TavernContent.tscn`.
Approved source: repository `art_sources/tavern-v1/approved-interior-v1.png`.
Runtime texture/layout: `res://Assets/Maps/Tavern/`.

The approved 1254-square PNG is retained unchanged. It uses 0.75 world pixels per
source pixel, exactly the actor's 64px-frame/48px-display ratio. Nearest texture
sampling, lossless import and no mipmaps retain that density at maximum zoom.
An actor-free native-density GPU composition reproduced the approved RGB pixels
exactly during initial validation (zero changed pixels).

The room is one floor with a central open hearth, perimeter seating, open
circulation, an empty bartender aisle, and a separate northeast kitchen. No actors,
including the tavern master, are baked in. Physical bases block furniture/hearth;
native-texture foreground polygons sort at furniture feet against actors. The
room-specific navigation grid routes click interactions around these obstacles.

This is an exact-artwork installation: the base image still contains the furniture.
Foreground polygons provide actor occlusion, not a reconstructed clean floor.
Moving a furniture group visually requires a separate floor/art variant; moving
only its foreground polygon would leave its original appearance in the base.
Geometry and navigation share the source-space obstacles in `layout.json`.

`python tools/build_tavern_scene.py` deliberately regenerates the content scene,
layout and copied runtime PNG. It does not edit pixels. Preserve manual content
edits before running it; edit the builder definitions when changing generated
geometry so collision/navigation stay consistent. The runtime scene and scripts
are not overwritten by that builder.

## Stove and Cooking

Click the pictured upper-right stove to approach it and open **Cooking**.
Right-click offers **Cook at stove** and **Walk here**. The latter only approaches.

Choose raw fish from the backpack, then **Cook 1** or **Cook all**. The panel uses
the existing CookingSession rules: three-second attempts, current level/burn curve,
cooked/burnt outcomes, and success XP. It displays quantity, level requirement,
burn chance, progress and status. Fish still in the Fishing Pale must first be
moved into the backpack through the existing inventory workflow.

The stove is a persistent active heat source while its area exists. The center
hearth is decorative for this installation; no cookware or cooking interaction
was added there. Closing/Escape, movement/range loss, damage, invalid heat, combat
or travel cancels unfinished cooking without spending its ingredient. Completed
results remain. The modal owns world input while leaving its actual UI buttons
usable. Cooking XP also enters the existing training-session meter.

This installation does not add tavern NPCs, rest bonuses, multiplayer networking
or player trading. Those can use the room as their test location later.

## Verification

From the repository root with installed Godot 4.5.1:

```text
Godot --headless --path godot_client res://scenes/dev_tools/tavern_integration.tscn
```

The test covers actual pointer dispatch, both door entry choices, non-entering
Walk here, repeated scene swaps, safe arrival/return, persistent character data,
stove approach around furniture, bartender-aisle access, physical hearth collision,
modal input, one/all cooking, rewards and cancellation on close/damage/travel.

Run it without `--headless`, adding `-- --output=<absolute evidence directory>`,
for GPU-rendered overview, door, stove UI and maximum-zoom character comparisons.
`--script res://scripts/dev_tools/tavern_art_check.gd -- --output=<absolute PNG>`
renders the actor-free scene at native source density for pixel comparison.
Keep output outside the repository and inspect stderr, not just the exit code.
