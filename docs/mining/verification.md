# Mining verification — 2026-10-24

**Verdict:** authoritative core verified in Godot 4.5.1; playable Mining and the
installed 65-hour progression target are **not verified**. Design/plan tasks 5–7
remain incomplete. No items, artwork, balance values or unrelated systems changed.

## Coverage and results

| Area | Evidence / limitation |
| --- | --- |
| Ore/tool requirements, speeds, probability | Definition and service suites pass. Independent ore/tool levels, exact tool unlock, ownership filtering, faster attempts and increasing/capped probability. Actual catalog has no pickaxe; tool-resolution fixtures are isolated, not production items. |
| Inventory and XP | Real PlayerState grants one Bronze Ore (235) and 121 XP, caps XP at 19,450,000 and rejects full inventory/save-limit stacks without depletion. Save migration and journal/skill regressions pass. |
| Depletion/respawn | Shared generation claim, 4-second Bronze respawn, stale-generation rejection and one total reward for competing miners pass. |
| Interruptions | Movement/range, eligibility/combat/cast, equipment/tool loss, full inventory, damage, death, competing activities, disconnect and freeze/thaw cases pass. |
| Multiplayer/durability | Region/host fixtures verify forged input rejection, same-deposit races, movement ordering, lost-save-ack retry without replay, lease loss and reconnect data. Live two-client test blocked at account-service health check (connection refused); no live Mining race was tested. |
| Animation/interaction | Not implemented: client/local controller, click/approach, actor gathering animation/cancellation, deposit rendering and client reconciliation. Existing attachment tests do not prove Mining presentation. |

Commands run from repository root using installed Godot/Python:

- `tools/test_mining.py --godot <Godot>`: **247 checks passed** across eight scenes
  (definitions 31, service 48, authority 37, host 13, character persistence 31,
  region freeze 15, host persistence 54, original online minigames 18).
- `tools/test_cooking.py --godot <Godot>`: **12 suites / 2,853 checks passed**:
  cooking, cooking UI, tavern, fish food, Pale fishing, food input, fish inventory,
  Fishing, cast pacing, Fishing input, skill tools and fishing difficulty.
- `tools/test_inventory_items.py --godot <Godot>`: **122 passed**.
- `catalog_acquisition_smoke.tscn`: **1,064 passed**;
  `attachment_smoke.gd`: **1,403 passed**.
- Django `backend.accounts`: **26 tests passed**, using the PostgreSQL test
  database and temporary isolated beta-policy directory; live policy untouched.
- `python -m unittest discover -s tools -p test_mining_balance.py`: **11 passed**.
- `python tools/mining_balance.py`: **65.01 hours**; rerun with
  `--config godot_client/data/mining.json`: **unavailable / nonzero**, clear
  missing-pickaxe result without a traceback or fabricated progression estimate.
- Godot editor import and main startup (`--quit-after 120`): **passed**, no script errors.
- `sprite_integration_smoke.gd`: **7 / 3,836 checks failed**, already present before
  these fixes: expected 23 skins versus 22; Iron Longsword attachment, attack-event
  and attack-facing assertions in each of `EastOutskirtsLayered.tscn` and `main.tscn`.
  These non-Mining tests/assets were not changed.
- `tools/test_online_concurrency.py`: **blocked**, account-service connection refused.

## Balance

The proposed six-ore / five hypothetical-tool scenario (`tools/mining_balance.json`)
reproduces **65.00575 hours (65.01)**, within 60–70 hours. It uses the existing XP
curve, full extraction intervals, probabilities, one uncontested deposit per option,
full respawn waits and 1.2-second retargeting; excludes extended banking/travel.

The installed `godot_client/data/mining.json` contains only Bronze and **zero
pickaxes**. It cannot currently award Mining XP through valid gameplay, so there is
**no attainable finite 1–100 estimate**. Do not describe 65.01 hours as production
balance. Bronze's probability/reward/timing fields agree with the proposal, but the
proposal's other ores and tool profiles are not installed content.

## Narrow fixes and remaining prerequisites

- `godot_client/scripts/mining_definitions.gd`: exact interval equality for the
  lower-ID tiebreak; approximate equality previously selected a slower tool depending
  on insertion order. Regression reproduced before fixing.
- `godot_client/scripts/dev_tools/mining_definitions_smoke.gd`: real-selector tests
  for both orders, exact ties, ownership, level boundaries and defensive copies.
- `tools/mining_balance.py`, `tools/test_mining_balance.py`: runtime configuration
  compatibility and actionable unavailable result instead of a schema traceback;
  no synthesized tools or balance changes. Future runtime estimates require an
  explicit `--retarget-seconds` assumption and actual catalog pickaxe IDs.
- This report: `docs/mining/verification.md`.

Manual/content attention: approved actual pickaxe catalog IDs/acquisition, finalized
multi-ore metadata, approved deposit placements, available/depleted visual bindings,
and player Mining animation/tool attachment bindings. Implement the remaining
interaction/presentation adapters, then test two real clients and rerun final balance.
Do not repurpose swords/rods, invent IDs, or substitute goblin-worker artwork.
