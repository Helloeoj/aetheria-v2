# Server authority and selectable worlds

Date: 2026-10-21

Status: World growth direction accepted. The user additionally requires username/password accounts and saved character progress for the first usable online game, with optional verified-email recovery later. The account/persistence addition awaits review; implementation also requires the relevant written plan and execution-method selection. No networking implementation or capacity validation is claimed.

## Purpose and requirements

The user wants Aetheria's gameplay to run on a trusted server so modified clients cannot decide gameplay outcomes. The agreed starting load-test target is 50 simultaneous players. The long-term goal is thousands online at the same time, using selectable worlds in the style requested by the user. The user explicitly requires growth in BOTH players per world and the number of worlds, with maintainable expansion points from the first implementation.

The first usable online version must include username/password registration, login and persistent characters. Progress must survive logout and later sessions. Optional email linking and password-reset requests are future features; email must be verified before it can authorize recovery. The concrete account, save and recovery design is in [Accounts and persistent characters](2026-10-21-accounts-and-character-persistence-design.md).

Each world is an independent logical simulation of the same game map. A world must retain its identity as its player capacity increases or its simulation moves across processes. Players in different worlds cannot interact with each other's actors or drops. Regions and dungeons are locations within a world; changing region or server worker does not switch worlds. Thousands across the service is the initial long-term population goal; capacity within one world and one crowded area must be measured separately.

Assumptions for review:

- A character's inventory, equipment, currency, skills, and saved progress follow it between worlds.
- One account may have only one active gameplay session across the service. The first version has one character per account.
- Worlds use the same gameplay rules and content version. Special-rule worlds and separate economies are outside the first implementation.
- Online character saves are separate from local development/test characters. Local saves and debug tools cannot grant online progress.
- The initial client target is the existing desktop Godot game. Browser/mobile transports are separate future requirements.

The 50-player number is the first validation milestone, not a permanent limit or an advertised capacity. Larger worlds are a first-class design objective. Raising the configured admission cap is a small operational change only after load tests establish sufficient simulation, persistence and network capacity; it is not a substitute for those improvements.

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

1. **Dedicated Godot worlds with shared character services — recommended.** Reuse the current GDScript rules and map collision. Extract simulation from UI, make actor storage support multiple players, and add a trusted entry point for all commands. Grow each world through optimization, relevant-entity replication and, when needed, region workers; also add more independent worlds.
2. **Separate Python gameplay server.** Possible, but would require porting and maintaining combat, timing, collision and item rules in another implementation. No running Python server currently provides this functionality.
3. **Distributed region workers from the first release.** Supports dividing one world's load across processes early, but immediately requires routing, ownership transfers and cross-region interaction rules. Preserve the required boundaries in option 1; implement distributed workers when measured demand justifies their complexity.

Choose option 1. Start with one world process and stable boundaries for shared account and character ownership. Do not introduce orchestration clusters or distributed simulation before measurements justify them.

## World structure and growth

Each configured world has a stable ID, display name, endpoint, region label, content/protocol version, measured player count, admission cap, and status (`starting`, `online`, `full`, `draining`, or `offline`). The initial `max_players` configuration default is 50 authenticated active players; pending handshakes have a separate bounded limit. `max_players` is validated server configuration, not a hard-coded gameplay/protocol constant. Counts and admission are server-owned; the displayed count is advisory and a successful reservation decides admission.

One world starts as one headless Godot process, but logical world IDs, region/instance IDs and worker IDs are distinct from the start. A machine can run more than one process only when CPU, memory and bandwidth measurements leave sufficient headroom. Different worlds can later move to different machines, and regions within one world can later gain separate workers, without changing account/character IDs or asking players to select a different world.

Capacity growth follows two independent tracks: raise one world's tested population through 50, 100, 200 and later evidence-based milestones; add worlds to raise total service capacity. These are benchmark stages, not promised limits or throughput. The implementation must not make an expanding game depend on an increasing number of worlds capped at 50.

Players receive updates about nearby relevant entities in their current region/instance. Private inventory and progression state is sent only to the owning player. Combat targets and interactions must still be validated against authoritative region, range and visibility; receiving an entity ID never grants authority over it.

