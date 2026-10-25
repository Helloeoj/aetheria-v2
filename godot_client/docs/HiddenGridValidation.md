# Hidden-grid integration validation — phase 6

Scope: the installed Godot 4.5.1 game, including the local uncommitted Catacombs
content/navigation. Tests exercise gameplay, collision and persistence; editor
compilation is a separate check, not evidence that gameplay works.

## Findings and completed fix

Offline auto-chase cancellation could strand a player between centers. Clearing
or replacing the target left a finite route goal, while the released-input path
only advanced steps without such a goal. Target death had the same outcome.

`grid_control_integration.gd` reproduced six failures for clear/replace/dead
targets. Target changes now cancel the remaining route; the active segment still
finishes normally. Losing a target also releases chase ownership. The actual
game/controller integration now passes 37 checks, including native keys, smooth
speed, turning, stopping, diagonal duration, actor sharing and scale.

Existing test fixtures were brought into line with the approved design, not
gameplay changed to satisfy old assumptions:

- Direction/facing fixtures start at reachable clear centers; ordinary turns no
  longer assume redirection every 1/120 second.
- Fishing fixtures move the authoritative actor/player and rendered sprite to
  the same arrived center, rather than moving only a sprite or an off-grid point.
- The sprite fixture tests all 22 current catalog skins and their authored
  frames instead of asserting a stale count of 23. It meets item skill
  requirements, explicitly starts combat, and waits for the actual death fade.
- The live session fixture decodes saves through the backward-compatible codec
  instead of assuming every current save is version 1.
- Authoritative portal coverage adds a Golem–Catacombs round trip when that
  optional local map and entrance are installed.

## Verified scale and preservation

The current player rotation source is 64x64 pixels. Walk frames are 76x76 with
transparent padding. Visual scale is 0.75: the base source canvas occupies 48x48
world pixels, and the padded animation canvas 57x57. The collision body remains
24x24; gameplay cells remain 32px. These are distinct measurements, not a request
to rescale art. The Catacombs' native 32px art cells still display at 24 world
pixels through its existing 0.75 content scale.

All 58 files that were dirty or untracked at this phase's start were compared by
SHA-256 and remain unchanged. This includes the Catacombs assets, scenes, scripts,
navigation, integration test and unrelated tools. No original art, map geometry,
interface implementation or catalog was edited by this validation phase.

The original lake-art fishing interface was rendered and visually inspected;
native controls and pale context menus passed at 1280x720, 2560x1440 and 3840x2160.
Rendered Catacombs entrance, room, clearance and round-trip captures were also
inspected. Existing cooking/pan controls are covered by the gameplay suites.

## Executed coverage

| Area | Evidence |
| --- | --- |
| Movement/grid | 28-suite grid runner: zero failures; includes editor and login startup, conversions, native WASD/arrows, real body movement, release/turn rules, diagonals, swept edges, corner prevention, actor sharing, blocked click routing, map adoption and narrow passage holds |
| Enemies/combat | Existing combat, chase/return/leash, roaming adapter, knockback and orb tests; no new idle roaming enabled |
| Interactions | Fishing, cooking, crafting/shop, mining, pickups and portals; original controls/interfaces and authored ranges retained |
| AoE | Inclusive boundaries, negative/map-edge cells, per-spell offsets, captured target cell, committed arrival occupancy, entering/leaving targets, wall behavior and shared preview/resolution footprints |
| Networking | 13 networking suites: zero failures, including 1,401 snapshot-transport checks, persistence/freeze, original online minigames, input and responsiveness; separate 3-suite movement runner also passed |
| Presentation/art | 3,837 sprite checks passed: 22 skins, 251 authored frames, eight facings, equipment, targeting/death and both game scenes |
| Fishing/cooking/food | All 12 existing suites passed; inventory suite passed 122 checks |
| Catacombs | 132 checks in a real rendered run: original 24px navigation, actual pointer/context input, eight room routes, body/corner clearance, doorway posts, removed islands, cameras, sealed descent and retained character state |
| Server map transitions | 109 checks with local Catacombs present, including concurrent region loads, center arrivals, single world ownership, persistence, invalid arrivals and ownership loss |
| Saves | Existing codec versions 1/2, inventory/progression preservation, safe spatial migration, rejection without replacement for unsafe coordinates, portal state and motion cleanup |

Counts overlap between runners and are not a count of independent tests.

## Real encrypted network run and remaining failure

Two real source-client sessions ran against a separate local HTTP/DTLS world and
disposable PostgreSQL database. Gameplay passed 12 checks and then 14 checks:
login, authoritative movement, prediction before a snapshot, speed limits,
client-grant rejection, durable logout and reconnect with the same character,
inventory and progression. First rendered responses were 5.95ms and 5.82ms with
10Hz snapshots. Both leases released and save revisions advanced. The isolated
world stopped gracefully and its disposable database was dropped; live account
rows/services were not modified.

**The full encrypted runner is NOT green.** Shutdown logs three native errors:
`Parameter "p_mutex->mutex" is null` in `godot_mbedtls_mutex_free`.
A standalone Godot script containing only certificate loading, ENet server
creation, DTLS setup and `peer.close()` reproduced all three errors without any
game or account code. This phase does not suppress the errors or claim to fix
Godot's native TLS teardown. An engine-level fix/compatible engine review remains
outside the approved movement design; no engine upgrade was performed.

## Remaining design limits

- Tavern's 28.5px/30.75px aisles still prevent strict grid adoption. Its original
  continuous movement and existing furniture navigation remain.
- AoE radii remain explicitly provisional: Stormring/Tideburst 2, Shatterground
  2.5, Cinderfall 3, Starfall 3.5. Existing wall-ignore behavior is unchanged.
- Invalid/overlapping/out-of-map saved coordinates cannot establish a safe
  original floor and are not silently moved to another floor or overwritten.
- Mining's empty approved pickaxe catalog and content-placement hold remain.
- Production idle roaming is not newly enabled; the dormant helper's shared-grid
  adapter is tested without changing existing encounter behavior.
- This is automated/native-input and rendered validation, not a human playthrough
  or wide-area-network/load test. Exported release executables were not tested.

## Reproduction commands

From the repository root, using the installed engine/runtime and an evidence
directory outside the checkout:

```powershell
./tools/test_hidden_grid.ps1 -Godot $env:GODOT -EvidenceDirectory <outside-repo>
python tools/test_networking.py --godot $env:GODOT --output <outside-repo>
python tools/test_movement.py --godot $env:GODOT
python tools/test_cooking.py --godot $env:GODOT --output <outside-repo>
python tools/test_inventory_items.py --godot $env:GODOT --output <outside-repo>
& $env:GODOT --headless --path godot_client --script res://scripts/dev_tools/sprite_integration_smoke.gd
```

`tools/test_beta_online.py` requires the existing private account-service Python
runtime and PostgreSQL service. It creates isolated disposable test state, and
currently exits unsuccessfully on the native DTLS shutdown errors described above.
Keep its credentials and raw diagnostic evidence outside Git.
