# Authoritative Foundation Implementation Plan

> Historical design plan. The user subsequently authorized implementing the
> usable account-backed shared world directly, superseding the movement-only
> slice and approval pauses below. The installed entry point is now Login;
> accounts, durable PostgreSQL saves and authoritative gameplay are implemented.
> `godot_client/docs/Networking.md` and `backend/README.md` describe the actual
> modules, validation commands and remaining deployment/scale work. Unchecked
> boxes below describe the earlier proposed decomposition, not missing
> confirmation from the user and not a claim that every planned future module
> has shipped.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a loopback-only, two-client movement slice with server authority and explicit expansion points for larger worlds and additional worlds; verify storage/admission correctness above 50 without claiming load capacity.

**Architecture:** A Godot server owns a registry of logical regions and routes validated session commands to the sole owner of each region. Transport, simulation, collision, relevance and presentation have separate interfaces; the initial adapters run within one server process. Existing local gameplay remains available through its current entry point; the online foundation runs through separate test scenes and exposes movement only.

**Tech Stack:** Installed Godot 4.5.1, GDScript, ENet, JSON configuration/messages, Python standard-library process orchestration. No new engine or product dependencies.

**Spec:** `docs/superpowers/specs/2026-10-21-server-authority-and-worlds-design.md`, particularly milestone 1 and Expansion and maintainability requirements.

**Required companion:** `docs/superpowers/specs/2026-10-21-accounts-and-character-persistence-design.md` defines milestone 1B. This plan is 1A only; username/password accounts and durable saves must ship before usable online progression, not wait for multi-world deployment. The admission provider below is deliberately replaceable by 1B's asynchronous account-service adapter.

## Global Constraints

- The 50-player number is the first validation milestone, not a permanent limit or an advertised capacity.
- The initial `max_players` configuration default is 50 authenticated active players; pending handshakes have a separate bounded limit.
- Preserve the existing 0.6-second world rule tick.
- Gameplay decisions stay on the server. Unknown/unmigrated online actions fail closed; no local-game fallback.
- Logical world, region, instance, character and entity identity never derives from socket/peer IDs or scene-node paths.
- No production accounts, shared saves, world hopping, public hosting, combat, economy or 50-player performance certification ships in 1A. Mandatory companion milestone 1B supplies username/password accounts and durable saves before any real progress is enabled. This slice uses disposable test identities and a collision fixture; it is never presented as the first usable online game.
- Preserve active art, maps, balance, diagnostics and unrelated working changes. Recheck the active development branches before runtime integration.
- Keep secrets, ADC output, native logs and benchmark evidence outside Git; preserve generated source `.uid` files alongside new scripts.
- Use a dedicated `codex/` implementation branch. Review staged paths and diff, run relevant checks, verify origin is `Helloeoj/aetheria-v2`, commit, push and verify the remote SHA. Do not merge without authorization.

## Review Focus

- Configuring 51 or 200 players must exercise the same admission, storage and wire fields as 50; no hidden fixed-size slot list (Tasks 1, 2, 6).
- A stale region-owner generation must never mutate a reassigned actor, even when its command arrives after handoff (Task 2).
- Closing a client while movement is held must stop that actor promptly without freezing another client (Tasks 2, 3, 6).
- Baseline pages and deltas can be lost, duplicated or reordered; a client must not resurrect a removed actor or apply a half-baseline (Tasks 4, 5).
- A forged identity or an unmigrated action must not reach simulation, and credentials/private state must not enter other clients' snapshots or diagnostics (Tasks 3, 4, 6).

## File structure and interfaces

All new GDScript classes below live under `godot_client/network/`; test scripts/scenes live under `godot_client/scripts/dev_tools/` and `godot_client/scenes/dev_tools/`. Do not grow `scripts/main.gd` or activate the dormant placeholder to hold this implementation.

