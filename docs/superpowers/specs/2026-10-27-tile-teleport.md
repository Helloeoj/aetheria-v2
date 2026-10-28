# Tile coordinates and developer teleport

Give worldbuilding/testing the existing movement grid's integer (x, y) addresses.
One cell is 32 world pixels. Use HiddenGrid.cell_at/center and its authored origin,
so addresses survive camera changes and map-bound expansion. X increases east;
Y increases north. Negative coordinates are valid. An address belongs to its area;
separate scenes do not share an implicit depth coordinate.

Enter commands through the existing chat composer, even when chat is offline:
`::tele x y` (`::teleport` alias), `::pos`, `::tile`, `::coords [on|off]`, `::help`.
`::pos` reports the area, scene and a reusable teleport command. The optional
coordinate overlay shows player/cursor cells and highlights the cursor cell;
it does not intercept game input or edit content. Responses remain local.

Teleport lands on the exact requested center, never a silently substituted tile.
Reject malformed/noninteger/out-of-range coordinates, solid terrain, unsupported
floor, occupied cells, unavailable geometry, dead players and area transitions.
Cancel old movement, chase, targeting, spell intent and gathering on success;
synchronize actor/player/grid/sprite/camera immediately. Preserve character state.

Use the existing developer sandbox permission boundary. The user explicitly
confirmed developer-only scope for now; future admin commands are much later
work. Preserve the existing rule that online characters never accept client
debug grants. Coordinate inspection also works in development online views.

Approaches considered: a second coordinate grid would drift from movement;
pixel teleport would be hard to reuse for placement. Reusing HiddenGrid gives
one identity for movement, cursor inspection and future node/monster placement.
No artwork, props, maps, interfaces or gameplay are replaced or moved.

Implement in the active checkout, preserve unrelated edits, run focused Godot
regressions and startup/import validation, then commit/push only this feature.
