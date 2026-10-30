# Developer monster placement

F5 and the sprite viewer use the same spawn function. Each monster appears on
an unoccupied, reachable tile center within **3 tiles (96 world pixels)** of the
character's current position. The search uses actual distance, including when
the player is between cell centers, and excludes the player's own cell.

Candidate cells and their route must fit the existing **24×24 pixel body** on
authored floor, clear current collision and map bounds, and obey ordinary
diagonal corner rules. Nearby floor behind an impassable wall is not a valid
shortcut. Repeated spawns use other free tiles rather than stack bodies.

When no valid tile exists, the menu displays a message and creates no monster,
actor, sprite or consumed spawn ID. Move to clearer ground and try again.
The existing menus, templates, sprites, combat and online permissions remain.

The real map world and authoritative regions also validate terrain when
`WorldState.register_monster_actor()` is called. Its boolean result must be
checked by spawn code before publishing a sprite/body. This keeps future world
spawners under the same floor/body rules; no new online spawn command is added.

`scripts/floor_support.gd` is the runtime floor dependency. The previous
`dev_tools/tile_floor_support.gd` path remains a compatibility alias for tile
commands/tests. Ground TileMapLayers, the tavern's complete floor image, and
an area's authored `Assets/Maps/<scene-name>/layout.json` `floor_cells` contract
are supported. Unknown floor sources fail closed. Floor cells describe world
pixels through `gameplay_cell_pixels` and `grid_origin`, not image resolution.

Tests (Godot 4.5.1, from repository root):

```powershell
& $env:GODOT --headless --path godot_client --script res://scripts/dev_tools/monster_spawn_unit.gd -- --social-no-auto
& $env:GODOT --headless --path godot_client --script res://scripts/dev_tools/monster_spawn_smoke.gd -- --social-no-auto
```

The map suite covers the tavern, outskirts, Golem Kingdom, Bracken Mine and
combat test scene, plus installed local Catacombs/Valtherian expansions. Add
`--spawn-screenshot` after `--social-no-auto` in a graphical run to save the
real 4× player/monster render to the temp folder, outside the checkout.