| File / class | Responsibility |
| --- | --- |
| `world_config.gd` / `OnlineWorldConfig` | Parse/validate server configuration and transport feasibility |
| `wire_schema.gd` / `OnlineWireSchema` | Bounded, versioned primitive-only message encoding/validation |
| `region_simulation.gd` / `OnlineRegionSimulation` | Dynamic actor state, fixed-step movement and authoritative events |
| `region_router.gd` / `OnlineRegionRouter` | Stable logical routes and owner generations; in-process adapter |
| `region_collision.gd` / `OnlineRegionCollision` | Server-owned collision query contract and fixture adapter |
| `session_registry.gd` / `OnlineSessionRegistry` | Disposable test ticket admission, peer-to-actor ownership and limits |
| `admission_provider.gd` / `OnlineAdmissionProvider` | Nonblocking admission/cancellation contract for a future account-service adapter |
| `fixture_admission.gd` / `OnlineFixtureAdmission` | Disposable single-use test ticket provider; no persistent-account claim |
| `session_wire.gd` / `OnlineSessionWire` | Identical RPC node contract on client/server; byte buffers only |
| `server_runtime.gd` / `OnlineServerRuntime` | ENet lifecycle, bounded command ingress, simulation clock and routing |
| `interest_index.gd` / `OnlineInterestIndex` | Region-local spatial cells and relevant actor IDs |
| `state_replicator.gd` / `OnlineStateReplicator` | Baselines, changes, removal tombstones and per-peer budgets |
| `client_state.gd` / `OnlineClientState` | Revision/epoch-aware client replica, no authority mutators |
| `client_runtime.gd` / `OnlineClientRuntime` | Connection/input, replica updates and disconnect handling |
| `network_unit_smoke.gd`, `network_test_peer.gd` | Headless contract assertions and scripted real peers |
| `network_server.gd`, `network_client.gd` and matching scenes | Explicit disposable foundation entry points and movement display |
| `tools/test_network_foundation.py` | External-output test runner, process cleanup and evidence |
| `godot_client/docs/Networking.md` | Launch/configuration, interfaces, limits and future milestone map |

Every result dictionary uses `ok: bool`, `code: String`; rejected mutations leave state unchanged. Configuration is immutable after startup in this milestone.

Region actor views use `{actor_id: String, world_id: String, region_id: String, owner_generation: int, position: Vector2, revision: int}`. Simulation events use `{type: String, actor: Dictionary}` for `actor_added`/`actor_changed`; removal uses `{type: "actor_removed", actor_id: String, region_id: String, owner_generation: int, revision: int}` with a newer revision. `add_actor` returns the initial view and its event; `step` returns changes. `remove_actor` returns a removal event, or an empty dictionary when absent. Wire records convert position to two finite JSON numbers. Routers and interest indexes are bound to one world, so identical region names in different worlds remain isolated. Replicas keep generation/revision tombstones until a newer complete baseline makes them obsolete.

## Task 1: Validated configuration and bounded wire schema

**Files:** Create `network/world_config.gd`, `network/wire_schema.gd`, `scripts/dev_tools/network_unit_smoke.gd`, `tools/test_network_foundation.py` (unit mode).

**Interfaces:** `OnlineWorldConfig.from_dict(raw: Dictionary) -> Dictionary` returns `{ok, code, config: OnlineWorldConfig}`. `OnlineWireSchema.encode(message: Dictionary) -> PackedByteArray` and `decode(payload: PackedByteArray) -> Dictionary` return validated primitive fields; decoding returns `{ok, code, message}`. No executable variant/object deserialization.

