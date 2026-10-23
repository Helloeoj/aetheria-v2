# Aetheria

Current private repository: [Helloeoj/aetheria-v2](https://github.com/Helloeoj/aetheria-v2).
The active Godot 4.5.1 project is `godot_client/project.godot`.
See [Development synchronization](docs/DevelopmentSync.md) for the required
review, validation, commit and push workflow at the end of coding tasks.

The active project is a GDScript port of the existing Python implementation.
The original Python files remain under `legacy/python/` as a reference archive.

Open `godot_client/project.godot` with Godot 4.5.1 and press F5. The entry scene
is account login. On Windows it starts the local account/database/world services;
create a username/password and log in to play a saved character in the shared,
server-authoritative East Outskirts. See
[Online accounts and worlds](godot_client/docs/Networking.md) for setup,
persistence, capacity configuration and tests. For the invite-only PC-hosted beta,
launcher, free public endpoints and release controls, see [Closed beta](docs/ClosedBeta.md).
Choose **Developer sandbox — unsaved testing** on Login for the original F5/F6/F7,
K and P test controls. Sandbox experiments do not change saved online characters.

The layered East Outskirts map includes imported character sprites,
health bars, tick-based combat and target controls. Directly opening map/developer
scenes runs the offline test sandbox, including developer menus; those menus are
disabled in the online game. Player and monster movement uses the map's physical edge,
river, rampart, tree-trunk, and rock collisions; attacks and projectiles check
the same geometry. The earlier grid-only test remains in
`godot_client/scenes/main.tscn`.

The item and monster registries, world points, named loot tables, and equipment
set definitions are carried over as data under `godot_client/data/`. The
curated loot tables retain the item names from Python. Names missing from the
master item registry remain unresolved.

## Controls from the Python client

- Hold **W/A/S/D** to move.
- **Left-click** selects a monster without attacking. **Space** starts melee or ranged attacks against the selected enemy; it does nothing without a selection.
- **Right-click** opens a small context menu: monsters offer Attack / Walk here, ground items offer Pick up / Walk here, backpack items offer Equip / Drop, and worn equipment offers Unequip into the backpack. Worn equipment cannot be dropped directly.
- **T** selects the next monster; **U** clears the target.
- **F5** opens the monster spawn menu; **F6** opens the item menu; **I** opens the
  tabbed character journal (Inventory, Skills, Spells, Equipment, Combat).
- **K** toggles the side practice panel for skill levels and full health restoration.
- **H** eats the selected quick food; choose a species in the journal with
  **Set quick food [H]**. Move caught fish from the Fishing Pale into the backpack
  before eating. The HUD shows quantity, healing, and cooldown.
- **F7** opens the sprite viewer. Choose a character, facing, and action, test hit
  flashes and target rings, or spawn the selected creature into the game. The
  game pauses while the viewer is open. **PageUp/PageDown** browse the F5 list.
- **Q/R** browse unlocked spells; **E** casts the selected spell.
- **Escape** closes the open menu.

The sprite library contains all 23 supplied character variants and maps them to
the player and 25 monster definitions. Equipping **Iron Longsword** displays the
supplied sword-bearing player. Missing action directions keep the matching static
facing; attacks without animation frames use a brief movement cue. Imported art
and the repeatable import workflow are described in
[`docs/SpriteIntegration.md`](docs/SpriteIntegration.md).

The character starts at combat level 1, with Attack, Strength, Defense, Range,
and Magic at level 1 and Health at level 10. Combat level reaches 150 only when
all five combat skills reach 100; Health does not contribute to that rating.
For full-spellbook testing, enable `max_skills_for_testing` on the main scene's
controller to start all skills at 100 and combat level at 150. The option defaults
to off. See [`godot_client/docs/SkillProgression.md`](godot_client/docs/SkillProgression.md)
for progression rules. The spell roster and unlock schedule are recorded in
[`godot_client/docs/CoreSpellbook.md`](godot_client/docs/CoreSpellbook.md).

The downloadable standalone launcher is a later packaging step. This migration
keeps the archived source behavior as its scope.
