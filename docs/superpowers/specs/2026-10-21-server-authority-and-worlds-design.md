# Server authority and selectable worlds

Date: 2026-10-21

Status: Proposed design; awaiting user review. No networking implementation or capacity validation is claimed.

## Purpose and requirements

The user wants Aetheria's gameplay to run on a trusted server so modified clients cannot decide gameplay outcomes. The agreed starting load-test target is 50 simultaneous players. The long-term goal is thousands online at the same time, using selectable worlds in the style requested by the user.

This design interprets that goal as thousands across multiple worlds, not thousands guaranteed in one crowded area. Each world is an independent simulation of the same game map. Players in different worlds cannot interact with each other's actors or drops. Regions and dungeons are locations within a world; changing region does not switch worlds.

Assumptions for review:

- A character's inventory, equipment, currency, skills, and saved progress follow it between worlds.
- One account may have only one active gameplay session across the service. The first version has one character per account.
- Worlds use the same gameplay rules and content version. Special-rule worlds and separate economies are outside the first implementation.
- Online character saves are separate from local development/test characters. Local saves and debug tools cannot grant online progress.
- The initial client target is the existing desktop Godot game. Browser/mobile transports are separate future requirements.

The 50-player number is a test target, not an advertised capacity. Increasing a configured connection limit does not establish playable capacity.

## Current repository evidence

The running project is `godot_client/project.godot`, using Godot 4.5.1. At inspection, `origin/main` was `201c2f6`; the active development checkout also had cooking work at `e1d0b71` and uncommitted catacombs/crafting changes. This document is isolated from those changes on a branch based on `origin/main`. Runtime integration must recheck the final merged versions before editing shared files.

- `autoload/network_manager.gd` is a placeholder and is absent from the project's autoload list. It is not a working server connection.
- `scripts/main.gd` constructs one `PlayerState`, drives movement, real-time combat and world ticks locally, and also manages presentation and input.
- `scripts/world_state.gd` stores one `player`; movement synchronization assumes that single player. Adding RPCs alone cannot make this a multiplayer world.
- `scripts/player_state.gd` holds mutable inventory, gold, skills, equipment, HP, mana, targeting and position in the client process.
- `scripts/combat_system.gd`, `inventory_system.gd`, `crafting_service.gd`, `loot_system.gd`, `fishing_session.gd`, and `cooking_session.gd` contain rules to reuse behind server-owned state.
- `scripts/game_tick_config.gd` defines a 0.6-second world tick; movement and projectiles currently advance using frame delta. Network snapshot cadence must not silently change these gameplay rules.
- `scripts/scene_travel.gd` preserves a local player while changing scenes. Online region travel requires server authorization and cannot replace the server's entire scene for one player's move.
- Item/spawn menus, skill editing, free fishing supplies, and healing practice tools currently modify local gameplay. Hiding their UI would not secure an online server.

The dormant Python tree under `legacy/` is reference material, not the active server.

## Approaches considered

1. **Dedicated Godot worlds with shared character services — recommended.** Reuse the current GDScript rules and map collision. Extract simulation from UI, make actor storage support multiple players, and add a trusted entry point for all commands. Multiple independent world processes provide the growth path.
2. **Separate Python gameplay server.** Possible, but would require porting and maintaining combat, timing, collision and item rules in another implementation. No running Python server currently provides this functionality.
3. **One seamless distributed simulation.** A different product requirement involving cross-process region ownership and transfers while players share one world. It adds substantial complexity and is unnecessary for selectable worlds.

Choose option 1. Start with one world process and stable boundaries for shared account and character ownership. Do not introduce orchestration clusters or distributed simulation before measurements justify them.

## World structure and growth

Each configured world has a stable ID, display name, endpoint, region label, content/protocol version, measured player count, admission cap, and status (`starting`, `online`, `full`, `draining`, or `offline`). Initial admission cap: 50 authenticated active players; pending handshakes have a separate bounded limit. Counts and admission are server-owned; the displayed count is advisory and a successful reservation decides admission.

One world starts as one headless Godot process. A machine can run more than one process only when CPU, memory and bandwidth measurements leave sufficient headroom. Different worlds can later move to different machines without changing character identity or the client command contract.