- [ ] **Step 1: Add failing configuration/schema tests.** The test entry extends `SceneTree`, counts checks, exits nonzero on failure, and prints exactly `[Network foundation] N checks, 0 failures` on success. Pin assertions equivalent to:

  ```gdscript
  assert(OnlineWorldConfig.from_dict({}).config.max_players == 50)
  assert(OnlineWorldConfig.from_dict({"max_players": 51}).ok)
  assert(OnlineWorldConfig.from_dict({"max_players": 200}).ok)
  assert(not OnlineWorldConfig.from_dict({"max_players": 0}).ok)
  assert(not OnlineWorldConfig.from_dict({"max_players": 50.5}).ok)
  assert(not OnlineWireSchema.decode(PackedByteArray()).ok)
  ```

  Also test malformed JSON, nested/oversized payload, unsupported version, unknown keys/actions, NaN/infinity vectors and rejected client outcome fields. Cap decoded depth and collection/string sizes before simulation; do not rely on JSON parsing to reject every invalid semantic value.
- [ ] **Step 2: Run RED.** `python tools/test_network_foundation.py --godot $env:GODOT --suite unit` must identify missing classes, not silently pass with no checks. Runner uses `tempfile` output and the `tools/test_inventory_items.py` pattern to reject `SCRIPT ERROR:`/`ERROR:` even with a zero Godot exit code.
- [ ] **Step 3: Implement configuration and schema.** Defaults: loopback IPv4 bind, world ID `world-1`, port 24567, `max_players=50`, pending limit 16, fixed-step 30 Hz, snapshots 10 Hz, speed 4 tiles/second, input expiry 250 ms, max catch-up 4 steps/frame, relevance radius 32 tiles, spatial cell size 16 tiles. Preserve the 0.6-second rule tick using 18 steps. Validate fixed-step rates against the existing tick; snapshot rate cannot exceed simulation rate. Validate the current ENet admission cap against its 4,095 transport ceiling with an explicit unsupported-cap diagnostic; do not embed this ceiling in logical-world schemas. Bind/session fixture loading must reject non-loopback configuration in this slice.

  Version 1 input envelope: `{v:1, kind:"move", sequence:int, direction:[number,number]}`; sequence is a nonnegative exact integer no larger than `2^53-1`, and direction magnitude cannot exceed 1 beyond a small documented floating-point tolerance. JSON numbers may decode as floats: validate finite integral/range constraints before converting integer fields. Wire strings are bounded to 64 characters, payloads to 8,192 bytes. Admission/control kinds (`hello`, `admitted`, `rejected`, `resync`) and state kinds (`baseline`, `delta`, `removed`) have distinct allowlists; only `hello` may carry a ticket, and only before admission. Capabilities identify this as `movement_only`; reject attack/craft/grant/travel and arbitrary actor IDs.
- [ ] **Step 4: Run GREEN** with the unit command; inspect the marker and actual error output. Test negative, fractional, wrong-type and above-transport-limit configuration, and extreme snapshot/catch-up/queue values. Document actual allowed ranges in the config class.
- [ ] **Step 5: Review and commit only Task 1 source/tests and `.uid` files** with `feat: define expandable online world configuration and protocol`.

## Task 2: Multi-actor region simulation and in-process routing

**Files:** Create `network/region_simulation.gd`, `network/region_router.gd`, `network/region_collision.gd`; extend unit smoke tests.

**Interfaces:** `OnlineRegionSimulation.configure(world_id: String, region_id: String, config: OnlineWorldConfig, collision: OnlineRegionCollision) -> void`; `add_actor(actor_id: String, position: Vector2) -> Dictionary`; `remove_actor(actor_id: String) -> Dictionary`; `apply_move(actor_id: String, sequence: int, direction: Vector2, now_usec: int) -> Dictionary`; `step(delta: float, now_usec: int) -> Array[Dictionary]`; `read_actor(actor_id: String) -> Dictionary` returns a detached view. Router: `configure(world_id: String) -> void`; `register_region(region_id: String, owner_generation: int, simulation: OnlineRegionSimulation) -> Dictionary`; `dispatch(region_id: String, owner_generation: int, actor_id: String, command: Dictionary, now_usec: int) -> Dictionary`; `read_actor(region_id: String, actor_id: String) -> Dictionary`. Collision: `resolve_motion(actor_id: String, start: Vector2, displacement: Vector2) -> Vector2` returns the allowed position using server geometry.

