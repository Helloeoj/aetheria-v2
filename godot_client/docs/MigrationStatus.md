# Python to GDScript port status

The original code is preserved in `legacy/python/`. The active Godot project
uses the converted scripts and catalog data in this folder.

## Ported

- Player model, stats, inventory, equipment-slot rules, and the older duplicate player model.
- Hit rolls, actor/projectile state, tick combat, monster pursuit, and projectile behavior.
- Item, monster, world, loot, and equipment-set registries. The catalogs contain
  170 registered items, 84 monster records, 15 world tiles, and 15 set definitions.
- The Arcade client's grid rendering, movement, combat loop, targeting, health
  bars, inventory menu, item menu, and monster spawn menu.
- The prototype server's JSON message, session, world-tick, and demo-loop code.
- The two Python developer combat demos, now available as GDScript utilities under `scripts/dev_tools/`.

## Source differences to keep in mind

The archived project contains overlapping generations of code. The Arcade
entry point imports `WorldState` and monster lookup helpers that are missing
from the Python archive; the inventory menu calls an unequip function under a
name the core module does not provide. The Godot port connects those pieces to
the existing core implementations. The F5 spawn menu exposes the six monsters
registered by `aetheria_core.monsters`; the other family records are carried in
the catalog from the separate older monster files.

The pytest suite remains in the Python archive because it is test code rather
than game runtime code. Its combat cases refer to `_roll_damage`, which is
absent from the archived `CombatEngine`. Godot runtime verification has not
been performed in this workspace.