For the first worlds, region simulations stay inside their world's process. Dungeon instance IDs are scoped by world and party/instance. Define region ownership, state-transfer and command-routing interfaces initially, using in-process adapters. A future worker implementation can replace those adapters. Entity/world identities and client action semantics do not include machine addresses, scene-node paths, or assumptions that every region is in the same process. The client endpoint may use a gateway or receive a server-authorized redirect if physical routing changes.

Each entity has exactly one authoritative region owner. Later cross-worker region transfers must use fenced ownership, sequenced handoff and revisioned state so two workers cannot apply the same action. Cross-region projectiles, targeting and party-instance transitions require explicit interaction rules and failure tests before distributed regions are enabled. The first implementation provides clear contracts; it does not pretend these runtime guarantees already exist.

Splitting regions helps players spread throughout a larger world. It does not automatically solve a single crowded city or boss encounter. Such hotspots require separate profiling of spatial queries, collision, AI, replication and persistence, with a later design for finer spatial partitioning if optimization alone is insufficient. Retain a measured safe admission cap until the relevant tests pass.

## Expansion and maintainability requirements

- Configuration owns per-world `max_players`, simulation and snapshot rates, spatial relevance radius, input/queue budgets and admission limits. Values have validated ranges; changing world population does not require editing combat, inventory or UI code. Unsafe live changes are applied during a controlled restart rather than mutating storage layout during play.
- Player storage is keyed by stable IDs, not fixed arrays of 50 slots. No packet field, UI list, actor registry or database schema assumes a maximum population of 50. Configured transport and memory limits are checked explicitly and fail with a clear diagnostic.
- The session gateway maps authenticated connections to stable character/world/region IDs. The command router resolves region ownership; gameplay handlers do not access global scene paths, sockets or physical worker endpoints. A network connection is replaceable without creating a new character.
- A region simulation receives an explicit command and fixed-step clock and emits authoritative events/state. Its gameplay interface works in-process first and can later sit behind a worker adapter. Do not run speculative parallel writes against the same region state.
- Use spatial indexing for nearby-entity queries and per-client interest tracking. Replication sends changes within an explicit byte/entity budget and supports baseline resynchronization; it must not broadcast every actor to every player each step. Priority rules preserve authoritative results and important nearby events under load.
- Reuse shared character/transaction services for both larger worlds and additional worlds. Measure backend contention and connection pools; adding world processes cannot bypass ownership or create independent copies of a character's inventory.
- New regions, instances, item catalogs and activity handlers register through explicit versioned data/service interfaces. Enabling a new activity requires a server validator and an authority test; unknown network action names remain rejected. Expansion content must not require rewriting the connection manager.
- Version protocol, persistent schema and content manifests. Pin a world's compatible versions, define migrations, and reject mismatched clients clearly. Growth must not rely on silently interpreting old save or packet layouts as new ones.
- For each new process boundary, document ownership, ordering, retry/deduplication, timeouts and recovery before rollout. Replace focused adapters and data definitions rather than introducing a universal plugin framework or implementing distributed infrastructure before it is required.

## Components and authority boundaries

| Component | Responsibility | Principal dependencies |
| --- | --- | --- |
| Client connection/presentation | Send input intents, show authoritative state, reconcile prediction, show world list | Versioned protocol and trusted service endpoints |
| World command gateway | Bind connection to authenticated account/character; validate schema, ownership, sequence, limits and command permissions | Session authority and authoritative simulation |
| World simulation | Own players by unique entity ID, monsters, collision, combat, drops, activities, server time and random outcomes | Existing gameplay rules and server-loaded map data |
| Region registry/router | Resolve logical world/region/instance IDs to their sole simulation owner; use an in-process adapter initially | Region ownership records and versioned command/state contracts |
| Replication service | Send relevant snapshots/events and owner-only character updates; support joining and resynchronization | Authoritative world state and spatial relevance |
| Shared session/character service | Authenticate/admit, prevent simultaneous ownership, persist character transactions, fence stale writers, coordinate world hops | Transactional database and server credentials |
| World directory | Publish healthy available worlds and route selection/admission | World heartbeats and session service |

The shared service may initially be a single backend process with a transactional database. It is a service boundary, not a requirement to deploy many microservices. The account/persistence addition recommends Django's maintained authentication facilities with PostgreSQL; dependency versions and deployment setup belong in its implementation plan. All worlds use the same stable account/character records. Clients never receive database or world-service credentials, and Godot gameplay does not need a second implementation in the backend language.

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

