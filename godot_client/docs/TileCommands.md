# Tile coordinates and teleport

Open **Developer sandbox — unsaved testing** from Login. Press **Enter**, type
a command in the existing chat box, then press **Enter** again. Chat does not
need to be connected. Commands and responses stay on your client.

| Command | Action |
| --- | --- |
| `::tele x y` | Teleport to the exact center of tile `(x, y)` in the current area. |
| `::teleport x y` | Alias for `::tele`. |
| `::pos` | Print your tile, area scene and reusable `::tele` command. |
| `::coords` | Toggle player/cursor coordinates and a cursor tile outline. |
| `::coords on` / `::coords off` | Explicitly show/hide coordinates. |
| `::tile` | Record the cursor tile, scene and placement center in local chat. |
| `::help` | List commands. |

For example, `::tele 12 -18` selects tile `(12, -18)`, not pixel `(12, -18)`.
Use `::pos` for a known valid starting address. With `::coords on`, hover a
candidate tile and enter `::tile` to record it for future node/monster placement.
The placement center is in the area's local scene pixels; a prop's own anchor
and worldbuilding validation still determine its actual placement.

These are the existing HiddenGrid movement cells, each **32 world pixels**.
X increases east/right; Y increases north/up. Signed coordinates are supported.
The grid is anchored to the area's authored `gameplay_grid_origin` (normally
pixel `(0, 0)`), independent of the camera, zoom and map-bound expansions.
At the default anchor, the first cell below/right of pixel `(0, 0)` is `(0, -1)`.
The scene path identifies the area: the same `(x, y)` in two scenes means two
different locations. There is no depth coordinate or implicit area travel.

Teleport checks the full existing 24-pixel player body against current collision
geometry, authored floor coverage and map bounds. Blocked/occupied/void tiles are rejected; the destination is
never silently moved. Successful teleport cancels old movement/targeting and
gathering, updates the player, actor, grid occupancy, sprite and camera together,
and preserves inventory, levels and health. Finish fishing/cooking first.

Teleport follows the existing sandbox-only developer permission boundary.
It cannot move a saved online character or write an online save. Coordinate
inspection is also available in the development client's online map view.
Tester/release clients do not install this controller. Existing F5/F6/F7/K/P
controls, ordinary chat and map travel retain their behavior.

## Validation

With the installed Godot 4.5.1 engine:

```powershell
& $env:GODOT --headless --path godot_client --script res://scripts/dev_tools/tile_commands_smoke.gd -- --social-no-auto
& $env:GODOT --headless --path godot_client --script res://scripts/dev_tools/tile_floor_smoke.gd -- --social-no-auto
```

To capture a real 4x render, omit `--headless` and add `--tile-screenshot` after
`--social-no-auto`. The PNG is written outside the repository to the temp folder.
The map suite also exercises Catacombs void rejection when that local expansion
is installed; other checkouts still run the permanent floor-hole regressions.