- [ ] **Step 1: Add failing authority/expansion tests.** With a fake monotonic clock, add 200 distinct actors and verify the last actor can move without changing the first. For unobstructed motion, verify 30 fixed steps move a held actor 4 tiles within tolerance; refresh input before its expiry. Test an obstacle and map boundary, replayed sequence, invalid direction, input expiry, removal and independent actors.

  ```gdscript
  assert(router.dispatch("region-a", 1, actor_id, move_command, now_usec).ok)
  # Re-register region-a with owner generation 2 and an equivalent detached state.
  assert(not router.dispatch("region-a", 1, actor_id, move_command, now_usec).ok)
  assert(router.dispatch("region-a", 2, actor_id, next_command, now_usec).ok)
  ```

  Verify a region-b route cannot affect a region-a actor. Tests may use fixture helpers defined in this test file; each helper must create the real production classes above.
- [ ] **Step 2: Run the unit command and observe these tests fail.** Keep existing Task 1 assertions passing.
- [ ] **Step 3: Implement explicit region state and routing.** Actors are dictionaries keyed by stable opaque IDs with server-owned position/revision. Regions have unique world-scoped identity and generation. Single-owner updates are sequential; no dependency on a singleton `player`, UI or `SceneTree` paths. Fixed-step clock drives motion; commands contain no elapsed time. The fixture collision adapter uses a 128-by-128 tile rectangle and a solid rectangle from `(60,20)` to `(64,108)`; all server/renderer fixture geometry comes from this same adapter. This is not an import of active game-map collision.
- [ ] **Step 4: Run GREEN**, including stopping one expired/disconnected actor while another moves. Verify returned views cannot mutate authoritative dictionaries. Exercise a replaced in-process adapter with preserved logical IDs and an increased owner generation. This is a contract test, not proof of safe distributed handoff.
- [ ] **Step 5: Review and commit Task 2** with `feat: add server-owned region simulation and routing`.

## Task 3: Session-bound ENet transport and fixed server clock

**Files:** Create `network/session_registry.gd`, `network/admission_provider.gd`, `network/fixture_admission.gd`, `network/session_wire.gd`, `network/server_runtime.gd`, `scripts/dev_tools/network_server.gd`, `scenes/dev_tools/network_server.tscn`, `scripts/dev_tools/network_test_peer.gd`; extend Python runner with `transport` suite.

**Interfaces:** Registry: `configure(config: OnlineWorldConfig) -> Dictionary`; `reserve(peer_id: int, request_id: String, now_usec: int) -> Dictionary`; `complete(peer_id: int, request_id: String, claims: Dictionary, now_usec: int) -> Dictionary`; `resolve(peer_id: int) -> Dictionary`; `release(peer_id: int) -> void`. Reservations count against capacity and expire; completion rejects a disconnected/expired/replaced request. Only a successful completion returns server-owned `account_id`, `character_id`, `actor_id`, `region_id`, `owner_generation`, `session_epoch`. Admission provider: `begin_admission(request_id: String, world_id: String, ticket: String) -> void`, `cancel_request(request_id: String) -> void`, `release_claim(request_id: String) -> void`; signal `admission_ready(request_id: String, result: Dictionary)`, where successful results contain backend-owned `claims`. The fixture provider adds `configure(tickets: Dictionary) -> void`; test records supply stable account/character IDs. Request IDs and session epochs are generated by the server. A full-world reservation failure does not call the provider or consume a ticket. Late success after cancellation triggers provider cleanup rather than actor creation. Runtime: `start(config: OnlineWorldConfig, admission: OnlineAdmissionProvider, router: OnlineRegionRouter) -> Error`, `stop() -> void`. No backend I/O blocks the simulation thread.