Example arithmetic, not capacity evidence: 20 worlds with 50 active players each would give 1,000 simultaneous players in total. This does not establish that one machine could host those 20 worlds. Per-world caps can increase after load testing.

Players receive updates about nearby relevant entities in their current region/instance. Private inventory and progression state is sent only to the owning player. Combat targets and interactions must still be validated against authoritative region, range and visibility; receiving an entity ID never grants authority over it.

For the first worlds, region simulations stay inside their world's process. Dungeon instance IDs are scoped by world and party/instance. Moving a busy region into another process is a later design if one world reaches its measured simulation limit.

## Components and authority boundaries

| Component | Responsibility | Principal dependencies |
| --- | --- | --- |
| Client connection/presentation | Send input intents, show authoritative state, reconcile prediction, show world list | Versioned protocol and trusted service endpoints |
| World command gateway | Bind connection to authenticated account/character; validate schema, ownership, sequence, limits and command permissions | Session authority and authoritative simulation |
| World simulation | Own players by unique entity ID, monsters, collision, combat, drops, activities, server time and random outcomes | Existing gameplay rules and server-loaded map data |
| Replication service | Send relevant snapshots/events and owner-only character updates; support joining and resynchronization | Authoritative world state and spatial relevance |
| Shared session/character service | Authenticate/admit, prevent simultaneous ownership, persist character transactions, fence stale writers, coordinate world hops | Transactional database and server credentials |
| World directory | Publish healthy available worlds and route selection/admission | World heartbeats and session service |

The shared service may initially be a single backend process with a transactional database. It is a service boundary, not a requirement to deploy many microservices. Database product, backend runtime and login provider are selected in the implementation plan against the deployment environment; correctness requirements here do not depend on a vendor. Clients never receive database or world-service credentials.

The network manager is responsible for connection lifecycle and routing; gameplay rules stay in focused server services. `main.gd` becomes a client-facing coordinator instead of acquiring all networking, persistence and simulation responsibilities.

## Command and simulation rules

The client requests actions such as move direction, walk-to destination, attack target, cast spell, equip owned item, eat food, pick up drop, craft recipe, start/operate/cancel activity, or use portal. The gateway obtains the requesting actor from its session, not a client-chosen player ID.

Requests never set authoritative position, elapsed simulation time, HP, damage, inventory contents, item stats, currency, XP, RNG seed, success result, or destination scene path. Destination markers identify server-approved portals and routes. Clients can inspect public item definitions for display; the server uses its own approved definitions for decisions.

Every accepted action checks applicable session/world/region, life state, ownership, range/line of sight, resources, skill requirements, cooldowns, activity reservation and capacity. Reject malformed/non-finite/out-of-range data, unsupported command versions, unknown actions and excessive rates before expensive work. Bound payload sizes, pending queues and resynchronization requests. Never deserialize executable objects from client messages.

Use monotonically sequenced movement input and server-bounded movement speed. Server elapsed time determines movement distance; client-reported frame delta does not. Missing/expired movement input becomes neutral so a disconnected player cannot keep walking indefinitely. Click-to-walk and auto-chase pathfinding use server collision.

Preserve the existing 0.6-second world rule tick. Movement, projectile and activity timing advance using a fixed server simulation step selected and measured in the first plan. Snapshot frequency is independently configurable. Bound catch-up work; sustained overload triggers health/admission changes and diagnostics, not an unbounded tick backlog or client-controlled time.

Client movement prediction is optional for the first playable slice and must reconcile to authoritative snapshots. Other actors interpolate. Cosmetic prediction cannot award items, land damage, spend resources or finalize progress. Reliable transactions/events and replaceable movement/snapshots use appropriate separate channels.

Fishing/cooking prompts and attempts are server-issued sessions with server-owned reservations, timing and random results. Clients submit input for a specific attempt, never a success flag. Define bounded, server-measured latency handling and stale-attempt rejection; unrestricted client timestamps cannot extend deadlines. Closing a panel or losing focus cannot pause the server activity clock.

