# Peasant equipment sockets

**Update:** the fitted bronze and iron equipment pack is now registered in this
same game. F7 includes both tiers' weapons/shields, armor presets and individual
armor choices; F6 equips them through the real inventory. See
[BronzeIronEquipment.md](BronzeIronEquipment.md) for IDs and implementation notes.
The rigid-socket clothing limitation described below is addressed for these
fitted items by articulated item parts and separate masked body layers; it still
applies to arbitrary future assets without such a setup.

The playable peasant now keeps its base `peasant` artwork when equipment changes.
Your Adamantite Kiteshield is an independent item attached to his left hand.
The right-hand Iron Longsword scene uses test artwork to demonstrate weapon
attachments. The old `peasant_sword` artwork remains available in the sprite
viewer as a supplied reference appearance.

## Inspect in Godot

1. Run the project with F5, then press F7 in the running game.
2. Select **Peasant** (not **Peasant with Iron Longsword**).
3. Choose **Adamantite Kiteshield** in the Shield picker. The Weapon picker can
   separately enable the test sword; either item can be previewed on its own.
4. Enable **Show attachment skeleton** and choose a direction and action.

The preview changes only its own character. To equip the actual player, use F6,
enter item ID **106**, and press Enter to equip your shield. Item **25** equips
the test sword. Use inventory (`I`) to remove equipment.
The same asset follows the player's walking, turning, hit tint, and attack lunge.

## How this skeleton works

The supplied PixelLab export contains flattened PNG frames and animation timing.
It does **not** contain animated bone/joint coordinates. Adding a skeleton alone
would not tell Godot where a hand moves inside those images.

`CharacterAttachmentRig` therefore supplies a real Godot `Skeleton2D` with
`Bone2D` nodes driven by manually inspected per-frame coordinates. It is an
attachment skeleton; it does not deform the peasant artwork or recover the
original PixelLab rig. The attachment tracks cover all 72 supplied peasant poses:
eight idle directions and eight walking frames in each direction.

The rig is a child of `ActorSprite/CharacterVisual`, named `EquipmentSkeleton`.
Socket markers also sit beneath CharacterVisual to keep equipment immediately
in front of or behind the body without changing its world depth. They inherit
the visual's scale, attack displacement, tint, and fade. Frame and
animation changes update sockets immediately. Different PNG canvas sizes are
accounted for using the current image's dimensions and the sprite's feet anchor.

| Socket ID | Intended use |
| --- | --- |
| `right_hand` | Main-hand weapon or tool |
| `left_hand` | Shield or off-hand item |
| `head` | Rigid helmet, hat, or head accessory |
| `chest` | Rigid body ornament or attachment |
| `waist` | Belt attachment or pouch |
| `back` | Backpack or sheathed item |

The visible hand is redrawn over the test sword's grip using a five-pixel region
of the current original frame. This overlay is disabled for the shield, whose
front panel covers the hand. Far-hand items draw behind the body. Anatomical
handedness is preserved when the character turns; the artwork is not mirrored.
Occluded hand coordinates are estimates because those hands are hidden in the
source frames. Future artwork may need those coordinates refined.

## Your Adamantite Kiteshield

The supplied GIF contains eight 68x68 views with native transparency. Its frame
order is south, southeast, east, northeast, north, northwest, west, southwest.
`tools/import_equipment_gif.py` decodes these to PNGs without changing RGBA
pixels, mirroring, or resizing. `source_manifest.json` records source and frame
hashes; `--check` compares the imported pixels to the unchanged source GIF.
The green palette entry is already transparent and needs no chroma-key shader.

Assets live in `Assets/Equipment/adamantite_kiteshield/`, with the independent
scene at `scenes/equipment/adamantite_kiteshield.tscn`. Each facing has its own
grip pivot. The scene draws at half its native pixel scale to fit the peasant;
the PNGs stay at their original resolution.

`EquipmentVisual2D.set_attachment_facing()` changes artwork only when the actor
faces another direction, not when the walking frame advances. It cancels the
socket's sword grip angle so the shield keeps its authored orientation. The
registry uses `left_hand` and `grip_cover: false`. Other directional items can
reuse this script with their own textures, grip coordinates, and display scale.

## Add an independently created item

1. Create a scene with a `Node2D` root and a `Sprite2D` child. Place the grip or
   attachment pivot at the scene root's `(0, 0)`. Match the character's source
   pixel scale. For a weapon, point the blade toward negative Y, as in
   `scenes/equipment/iron_longsword.tscn`.
2. Place the artwork under `Assets/Equipment/`. Set nearest texture filtering.
   Adjust the Sprite2D position/rotation/scale inside the item scene to align
   its grip; no character sprites need to change.
3. Register the item under its exact inventory name in
   `data/equipment_visuals.json`, specifying its scene and socket:

```json
"Iron Longsword": {
  "socket": "right_hand",
  "scene": "res://scenes/equipment/iron_longsword.tscn"
}
```

4. Ensure the item exists in the gameplay item catalog if it should be
   obtainable/equippable. That catalog controls stats; `equipment_visuals.json`
   controls only appearance. Items without registered artwork retain their
   gameplay effects and display no placeholder equipment.

`main.gd` passes the player's complete equipment dictionary to
`ActorSprite.set_equipment()`. Each character creates its own item node while
sharing the scene's texture resources. Repeated refreshes reuse existing nodes.
An item can also be attached directly in code:

```gdscript
actor.set_equipment({"weapon": {"name": "Iron Longsword"}})
var hand_socket := actor.attachment_rig.get_socket("right_hand")
```

## Add a new animation or character

Author socket coordinates once for its frames in
`data/character_attachments.json`. Each pose key is its exact PNG resource path;
each socket is an `[x, y]` coordinate in that PNG's actual canvas, including
transparent padding. Do not use scaled screen coordinates. The generated sprite
catalog does not own these tracks, so reimporting artwork will not erase them.

Frames without tracks hide the attachment rig instead of displaying a stale
hand position. Other character skins are not yet rigged. A new character needs
its own tracks, after which compatible item scenes can be reused. The F7 item
pickers currently expose the peasant, your shield, and the test sword.

Rigid sockets do not provide deforming clothing, joint-spanning armor,
two-handed IK, or missing viewing-angle artwork. Those need a separate art/rig
setup. The peasant currently has no authored attack frames; its existing attack
lunge remains in use.

## Verify

```text
Godot --headless --path godot_client --script res://scripts/dev_tools/attachment_smoke.gd
Godot --headless --path godot_client --script res://scripts/dev_tools/shield_attachment_smoke.gd
Godot --headless --path godot_client --script res://scripts/dev_tools/sprite_integration_smoke.gd
```

The focused attachment test covers all 72 poses, frame/animation signal updates,
equipment reuse/removal, separate characters sharing an item asset, transform
inheritance, unsupported skins, and hurt/death/revive behavior.
The shield test also checks all eight directional images, unrotated grip
placement, sword/shield independence, item 106, inventory restrictions, and F7
preview isolation in both game scenes.