Wire node path is `/root/NetRoot/Wire` on both peers, with four identical RPC declarations: `request_control(payload: PackedByteArray) -> void` (any peer, reliable channel 0), `submit_move(payload: PackedByteArray) -> void` (any peer, unreliable-ordered channel 1), `deliver_control(payload: PackedByteArray) -> void` (server authority, reliable channel 0), and `deliver_delta(payload: PackedByteArray) -> void` (server authority, unreliable channel 2). All use `call_remote`; server handlers reject calls executed on a client and client handlers reject non-server senders. Callbacks obtain the real RPC sender, never a peer ID from payload data. The client does not acquire node multiplayer authority.

- [ ] **Step 1: Add failing real-socket tests.** Two distinct tickets create distinct actors; an invalid ticket, reused ticket, second login for the same account, and unauthenticated movement cannot create/move actors. At configured cap 2, a third valid account receives `world_full`; release permits later admission. Delay a provider result until after disconnect/reservation expiry; no actor appears and the claim is released. Reject forged target identity, unknown action, command floods and oversized packets without disconnecting the innocent peer. Verify source logs contain no ticket values.
- [ ] **Step 2: Run RED:** `python tools/test_network_foundation.py --godot $env:GODOT --suite transport`. Runner creates disposable tickets/config outside the repo using Python `secrets`, supplies secrets through temporary files/environment rather than command-line values, starts processes with timeouts and kills only its own process handles in `finally`.
- [ ] **Step 3: Implement transport and session lifecycle.** ENet binds loopback explicitly. Tickets are disposable single-use test credentials behind `OnlineFixtureAdmission`; keep ticket-file parsing out of the runtime and registry so 1B can supply the shared backend adapter. The pending state machine reserves capacity, invokes the provider, validates the matching live request, then creates the fixture actor. Bound pending connections/timeouts separately from authenticated slots. Default per-peer command token bucket: 60/sec, burst 120; total queued work: at most 8 commands per authenticated slot, computed from configured cap. Coalesce pending movement per actor so floods do not turn into a movement-time multiplier. Server monotonic time and a fixed 30 Hz accumulator drive all actors; process at most 4 catch-up steps, report sustained overload and stop new admissions while unhealthy. Do not fast-forward arbitrary gameplay time after a stall. A disconnect neutralizes held input immediately and removes the fixture actor; expiry also stops a stalled connection. In 1B, durable finalization must precede ownership release; immediate fixture cleanup is explicitly not a persistent-save implementation.
- [ ] **Step 4: Run GREEN** with real separate Godot processes, plus unit suite. Test controlled clock stall/health recovery, stale sequence, pending timeout and stop/restart cleanup. Redact tokens before diagnostic events are constructed. Test reconnect requires a fresh ticket and cannot resurrect the removed actor by replaying commands.
- [ ] **Step 5: Review and commit Task 3** with `feat: bind online commands to server-owned sessions`.

## Task 4: Spatial relevance and bounded authoritative replication

**Files:** Create `network/interest_index.gd`, `network/state_replicator.gd`, `network/client_state.gd`; extend unit and transport suites.

**Interfaces:** Index: `configure(world_id: String, cell_size: float) -> void`, `upsert(actor_id: String, region_id: String, position: Vector2) -> void`, `erase(actor_id: String) -> void`, `query(region_id: String, center: Vector2, radius: float) -> Array[String]`. Replicator: `configure(config: OnlineWorldConfig, router: OnlineRegionRouter, index: OnlineInterestIndex) -> void`, `record_event(event: Dictionary) -> void`, `attach(peer_id: int, actor_id: String, region_id: String, session_epoch: int) -> void`, `detach(peer_id: int) -> void`, `build_messages(peer_id: int, now_usec: int, byte_budget: int) -> Array[PackedByteArray]`. Runtime feeds actor lifecycle/step events into the index and replicator. Replica: `apply(message: Dictionary) -> Dictionary`, `read_actor(actor_id: String) -> Dictionary`, `reset() -> void`. State messages carry the admitted session epoch and report population as an exact integer. No client API grants resources or changes authoritative position.