Persistent accounts are milestone 1B, required before enabling real online progression. Milestone 1A's disposable movement fixture is an engineering test only. Account creation uses a username/password and approved initial character state, never an uploaded local save. Password hashes, login sessions, optional verified email and future reset tokens belong to the account service, not a world snapshot. See the account/persistence design for the player flows and security requirements.

The shared service persists versioned character records with stable account and character IDs, schema/content version, location, inventory/equipment/currency, skills/XP and other durable progress. Live combat state remains world-owned; define restart/checkpoint handling for temporary HP, timers and unfinished activities before enabling each feature online. Live sockets, node references and temporary local UI state are never serialized as saves.

Commit durable progression before reporting success, checkpoint transient location/state every 5 seconds by default, and flush on orderly logout/region transitions/shutdown. Resolve the final saved revision before releasing ownership. A sudden failure may roll transient state back to the latest checkpoint; already committed progression must survive. Define explicit cancellation, retry and quarantine behavior rather than silently recreating a starter character when storage fails.

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

These are delivery boundaries, not claims that the whole migration fits a small network-handler patch. Milestone 1 is split into the existing 1A network foundation plan and a separate 1B account/persistence plan. Both are required before a usable online game with real progress; a disposable fixture does not satisfy the account requirement. Later plans refine the next milestone using the measured results.

- **1A — Authoritative foundation and two-client slice.** Separate headless server startup from client UI, establish versioned command/replication contracts, session-to-player binding and multiple player state, server-owned movement/collision, and a server tick. Include validated population configuration, stable world/region/actor IDs, an in-process region router, bounded spatial replication and tests demonstrating no fixed 50-player storage limit. Use isolated server-issued test identities behind a replaceable admission adapter. Unmigrated online gameplay actions are explicitly unavailable; they cannot fall back to local authority. This is a foundation test, not a secure full-game release.
- **1B — Accounts and persistent characters.** Implement username/password registration/login, a shared database, character load/save, durable operation journal, exclusive ownership, checkpoint/logout/disconnect recovery and an authenticated backend adapter. Keep nullable verified-email fields and mail/recovery interfaces compatible with the later email feature. Demonstrate persistence across actual process restarts and enforce private encrypted admission before public access. This precedes real online progression.
- **2 — Complete existing gameplay migration.** Move combat/AI/loot, inventory/equipment/food, crafting, fishing/cooking, progression and region/dungeon travel behind validated server services backed by 1B's durable character transactions. Preserve existing content and balance. Remove online mutation paths through debug/practice UI. Recheck cooking and catacombs changes at integration. Test two clients competing for the same drop or station reservation, including disconnect during the transaction.
- **3 — Selectable worlds and shared-character integration.** Reuse 1B's shared identities, database and exclusive ownership; add directory/world list, two independent world processes, reconnect and safe hops. Keep the contracts from milestone 1; a world hop cannot create a second save or duplicate online progress. Isolated test characters remain clearly separate.
- **4 — 50-player acceptance and deployment.** Exercise the migrated game with authenticated simulated clients and real client smoke tests. Publish measured hardware/workload/latency results and a justified admission cap. Fifty is a target to pass, not a guarantee.
- **5 — Growth within each world.** Benchmark 100 and then 200 players in one logical world, followed by larger evidence-based stages. Profile simulation, crowded areas, replication and persistence separately. Improve data structures and batching, raise tested caps, and introduce region workers through the existing routing/ownership interfaces only when the results require them. Do not reduce game rules or change world identity merely to claim a larger population.
- **6 — Growth in world count.** Provision additional worlds against measured shared-service and host capacity; test hundreds and then thousands of connections across the service, login bursts and persistence load. Track larger-world tests independently so this milestone cannot substitute for milestone 5.

The long-term architecture makes milestones 3-6 possible. It does not require building worldwide deployment, automatic scaling, distributed region runtime, player trading, a marketplace, or social systems in milestone 1. The region and configuration boundaries needed for future growth are part of milestone 1.

## Acceptance and evidence

Tests must inspect actual server-owned state and use real network sessions where authority is in question. Client UI state or a successful connection is insufficient evidence.