Online servers reject development grants, spawn commands, arbitrary healing and skill edits, even if a modified client exposes those buttons. Development tools operate only on isolated local/test characters. Any later administrative operations need separately authorized server permissions and audit records.

## Persistence and exclusive sessions

The shared service persists versioned character records with stable account and character IDs, schema/content version, location, inventory/equipment/currency, skills/XP and other durable progress. Live combat state remains world-owned; define restart/checkpoint handling for temporary HP, timers and unfinished activities before enabling each feature online. Live sockets, node references and temporary local UI state are never serialized as saves.

Admission atomically obtains exclusive account/character ownership with a generation (fencing token). Every durable write validates that generation and the expected character revision. Expiring a lease alone is insufficient: a partitioned old world must be unable to write after a new owner is admitted. A world stops accepting mutations when it cannot maintain valid ownership; health/readmission waits for safe recovery.

Item/currency/XP transactions commit atomically with an idempotency key scoped to the authenticated session and operation. Retries return the existing committed result. Consumptions and rewards cannot be stored separately. A client sees final transaction success only after durable commit. An operation is not treated as committed merely because its database request was sent.

On persistence failure, reject or pause the affected operation without consuming inputs or granting rewards. Keep bounded in-flight work and surface recoverable status. Process restarts restore the last committed state and deduplication records; an unfinished action is either committed once or rolled back according to its persisted state. Server-side cancellation and reservation cleanup must follow the same transaction rules.

Before each economy feature is enabled, its plan must specify atomic boundaries, durable retry identity, crash recovery and any multi-character transaction behavior. Trading, banking, auctions and cross-world chat do not yet become implemented merely because shared services exist.

## Join, reconnect and world hopping

1. Authenticate through a trusted service. Obtain a short-lived admission ticket bound to account, character, selected world, protocol/content version and a single-use nonce. ENet connection identity alone is not account authentication. Production credential/ticket handling requires authenticated encrypted service communication and a specified replay-safe world admission mechanism.
2. World service validates and consumes admission, reserves capacity and establishes exclusive ownership before creating an actor. A provisional socket cannot send gameplay commands or receive private state.
3. Load the committed character, create a unique actor in the correct region, and send the initial owner state and nearby entity snapshot. Loading a client scene cannot create a second authoritative character.
4. A reconnect gets a fresh authenticated connection and invalidates the replaced connection. A short server-owned reconnect grace period retains ownership; after expiry, durable state and cleanup must finish before ownership is released or recovered. Reconnect does not replay rewards or reset cooldowns.
5. A hop first reserves destination capacity. Initial rule: disallow hopping while in combat, casting, an item transaction or a timed activity. A server-owned account cooldown prevents rapid hop spam. Exact duration is configurable and tested rather than borrowed from another game.
6. Freeze the source actor, commit the source's final revision, and prepare a single-use transfer bound to the destination. Destination activation requires the committed revision and a new ownership generation. Source removal and destination activation are coordinated by the shared service; never trust a client-provided save.
7. Before ownership transfer, an admission/commit failure cancels the reservation and can resume the source. After transfer, the source stays frozen/removed and reconnect uses the shared service's current owner. Transfer timeouts and recovery cannot activate both copies. Preserve temporary restrictions such as remaining combat/hop cooldowns across a hop or reconnect.

When a world drains, remove it from new admission and finish or safely terminate existing sessions. Unexpected process death must invalidate its admission tickets and recover ownership through the shared service. A character cannot bypass unresolved durable work by selecting a different world.

## Migration milestones

These are delivery boundaries, not claims that the whole migration fits a small network-handler patch. Produce the first implementation plan after this architecture is reviewed. Later plans refine the next milestone using the measured results.

