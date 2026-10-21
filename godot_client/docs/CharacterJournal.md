# Character journal and practice tools

Open the journal with **I** or the **Journal** button at the top left. The five
tabs share one framed window. **I** or **Escape** closes it. Selecting a tab
keeps the character's current item, spell, and technique choices.

The interface scales automatically with the game window, using a 1280×720
layout as its reference. A 4K window displays the panels and controls at roughly
three times their reference size. This scaling applies only to the interface;
world camera zoom is independent. Body text uses a clear standard font at a
minimum of 16 layout pixels, with larger click targets, brighter secondary text,
and extra room for wrapped item names. Pixel lettering remains on headings and
tabs, alongside the original frames and artwork.

| Page | Controls |
| --- | --- |
| Inventory | Left-click to select an item; right-click for Equip, Drop, and Drop all for stacks. The existing detail-panel Equip button also works. |
| Skills | View all six levels, XP totals, XP sources, next-level progress, and session XP/hour. Reset session clears the measurements. |
| Spells | Inspect the spellbook, see unlock requirements and cast reliability, ready an unlocked spell, or cast it. |
| Equipment | Left-click to select a worn slot; right-click for Unequip. Read current combat stats beside the slots. |
| Combat | Select Stab, Slash, Crush, Ranged, or Magic when supported by the equipped weapon. |

The Crush label uses the existing `blunt` combat style. Spell selection uses
the existing Magic unlock checks and casting system. Combat stats and equipped
character visuals refresh immediately after changes.

Inventory and equipment cards use registered item artwork where available,
with the PixelLab category icons as a fallback.

Item details and tooltips show skill requirements. Locked Equip actions are
disabled. Weapons require Attack and catalog Armor requires Defense, with a
new tier every 10 levels. Attack and Defense cards show the unlocked tier and
the next requirement. See [EquipmentProgression.md](EquipmentProgression.md).

## Selection and right-click actions

Left-click a monster in the world to select it. Selection shows its target ring
and does not start an attack. **Space** starts melee or ranged attacks against
the selected living enemy, approaching weapon range when needed. Space with no
selection does nothing. **E** still casts the selected spell; Space does not
cast spells in Magic style. **T/U** remain alternative select/clear controls.

Health bars render above all world scenery, so trees and buildings can hide the
character without hiding its health. Character sprites retain their existing
overlap behavior, and bars follow the same camera position and zoom as before.

Right-click opens a compact menu at the pointer:

| Location | Actions |
| --- | --- |
| Monster | Attack that monster; Walk here. |
| Ground item | Pick up that stack; Walk here. |
| Empty ground | Walk here. |
| Backpack item | Equip (disabled for non-equippable items); Drop one; Drop all when stacked. |
| Worn equipment, including quiver | Unequip into the backpack. No Drop action. |

Overlapping world entities each get an action in the menu. Left-clicking a
ground item selects it without collecting it. Pick up collects within two tiles
or walks toward the item until it is in range. A stack transfers its full quantity
exactly once. F remains a nearby-pickup shortcut. Every valid catalog item can
exist as ground loot; items without dedicated ground art use their inventory art
or a category icon. Monster loot waits on the ground for collection.

Walk here cancels attacking, and WASD/arrows cancel a queued walk or pickup.
Walking uses the existing map collision and stops if blocked; it does not search
for a route around obstacles. Open menus suspend queued walking. Click outside,
Cancel, or Escape closes the context menu; the closing click cannot select or
activate something underneath. Menus stay inside the viewport, including near
the right and bottom edges. Context actions recheck item ownership and target
validity before transferring items or initiating attacks.

Only backpack copies can be dropped. Worn items must first be unequipped;
dropping an extra backpack copy does not remove the worn copy.

The integration check is `scripts/dev_tools/world_interaction_smoke.gd`, run with
`godot --headless --path . --script res://scripts/dev_tools/world_interaction_smoke.gd`.
Add `-- --capture` using a rendering-enabled Godot run to save in-game menu previews.

## Practice tools

Click **Test skills [K]** beside **Test fishing [P]**, or press **K**, to open
the right-side **Test skills** panel. It has all eight level controls and a
**Restore full health** button. **K** or its close button hides the panel.
The fishing menu also has a **Skills [K]** button. Switching to skills closes
the active fishing cast and releases its selectors before opening the controls.
Change Fishing, then press **P** to reopen fishing with the new level. Setting a level
also sets that skill's XP to its level threshold, updates combat level and
combat stats, and refreshes available spells. Restoring health also revives a
fallen test character. These are developer controls that edit the live player
state; they do not represent earned progression. Typing in a level field stops
movement and protects the game shortcuts. Escape releases the text field first.

## Artwork and sources

`Assets/UI/aetheria_frame.png` and `aetheria_icons.png` were drawn with PixelLab's
free exact pixel drawing tools. The original frame uses engraved brass, dark
blue panels, corner scrolls, and turquoise settings, with the warm adventure
menu feeling of Dark Cloud as inspiration. It retains Aetheria's pixel style.
The frame is 192×192 with 24px slicing margins. The 192×64 atlas holds twelve
32×32 icons, arranged in six columns.

The drawing recipes, previews, and PixelLab asset IDs are retained in the task
workspace's `work/ui-art` folder. No existing game artwork was replaced.

The heading and tab font is [Pixelify Sans](https://github.com/google/fonts/tree/main/ofl/pixelifysans),
distributed under the SIL Open Font License. Its license is included at
`Assets/UI/PixelifySans-OFL.txt`. Body text uses Godot's bundled fallback font.
