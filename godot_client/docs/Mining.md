# Mining core

Implemented: shared server-side extraction, existing Mining XP (1–100), save migration, and one Bronze Ore (235) definition. **Not yet playable:** the item catalog has no pickaxes. Production `pickaxes` remains empty; no items, IDs, substitutes, map placements or artwork were added.

## Ownership and entry points

- `scripts/mining_definitions.gd`: validated metadata in `data/mining.json`, joined to GameData. Independent ore requirements/probability curves; fastest owned eligible pickaxe, then lowest ID. Bronze uses the simulator's 121 XP, 0.28→0.78 over 26 levels, exponent 1.15 and 4-second respawn.
- `scripts/mining_service.gd`: one service per `network/authoritative_region.gd`. Repeated full-interval attempts; atomic generation claim → one `PlayerState.add_item()` → existing Mining XP → post-grant notification. One winner per deposit generation; no client RNG/reward fields.
- `scripts/mining_deposit.gd` and `scenes/gathering/mining_deposit.tscn`: authored stable ID, existing ore ID, approach point and radius. Region discovery rejects duplicate IDs. Blank visual paths explicitly mean unbound content; nonempty paths must resolve. This core node stores presentation state but does not render art.
- Existing `network/region_activities.gd` routes `mine_start {deposit_id, deposit_generation}` and `mine_stop {}`. Movement/attack/cast, hand-equipment changes, damage, death, another activity, loss of the locked tool, range/line-of-sight failure and inventory capacity cancel. Host travel/logout/ownership loss close activities; disconnect cancels even during a freeze.
- Snapshots expose public deposits/actor gathering and private activity/deadline/stop reason. Client interaction, offline controller, animation and committed XP-rate presentation are later plan tasks, not implemented here.

## Persistence and limits

`network/character_codec.gd` writes version 2; version 1 defaults **only absent Mining XP** to zero. Present malformed Mining and missing old skills reject. Backend accepts 1/2. Deploy/restart the compatible backend before matched host/client; old hosts cannot read upgraded saves.

Inventory has no gameplay slot cap. `InventorySystem.can_add_to_backpack()` validates existing save limits (2,147,483,647 per stack, 4,096 distinct entries), including canonical aliases, without inventing a backpack size. XP uses the unchanged 19,450,000 cap.

Uncertain saves reuse the existing exact operation/payload retry, freeze attempts and never replay rewards. Thaw starts a full fresh interval. Deposits are transient per host region; host restart resets rocks, not committed character rewards. No cross-host lock or crash-atomic deposit database is promised.

## Verification

From the repository root with installed Python/Godot:

```powershell
python tools/test_mining.py --godot $env:GODOT
python tools/test_cooking.py --godot $env:GODOT
python tools/test_inventory_items.py --godot $env:GODOT
python -m unittest discover -s tools -p test_mining_balance.py
& $env:GODOT --headless --path godot_client res://scenes/dev_tools/catalog_acquisition_smoke.tscn
```

Mining tests use real PlayerState, inventory, XP, region, codec and host/save queue. Only missing-tool resolution and HTTP responses are doubled; no fake items enter GameData. Includes simultaneous miners, stale/forged commands, misses, capacity, interruption, freeze/thaw, replay-safe saves and reconnect data.

Validated 2026-10-24: 120 Mining checks; 118 migration/freeze/host/original-online checks; 122 inventory checks; all 12 Fishing/Cooking suites; 1,064 acquisition checks; 7 balance tests; 26 account/PostgreSQL tests with isolated temporary beta-policy configuration. Editor import and headless startup passed. Initial regression runs exposed the now-fixed journal description and finished-Cooking handoff gaps; live beta configuration and one timing-sensitive account throttle run were isolated/rerun successfully. No live-account or two-client Mining playtest was performed.

Next activation prerequisites: authorize actual catalog pickaxes and acquisition, bind approved visuals/placements, then implement plan tasks 5–7 and verify two real clients. The simulator's 65-hour route remains a multi-ore proposal, not a production rate claim for this Bronze-only core.
