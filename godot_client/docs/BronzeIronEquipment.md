# Bronze and iron in the existing Godot test

All 34 bronze/iron equippables now use the same `ActorSprite.set_equipment()`
and `CharacterAttachmentRig` registry as the existing Adamantite Kiteshield.
No separate test project or gameplay scene is required. Inventory, stats,
map movement, attack lunge, tint and actor world sorting are unchanged.
The Adamantite Kiteshield scene and its original PNGs/pivots are unchanged.

## Inspect and equip

- F7: select **Peasant**. Weapon and shield pickers now contain both tiers.
- Use **Bronze armor** / **Iron armor** presets, or select an armor slot and
  an individual piece. **Clear armor** removes that preview loadout.
- F7 affects only the preview character. Choose Idle/Walk/Attack and any facing.
- F6 grants items and attempts to equip the real player through the existing
  item-ID menu. Bronze has no level requirement; Iron weapons require Attack
  10 and Iron Armor requires Defense 10. Locked grants stay in the backpack.
  `I` opens the journal to inspect, equip, and remove gear.

| Piece | Bronze ID | Iron ID |
| --- | --- | --- |
| Dagger | 1 | 23 |
| Shortsword | 2 | 24 |
| Longsword | 3 | 25 |
| Mace | 4 | 26 |
| Warmaul | 5 | 27 |
| Bow | 6 | 28 |
| Crossbow | 7 | 29 |
| Magic Staff | 8 | 30 |
| Magic Wand | 9 | 31 |
| Helmet | 10 | 32 |
| Platebody | 11 | 33 |
| Platelegs | 12 | 34 |
| Kiteshield | 13 | 35 |
| Square Shield | 14 | 36 |
| Cape | 15 | 37 |
| Ring (invisible) | 16 | 38 |
| Necklace | 17 | 39 |

The Adamantite Kiteshield remains item **106**. Two-handed weapon restrictions
still come from the existing inventory system. Rings occupy the game's ring1/
ring2 inventory slots but intentionally create no visual node.

## Fitted layers

Assets are in `Assets/Equipment/fitted_bronze_iron/`; independent item scenes
are in `scenes/equipment/fitted/`. The real iron longsword replaces the previous
test-sword registration, while the old reference scene is retained on disk.

`FittedEquipmentVisual` is a normal registered item scene beneath the existing
hand/head/chest/waist/back marker. Its independent articulated parts use native
Bone2D attachment points driven by the same current animation and frame. Hand
items keep the live game's existing hand coordinates; the other parts convert
the 80px fitted-pack padding back to each source frame's native canvas.

`FittedEquipmentBody` hides only the original sprite's own draw when fitted head,
chest or leg armor needs it, and supplies masked underbody/foreground layers.
The source SpriteFrames and their resource paths are retained for existing socket
tracking. Removing armor restores the original draw immediately. Head/hair and
lower tunic are suppressed where replaced; limbs and necklaces layer over armor.
All layers retain Z=0 inside the existing actor subtree to preserve map sorting.

Idle and walking cover all eight directions. The game's existing short attack
lunge remains; this import does not invent attack/casting/bow-draw animation.

Optional developer arguments open this SAME game's existing F7 preview:
`-- --equipment-review=bronze` or `-- --equipment-review=iron`.
`--equipment-proof=<absolute PNG path>` saves a one-time Godot viewport image.

## Verification

Run the real project's headless scripts:

```text
Godot --headless --path godot_client --script res://scripts/dev_tools/attachment_smoke.gd
Godot --headless --path godot_client --script res://scripts/dev_tools/shield_attachment_smoke.gd
Godot --headless --path godot_client --script res://scripts/dev_tools/fitted_equipment_smoke.gd
```

The fitted checks exercise all 32 visible items across 72 poses, invisible rings,
real PlayerState equipping, both game scenes, F7 presets, clothing restoration,
necklace-over-chest order, and coexistence with the original adamantite shield.
