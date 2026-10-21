# Aetheria Godot project

This folder contains the GDScript conversion. Open `project.godot` in Godot 4
and press F5 to run `scenes/EastOutskirtsLayered.tscn`. The map scene includes
the combat test character, health bars, developer menus, and the layered map.
`GameData` loads the converted catalogs from `data/`.

Press **I** or click **Journal** to open the tabbed Inventory, Skills, Spells,
Equipment, and Combat pages. Click **Test skills [K]** or press **K** to adjust all eight skill levels and
restore health in the side panel. See
[`docs/CharacterJournal.md`](docs/CharacterJournal.md) for the controls and artwork.

Left-click selects a monster; **Space** starts melee or ranged attacks against
that selection. **E** casts the selected spell. Right-click monsters for
**Attack / Walk here**, or ground items for **Pick up / Walk here**. Pick up
approaches distant loot. In Inventory, right-click for **Equip / Drop** (and
**Drop all** for stacks); in Equipment, right-click for **Unequip**. Worn gear
returns to the backpack and cannot be dropped directly.

Fishing catches are raw and must be cooked before eating. Cooking logic is
implemented; campfire interactions await the separate firemaking work. See
[`docs/Cooking.md`](docs/Cooking.md) for recipes and integration. Select a cooked fish in
Inventory and choose **Set quick food [H]**, then press **H** or click the food HUD
button to eat. Its display shows quantity, healing, and the shared 1.8-second
cooldown. A depleted selection stays selected until you choose another species.
Each meal adds one full equipped-weapon attack interval to the remaining attack
delay; changing to a faster weapon cannot shorten a pending food penalty.
Full health, defeat, and blocked actions consume nothing. See
[`docs/FoodFishingBalance.md`](docs/FoodFishingBalance.md) for values and rules.

Scroll the mouse wheel up to zoom in and down to zoom out (1.5x–4x).
The map camera follows the character and keeps them centered, including at map
edges. Zoom stays centered on the character; developer menus and the sprite
viewer do not change the map zoom while open.

The original grid combat demo remains available as `scenes/main.tscn`. The
map test scene uses the same tick combat, target controls, and developer menus.
Its player and monsters move as physics bodies on the map. The hidden blockout
instance preserves the original collision reference; editable terrain and object
tiles now supply the live map collision. For ongoing map editing, open
[`scenes/ValtheirisWorldContent.tscn`](scenes/ValtheirisWorldContent.tscn): the
outskirts, harbor, riverside road, woodland, farm with wheat field, and roadside
tavern share one editable terrain and object layer stack. The runtime node
remains named `PlayableMapContent`. `scenes/PlayableMapContent.tscn` and the
blockout scene remain preserved references; original coordinates and collision
outlines stay fixed.
The world extends north and west to origin `(-1536, -3072)` with bounding size
`3072 × 5728`; its unbuilt southwest area is blocked. The approved sections also
have [transparent source layers](Assets/MapLayers/Wilderness/) for art editing.
See [`docs/MapEditing.md`](docs/MapEditing.md) for
terrain brushes, object tiles, collision editing, and rebuilding precautions.
Attacks and projectiles also check the map geometry. Its controls are
listed in the repository README. The Python source is kept under
`../legacy/python/` for reference.

The character sprites now include eight facing directions, supplied movement
and idle clips, attack cues, hit flashes, target rings, and death fades. Press
**F7** to inspect all 23 variants or spawn a creature. The F5 spawn list includes
the 25 monster definitions with supplied artwork; use **PageUp/PageDown** to
browse it. Equipping **Adamantite Kiteshield** (item **106**) attaches your
eight-direction shield to the peasant's left hand. **Iron Longsword** uses a
separate test weapon. In F7, select **Peasant**, choose a Shield or Weapon, and enable
**Show attachment skeleton** to inspect the sockets. See
[`docs/EquipmentSockets.md`](docs/EquipmentSockets.md) to add independent items.
See [`../docs/SpriteIntegration.md`](../docs/SpriteIntegration.md) for the asset
coverage and reimport instructions.

The spell test controls are **Q/R** to browse unlocked spells and **E** to cast
the selected spell. The character starts at combat level 1, with the five combat
skills at level 1 and Health at level 10. Enable `max_skills_for_testing` on the
main scene's controller to start all skills at 100, reach combat level 150, and
access the full spellbook. This testing option defaults to off. Combat level
equally weights Attack, Strength, Defense, Range, and Magic; Health is excluded.
See [`docs/SkillProgression.md`](docs/SkillProgression.md) for the formula and XP rules.

The current code does not include a downloadable launcher or release package;
those belong to the later standalone distribution step.

Loot and economy rules, reviewed monster tables, developer pacing estimates, and
unresolved design questions are recorded in
[`docs/LootEconomyReview.md`](docs/LootEconomyReview.md). Its economic estimates
are design notes; the game does not need to read them at runtime.