- [ ] **Step 1: Add failing visibility/order tests.** An owner sees self and nearby actors; excludes actors across regions, beyond radius and all tickets/session data. Moving across cells updates interest. Complete baselines install atomically; reversed page order, missing page, duplicate delta and stale delta cannot corrupt state. Removal followed by an older update cannot resurrect an entity. Verify self corrections remain timely while other actors generate sustained changes.
- [ ] **Step 2: Run RED** for unit and transport suites with these assertions enabled.
- [ ] **Step 3: Implement spatial indexing and versioned replication.** Every record carries world/region/owner epoch, actor ID and actor revision. Baseline pages have a snapshot ID, page index and validated total-page count; retain at most 2 incomplete baselines per client, expire after 2 seconds, and never apply partial state. Normal change records are coalesced by actor/revision and replace older pending changes. Interest membership changes/removals and baselines use reliable channel 0; movement requests use unreliable-ordered channel 1; change messages use unreliable channel 2 with revision rejection. Split batches by encoded-byte limit, not assumptions about player count. A fresh reliable baseline repairs missed deltas at most once per 5 seconds per peer; excessive resync requests are rejected.

  Initial per-peer replication budget: 64 KiB/second with a 16 KiB burst, configurable within validated server bounds. Pending state is bounded by current interest membership with fair rotation after owner corrections. Emit queue/age/byte metrics; do not silently discard nearby actors to produce a passing larger-world benchmark. If a rate/budget cannot support the workload, report that capacity failure. Client control-message and baseline staging limits must be independent of untrusted page-count fields.
- [ ] **Step 4: Run GREEN**, including 200-actor unit fixtures with configurable budgets, exact encoded-size checks, radius/cell boundary cases, incomplete-baseline expiry and bounded pending state. Test loss followed by baseline recovery, and old-epoch messages after region reassignment. These are correctness tests, not 200-player performance certification.
- [ ] **Step 5: Review and commit Task 4** with `feat: replicate relevant server state with bounded queues`.

## Task 5: Two-client foundation view and failure behavior

**Files:** Create `network/client_runtime.gd`, `scripts/dev_tools/network_client.gd`, `scenes/dev_tools/network_client.tscn`; extend real-peer test driver. Do not modify active game maps or the current default main scene in this milestone.

**Interfaces:** `OnlineClientRuntime.connect_world(address: String, port: int, ticket: String) -> Error`, `request_move(direction: Vector2) -> void`, `disconnect_world() -> void`; signals `status_changed(code: String)`, `state_changed()`. The view reads `OnlineClientState` and renders interpolated remote state; it never writes server state.

- [ ] **Step 1: Add failing client integration tests.** Two clients see distinct actors from real authoritative snapshots; one input moves only its actor. A forged local position is replaced by server state. Held-key disconnect or lost focus sends neutral input when possible and is still covered by server expiry. `world_full`, version mismatch and unavailable server yield explicit status and no local-game launch. An old-session snapshot cannot populate a newly connected replica.
- [ ] **Step 2: Run RED:** `python tools/test_network_foundation.py --godot $env:GODOT --suite clients`.
- [ ] **Step 3: Implement the disposable view.** Display `Online foundation test — movement only; no saved progress`, connection status and authoritative actor IDs/positions using simple fixture shapes and the collision adapter's geometry. Use the same `/root/NetRoot/Wire` node contract as Task 3. Take input at the simulation cadence and send a neutral vector on release/focus loss. Initially render the local actor at authoritative position; prediction is deferred until reconciliation tests are ready. Disable all unmigrated gameplay entry points by absence and server allowlist, not hidden widgets. No inventory, economy, combat or debug-grant requests are supported here.
- [ ] **Step 4: Run GREEN** and open two rendered client instances against the local fixture server. Verify visible independent motion, obstacle collision, another region being absent and clean disconnects. Capture evidence outside the repository. Run the original default game entry separately to verify local gameplay still starts.
- [ ] **Step 5: Review and commit Task 5** with `feat: add two-client authoritative movement test view`.