1. **Authoritative foundation and two-client slice.** Separate headless server startup from client UI, establish versioned command/replication contracts, session-to-player binding and multiple player state, server-owned movement/collision, and a server tick. Use isolated server-issued test identities initially. Unmigrated online gameplay actions are explicitly unavailable; they cannot fall back to local authority. This is a foundation test, not a secure full-game release.
2. **Complete existing gameplay migration.** Move combat/AI/loot, inventory/equipment/food, crafting, fishing/cooking, progression and region/dungeon travel behind validated server services. Preserve existing content and balance. Remove online mutation paths through debug/practice UI. Recheck cooking and catacombs changes at integration. Test two clients competing for the same drop or station reservation.
3. **Shared characters and selectable worlds.** Add production-capable identity, transactional saves, exclusive ownership, directory/world list, two independent world processes, reconnect and safe hops. Keep the contracts from milestone 1; shared online progress is not enabled before ownership and transaction safety pass tests. Isolated test characters remain clearly separate.
4. **50-player acceptance and deployment.** Exercise the migrated game with authenticated simulated clients and real client smoke tests. Publish measured hardware/workload/latency results and a justified admission cap. Fifty is a target to pass, not a guarantee.
5. **Growth across worlds.** Provision more worlds against measured shared-service and host capacity; test hundreds and then thousands of connections across worlds, login bursts and persistence load. Increase per-world density only after separate hotspot tests pass.

The long-term architecture makes milestones 3-5 possible. It does not require building worldwide deployment, automatic scaling, a seamless distributed map, player trading, a marketplace, or social systems in milestone 1.

## Acceptance and evidence

Tests must inspect actual server-owned state and use real network sessions where authority is in question. Client UI state or a successful connection is insufficient evidence.

- **Authority:** malicious clients cannot change HP/XP/items, teleport, increase speed with forged delta, control another actor, invoke debug grants, fabricate cooking/fishing success, bypass portal rules, or loot an inaccessible drop.
- **Transactions:** duplicate/reordered/replayed requests, simultaneous pickup, insufficient ingredients, disconnect during crafting, and crash before/after durable commit never duplicate rewards or partly consume resources.
- **World ownership:** one account cannot be active in two worlds. Test full destination, replayed/expired admission, reconnect, stale source writes, source/destination/backend failure at each transfer boundary and recovery after timeouts.
- **Isolation:** entity IDs include world/instance context; another world or private instance cannot be targeted. Owner-only state never broadcasts to bystanders. Session replacement invalidates the previous connection.
- **Gameplay regressions:** run existing relevant combat, inventory, crafting, fishing/cooking, skill and interaction tests, editor parse/import checks and main-scene startup. Preserve native/ADC diagnostics and keep generated evidence outside source control.
- **Normal load:** ramp 1, 10, 25 and 50 clients; hold 50 for at least 60 minutes with movement, combat, loot and activities. Record server CPU/RSS, bandwidth, queue sizes, simulation step distribution, RPC rates, database latency/errors and client-observed response times after warmup.
- **Crowded area:** separately run 50 clients in one region with representative monsters/projectiles, then spread clients across regions. A dispersed test cannot certify crowded combat capacity.
- **Timing budget:** for the chosen fixed-step duration, require p99 simulation work under 80% of that duration, no accumulating step/command backlog, no unexplained authoritative desynchronization, no transaction/ownership violations, no script errors and no continuing memory growth after warmup. Define measured response-time criteria for the actual test network in the implementation plan. Record configured step/snapshot rates and entity/activity counts with the result.
- **Network impairment:** test latency, jitter, packet loss, reconnect and stalled clients; command queues and retransmissions must remain bounded. Activity timing tests include realistic latency without trusting client clocks.
- **Scale:** report total online across worlds separately from active players per world and per area. Multi-world arithmetic and ENet limits are not throughput benchmarks.

No gameplay code, deployment or benchmarks are part of this design-only change. The next gate is user review of this written specification, then an implementation plan for milestone 1 and a choice of execution method.

## Engine references

- [Godot 4.5 dedicated servers](https://docs.godotengine.org/en/4.5/tutorials/export/exporting_for_dedicated_servers.html): headless and dedicated-server exports.
- [Godot 4.5 high-level multiplayer](https://docs.godotengine.org/en/4.5/tutorials/networking/high_level_multiplayer.html): ENet peers, sender identity, RPC authority and channels. These primitives do not implement application authentication or game validation.
- [Godot 4.5 ENetMultiplayerPeer](https://docs.godotengine.org/en/4.5/classes/class_enetmultiplayerpeer.html): configurable client count with a documented maximum of 4,095 for `create_server`; documentation explicitly states achievable simultaneous clients can be much lower.