- **Authority:** malicious clients cannot change HP/XP/items, teleport, increase speed with forged delta, control another actor, invoke debug grants, fabricate cooking/fishing success, bypass portal rules, or loot an inaccessible drop.
- **Transactions:** duplicate/reordered/replayed requests, simultaneous pickup, insufficient ingredients, disconnect during crafting, and crash before/after durable commit never duplicate rewards or partly consume resources.
- **Accounts and saved sessions:** username/password registration without email, case-insensitive username uniqueness, correct/incorrect login, one initial character, complete character round-trip, orderly logout, sudden disconnect and actual process restart preserve the same committed account/character state. Save-service failures do not grant another writer a stale copy. Future email reset requires verified ownership, single-use expiring tokens and session revocation before activation.
- **World ownership:** one account cannot be active in two worlds. Test full destination, replayed/expired admission, reconnect, stale source writes, source/destination/backend failure at each transfer boundary and recovery after timeouts.
- **Isolation:** entity IDs include world/instance context; another world or private instance cannot be targeted. Owner-only state never broadcasts to bystanders. Session replacement invalidates the previous connection.
- **Gameplay regressions:** run existing relevant combat, inventory, crafting, fishing/cooking, skill and interaction tests, editor parse/import checks and main-scene startup. Preserve native/ADC diagnostics and keep generated evidence outside source control.
- **Normal load:** ramp 1, 10, 25 and 50 clients; hold 50 for at least 60 minutes with movement, combat, loot and activities. Record server CPU/RSS, bandwidth, queue sizes, simulation step distribution, RPC rates, database latency/errors and client-observed response times after warmup.
- **Crowded area:** separately run 50 clients in one region with representative monsters/projectiles, then spread clients across regions. A dispersed test cannot certify crowded combat capacity.
- **Expandable world population:** use test configurations above 50 (at least 51 and 200) to verify admission accounting, dynamic actor storage, owner-state routing and world-list counts without editing gameplay code. These correctness tests are separate from the actual 100/200-player performance gates. Verify invalid/unsupported caps fail at startup with diagnostics; changing a cap never changes character IDs, persistence schema or command fields.
- **Region routing and future workers:** two regions in the same world isolate commands by logical identity; replacing an in-process test adapter preserves actor IDs and command results. Reject a command routed with an obsolete owner generation. Actual worker handoff, cross-region interactions and failure recovery need distributed integration tests before deploying a distributed world.
- **Expansion content and relevance:** registering an additional region or approved activity does not require editing transport code; an unknown action is rejected. Replication omits distant/private state and respects configured budgets when relevant-entity count grows; resynchronization restores a coherent baseline.
- **Timing budget:** for the chosen fixed-step duration, require p99 simulation work under 80% of that duration, no accumulating step/command backlog, no unexplained authoritative desynchronization, no transaction/ownership violations, no script errors and no continuing memory growth after warmup. Define measured response-time criteria for the actual test network in the implementation plan. Record configured step/snapshot rates and entity/activity counts with the result.
- **Network impairment:** test latency, jitter, packet loss, reconnect and stalled clients; command queues and retransmissions must remain bounded. Activity timing tests include realistic latency without trusting client clocks.
- **Scale:** report total online across worlds separately from active players per world and per area. Compare one world at 50/100/200 and later tested populations, and separately compare increasing world count. Multi-world arithmetic and ENet limits are not throughput benchmarks. A future gateway layout must account for transport connection ceilings without encoding that transport's connection limit as a permanent logical-world player limit.

No gameplay code, deployment or benchmarks are part of these design documents. The existing 1A plan covers only the isolated networking fixture. Review the account/persistence addition before writing its separate 1B plan; implementation follows review of the applicable plans and selection of an execution method.

## Engine references

- [Godot 4.5 dedicated servers](https://docs.godotengine.org/en/4.5/tutorials/export/exporting_for_dedicated_servers.html): headless and dedicated-server exports.
- [Godot 4.5 high-level multiplayer](https://docs.godotengine.org/en/4.5/tutorials/networking/high_level_multiplayer.html): ENet peers, sender identity, RPC authority and channels. These primitives do not implement application authentication or game validation.
- [Godot 4.5 ENetMultiplayerPeer](https://docs.godotengine.org/en/4.5/classes/class_enetmultiplayerpeer.html): configurable client count with a documented maximum of 4,095 for `create_server`; documentation explicitly states achievable simultaneous clients can be much lower.