## Task 6: Expansion regressions, documentation and delivery

**Files:** Finish `tools/test_network_foundation.py`; extend `network_unit_smoke.gd`/`network_test_peer.gd`; create `godot_client/docs/Networking.md`. Preserve all script `.uid` files.

**Interfaces:** Runner CLI: `--godot <exe> --suite unit|transport|clients|all --output <external-dir>`. Default output is an external temporary directory. Exit 0 requires every selected suite's success marker, no native/script errors, all required checks executed and all test-owned processes cleaned up.

- [ ] **Step 1: Add failing expansion tests.** Through the same registry/router/schema and reserve/complete admission path, configure 51 and then 200 fixture accounts, admit exactly that many, resolve/move the last, reject the next, release/re-admit and verify unique stable actor identities. The cap accounting test may drive registry objects in-process; label it as such. Test two logical worlds with independent actors and two regions sharing a world; no cross-world or stale-generation command mutates either. Check snapshot population fields preserve counts above 50. Add an extra fixture region through registration without editing `session_wire.gd` or command schemas. Replace the fixture provider with a delayed test provider without changing gameplay routing; late/cancelled responses fail closed. Unknown activity commands remain rejected; activity registration is a later milestone, not an unsafe generic dispatcher.
- [ ] **Step 2: Run RED** for `--suite all` with each new assertion included and no skip on missing engine/suite.
- [ ] **Step 3: Finish runner and documentation.** Document server JSON defaults/validated ranges, disposable ticket creation/storage, loopback-only launch commands, movement-only capabilities, module interfaces, test interpretation and clean shutdown. Record a requirement map: mandatory 1B owns username/password accounts, shared database saves and durable ownership before real online progress; milestone 2 owns active-map collision/real gameplay migration using 1B's transactions; milestone 3 owns world selection/hops using existing shared characters; milestone 4 owns the 50-client 60-minute load gate; milestone 5 owns larger-world performance/worker rollout; milestone 6 owns increasing world count. Explain how to configure a larger cap, change a relevance budget, register a region and later replace the routing/admission adapters, including remaining tests required for safe deployment. Do not claim a configuration increase creates capacity.
- [ ] **Step 4: Run GREEN and relevant regressions.** Run `python tools/test_network_foundation.py --godot $env:GODOT --suite all`, then editor parse/import and original default main-scene startup using the installed Godot. Inspect full output for errors, not just return codes. Run existing inventory/combat/interaction regressions if runtime dependencies were changed; broaden only when a change or failure warrants it. Re-read the spec and record deferred milestone requirements instead of marking them implemented. Verify no evidence/secrets/caches entered the working tree.
- [ ] **Step 5: Review and deliver.** Review working tree and explicit staged diff; run `git diff --cached --check`; commit as `test: verify configurable world growth and document foundation`. Push only the implementation branch to verified `origin`, confirm remote SHA, create/attach a PR into `main` when validated and ready for integration, and report tests, SHA, URL and exact remaining limits. No capacity or full-game security claim follows from the two-client foundation.

## Plan review and execution

This plan implements only milestone 1A. Mandatory companion milestone 1B adds username/password accounts and persistent characters through the recommended Django/PostgreSQL backend and the admission adapter above; review its separate design before preparing its detailed implementation plan. Both 1A and 1B must complete before usable online progression. Optional verified-email recovery remains future work and cannot be presented as implemented by reserving schema fields.

Recommend native execution for this first plan: the six tasks depend closely on the same wire/session/region contracts, and a single implementer can keep them consistent. The user must review the plan and select native execution or subagent-driven execution before implementation. No gameplay code has been changed while preparing this plan.
