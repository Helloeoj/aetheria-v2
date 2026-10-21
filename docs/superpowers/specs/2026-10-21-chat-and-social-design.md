# Player chat, friends and blocking

Date: 2026-10-21

Status: Conversational design approved. Written specification awaiting user review; implementation has not started. This document does not claim an installed chat server or working online accounts.

## Agreed outcome

Players can communicate through local, global and private messages in a mostly transparent text panel that remains visible at the bottom of the game, in the style of RuneScape's chat box. They can keep a persistent friends list, see friends' availability, initiate private messages and block unwanted contact. The user selected a working server and in-game UI rather than an interface-only implementation, then approved a 20-tile local range and friends without acceptance requests.

Success requires actual messages between separate Godot clients, server-enforced routing and blocking, durable social lists, and a readable panel that survives area changes without intercepting gameplay when the player is not typing. An echo inside one client is not network delivery.

## Repository evidence and integration dependencies

The active game is the Godot 4.5.1 project at `godot_client/project.godot`. Inspection covered the active development checkout at `e1d0b71`, including its uncommitted area-travel changes. This specification is isolated on `codex/chat-and-social`, based on `origin/main` at `201c2f6`, to avoid including unrelated cooking, crafting and catacombs work. Recheck merged runtime files before implementation.

- `autoload/network_manager.gd` is a dormant placeholder and is not an enabled autoload. No working chat or account client exists.
- `scripts/main.gd` owns local gameplay and UI. Its text-focus checks are useful, but the P and K gameplay shortcuts currently run before the general editing guard. Chat typing must be protected before all gameplay shortcuts, including modal handlers.
- `main.gd` places quick-food controls near the bottom-left. The new panel must reserve that space and move those controls above it.
- `SceneTravel` preserves local character state while replacing area scenes. A scene-owned chat node would lose its connection and history, so social state and the panel must live outside replaceable scenes.
- The `scripts/server/` session/message classes demonstrate in-process routing only. They do not provide network authentication or durable accounts.

Related designs already exist on `codex/world-server-design`, inspected at `5998c36`:

- [Server authority and worlds](https://github.com/Helloeoj/aetheria-v2/blob/5998c36/docs/superpowers/specs/2026-10-21-server-authority-and-worlds-design.md).
- [Accounts and persistent characters](https://github.com/Helloeoj/aetheria-v2/blob/5998c36/docs/superpowers/specs/2026-10-21-accounts-and-character-persistence-design.md).

Those documents propose a shared Django/PostgreSQL account backend, stable separate account/character IDs, username/password authentication and one active gameplay session per account. They are designs, not available implementations. Reuse those identity/session boundaries; do not introduce a second password system, silently create public accounts from chat names, or claim account integration already works.

**Dependency:** Public, authenticated chat requires the shared account/session backend. The chat service and UI can be developed and exercised with explicit loopback-only test identities first, but that fixture is not the complete player-facing delivery. The implementation plan must identify the account-backend dependency before scheduling production integration. It must not expand this task into implementing character persistence or deploy anonymous public chat as a substitute.

## Approach and scope

Use a dedicated social service within the shared backend, with a WebSocket connection from the Godot client. Keep message routing, relationships, authentication and world-location lookup separate from rendering and gameplay simulation. This shares account identity while allowing chat to stay connected during area travel and later world changes.

Alternatives considered: player-hosted chat would make availability depend on the host's client; migrating the entire game simulation before adding chat would considerably expand the task. A shared social service supports the requested communication directly and fits the existing online-game design.

Use Django Channels for the backend WebSocket adapter and PostgreSQL for durable social records, alongside the account service's maintained authentication. Pin compatible dependencies and exact commands in the implementation plan. The initial service has one application worker with explicit bounded connection/dispatch state; it makes no multi-worker or population-capacity claim. A production channel layer such as Redis and cross-worker ordering tests are required before adding application workers. In-memory channel layers are limited to local tests.

The first release includes message delivery, relationships, presence, connection/reconnection feedback, session-only scrollback and the permanent panel. It does not include offline mail, persistent message archives, read receipts, attachments, group chat, parties, trading or a moderation dashboard. Shared movement/combat remains the separately planned multiplayer migration.

## Player experience

### Persistent panel

- Anchor at the bottom-left with 12 logical pixels of margin; target 640 by 200 logical pixels at 1280 by 720. Resize within the viewport using the existing UI scale, shrink the width on narrow windows and retain legible controls. Reserve space so quick-food controls and notices sit above the panel.
- Use a dark background at approximately 25% opacity, full-opacity readable text, a subtle border and the existing fantasy UI palette. Opacity applies to the background rather than the entire control. Provide a saved background-opacity setting from 10% to 80%.
- Keep the panel above normal gameplay menus and modal activities and preserve it across area changes. It has no close, collapse, auto-hide or inactivity fade. The area's opaque loading cover may temporarily cover it during travel; its state and messages survive.
- Show All, Local, Global and Private filter tabs, with unread counts when a different tab is selected. All combines those channels and service notices. Each message includes a channel label, sender and text; distinguish channels with text labels as well as colors.
- Separate the display filter from the send channel. A Local/Global/Private selector beside the composer shows exactly where a message will go. Default to Local; selecting All never silently changes the destination. Private exposes a recipient-handle field beside the input, allowing messages to players outside the friends list. Choosing Message on a friend fills that same field.
- Show incoming and outgoing private messages in Private and All, clearly distinguishing the other player. Selecting a friend opens their private-message composer. The first release uses one private transcript with recipient labels, rather than separate windows per player.
- Keep at most 500 message records in client memory across channels. Scrolling up pauses automatic scrolling and shows a new-message indicator; scrolling to the bottom resumes it. Receiving messages must not pull the reader away from older text. Mark a channel read when its messages are displayed at the bottom; All marks its included channels read under that same condition. Scrollback survives area travel and connection loss, but clears on logout, identity change or application restart.
- Render player text as plain text. Do not interpret BBCode, markup, executable links, remote images or control characters.

### Keyboard and mouse behavior

Enter focuses the composer when gameplay owns the keyboard. Enter while typing submits a valid nonempty message, then releases focus back to gameplay. Escape releases focus without sending and preserves the draft. Empty Enter releases focus without a network request. Clicking the composer also focuses it; input methods must be able to finish composition before submission.

Acquire chat focus before gameplay shortcuts and reset held movement/queued input when focus changes. While any social text field owns focus, typing P, K, I, H, movement keys or spell keys must not activate gameplay. Existing modal activities keep their input ownership unless the user explicitly clicks chat; closing a modal must not erase chat. Opening a modal while chat owns focus releases the composer safely. Normal world simulation, including ongoing combat, continues while typing.

Only interactive panel controls consume clicks and wheel events inside their bounds. The remainder of the screen retains existing world controls. Scrolling the transcript must not zoom the world. Do not cancel an existing activity merely because a message arrives.

### Friends and blocks

Friends and Blocked are two tabs in a small social drawer opened beside/above the chat panel; closing this drawer never hides chat. Each has a username entry, Add action, sorted rows, and Remove/Unblock actions. Friend rows show Online/Offline, offer Message and Block, and place online friends first. A player cannot add themselves. Duplicate operations return success without duplicate rows. Initial limits are 200 friends and 200 blocks per account.

Resolve usernames through the shared account directory and store relationships by stable account ID, not display text or socket ID. The account service's canonical username rules apply. Use its public player handle; never expose email, login credentials or account metadata through social lookup.

Friendship is one-way and needs no request/acceptance flow. Removing a friend changes only the owner's list and does not block messages. Anyone online may send a private message unless either account blocks the other. A mutual-friends requirement is not implied.

Adding a block atomically removes that target from the block owner's friends list. Adding a currently blocked target as a friend is rejected with an instruction to unblock first; it must not silently undo a block. Unblocking does not restore friendship. The other player's independently saved friends list is not edited.

A block hides that sender's public messages from the block owner's transcript, including retained records, and prevents private communication in either direction. Purge/hide matching retained private messages for the block owner and clear a blocked active private recipient. It does not delete text already received by other players or hide the block owner's public messages from everyone else.

Online status is visible to accounts that list the target as a friend, except when either side blocks the other. A blocked target sees the other account as unavailable; do not disclose whether the cause is a block or disconnection. Private-send failures use the same unavailable response for missing, offline and blocked targets. Friends/block changes appear as saved only after server commit; disable mutations while disconnected or loading the authoritative list.

## Channel rules and location

| Channel | Recipients | Validation |
| --- | --- | --- |
| Local | Sender plus connected eligible recipients within 20 tiles, inclusive, measured by squared Euclidean distance | Same logical world, area and instance; both locations fresh; apply each recipient's blocks |
| Global | Sender plus connected eligible accounts across all areas and worlds attached to this social service | Authenticated connection; apply each recipient's blocks |
| Private | Specified online account and the sender's own confirmed echo | Resolve recipient server-side; reject self, offline or either-direction blocked pairs |

The server derives sender identity/name, channel membership, recipient set, timestamp and message ID. Client requests cannot choose a sender or supply a list of recipients. Private content travels only to the sender and recipient; do not broadcast it with a client-side visibility filter.

Use stable logical world/area/instance IDs. Separate dungeon instances do not hear each other even if coordinates match. Region loading or unknown/stale locations disable Local sends with a clear notice, while Global and Private remain available.

For the current offline game, the explicit development adapter reports its own world/area/instance and finite tile position at up to 2 Hz, immediately invalidates location on travel start, and publishes the destination only after travel finishes. Expire a location after 5 seconds without refresh. Calculate local recipients from the latest accepted positions at send time. This mode provides real chat routing but client-reported proximity is not authoritative or resistant to modified clients.

Production location comes from a trusted world-service adapter bound to the authenticated character and its current ownership generation. Client location updates are rejected in that mode. Drop old-world/old-instance updates after a transfer and expire disconnected owners. Do not enable public local chat using a test position-authority bypass. Adding future worlds must not change relationship keys or the meaning of Global.

## Server components and state

| Unit | Responsibility | Dependency/interface |
| --- | --- | --- |
| Social authentication adapter | Bind connection to the account's active session and public character identity; revoke stale sessions | Shared account backend; explicitly separate loopback fixture adapter |
| Social domain service | Resolve users; apply friend/block rules, channel routing and deduplication | Relationship repository, presence directory, location provider, clock |
| Relationship repository | Commit directed friends/blocks and return authoritative revisions | Shared database with constraints and transactions |
| Presence/location directory | Track authenticated online sessions, logical location and freshness | Session authority and trusted world service, or explicit development provider |
| WebSocket adapter | Validate versioned envelopes, enforce limits, dispatch results and disconnects | Social domain service; no gameplay decisions |
| Godot social client | Own socket, list snapshots, pending requests, reconnect state and bounded scrollback | Transport and public identity/session adapter |
| Godot social panel | Draw chat/social controls and manage input focus | Social client signals and existing FantasyUI theme |

Durable records are directed `(owner_account_id, target_account_id)` friend and block relations with unique constraints, non-self constraints and timestamps; an owner social revision identifies saved changes. Repeated add/remove requests are idempotent. A friend-to-block change commits atomically; storage failure must leave the prior state intact. PostgreSQL integration tests cover concurrent list changes and restart persistence. Local UI preferences may use `user://`; account relations remain server-owned and follow the same account to another machine/world.

Serialize relationship changes and delivery decisions within the initial service, recheck blocks before private/public recipient egress and discard queued entries made ineligible by a block. Complete the block response only after its in-process routing state reflects the committed relation. Deterministic race tests cover message-before-block and block-before-message. Already received text cannot be recalled remotely; the blocking client's retained text is filtered immediately. Multi-worker delivery requires a separately verified ordering/invalidation strategy before rollout.

Presence represents an authenticated chat connection, not a client-selected online flag. Heartbeat every 15 seconds; expire the connection after 45 seconds without liveness. A healthy orderly disconnect removes presence immediately. Replacing/revoking a login closes the previous social connection and clears its location; stale events cannot revive it. Presence exposes Online/Offline only, without precise location or login details.

## Authentication, protocol and limits

Use certificate-validated `wss://` outside explicit loopback development tests. Reuse the account service's in-memory authenticated session in the native client's WebSocket handshake through an adapter; do not store passwords/session credentials on disk or put secrets in endpoint URLs, process arguments or diagnostic events. Apply the account backend's allowed-host/origin policy to handshakes and revoke long-lived sockets when the account session expires, logs out or changes. The WebSocket's initial authenticated account/character mapping is immutable.

The test adapter accepts only server-provisioned fixture identities through disposable test credentials, binds loopback and refuses non-loopback endpoints. No arbitrary client-supplied account ID, name or static secret in shipped source establishes public identity. Test fixtures may persist relationship rows across service restarts, but their identities remain separate from public accounts. Public deployment is incomplete until real shared-session integration and TLS tests pass.

Version 1 uses bounded UTF-8 JSON text frames. Requests carry protocol version, request ID, allowlisted operation and an operation-specific body. Initial operations are send, friend add/remove, block add/remove, snapshot request and heartbeat; only the development mode additionally accepts self-location updates. Responses/events distinguish ready/snapshot, request result, message, presence, social revision, heartbeat and connection errors. Recipient handles are resolved on the server. Unknown operations, malformed types and unsupported versions fail explicitly without executing partial actions.

Initial concrete bounds:

- Trim outer whitespace; require 1-280 Unicode code points and at most 1,120 UTF-8 bytes per message. Reject line breaks and nonprinting control characters; preserve ordinary Unicode text. Enforce the same policy server-side and show a composer character counter.
- Limit application frames to 8 KiB before JSON parsing. Bound encoded/decoded object depth, string lengths and operation fields; reject nonfinite numbers, invalid position arrays and oversized request IDs.
- Per-account sends: token bucket 1 message/second, burst 5, shared across all channels. Social mutations: 2/second, burst 10. Bound unauthenticated connections/handshake time separately from authenticated users.
- Maximum 128 queued application events or 256 KiB per connection, whichever is reached first. If a recipient stays slow, close its connection and show reconnection feedback; do not grow the queue or replay a backlog indefinitely.
- Server assigns message IDs and per-connection event order. Deduplicate request IDs within the same live session using a bounded 256-entry/60-second result cache. Do not deduplicate solely by text. Social mutations remain naturally idempotent after restart; chat sends are not automatically replayed after ambiguous connection loss.
- Initial configurable admission cap: 50 authenticated social connections, independent of world capacities. A full service rejects admission clearly without replacing another player. This is a test target/configuration default, not evidence of measured capacity; no schema/ID assumes 50 is permanent.

Do not record message bodies, private recipients' text, credentials or full packets in normal logs or ADC context. Diagnostics may include operation/result, opaque IDs, counts, connection health and non-secret errors. Messages have no server-side archive in this release. Operators' deployment configuration, database files, credentials and generated test evidence stay outside version control.

## Delivery and failure semantics

The composer creates a pending row. A successful result means the server accepted and routed the request; it is not a read receipt or a guarantee that a remote player saw it. An offline/blocked private recipient produces an unavailable result, with no successful outgoing private echo. Routing and the sender's confirmed row share one message ID to avoid duplicate echoes.

There is no offline private-message queue and no reconnect replay of missed chat. A socket can fail after server acceptance but before display; mark an unanswered pending request as uncertain and let the player retry deliberately rather than automatically duplicating messages. Requests that definitely failed validation show a specific safe reason and preserve the draft.

Connection states are Offline, Connecting, Connected and Reconnecting, with actionable brief notices inside the persistent panel. Retry recoverable network loss with bounded backoff of 1, 2, 4, 8 and then at most 15 seconds; allow manual retry. Authentication expiry requires normal login rather than endless reconnect attempts. Preserve current scrollback while disconnected, disable send/social mutations, and obtain fresh lists/presence/location before re-enabling applicable controls. On identity change, clear private history, drafts, cached lists and pending requests before presenting the next account.

Storage unavailability prevents successful relationship changes and new sessions whose block state cannot be loaded. Existing sessions stop sending/delivery if authoritative block validation is unavailable; show social service unavailable and keep gameplay running. Do not bypass blocks or replace saved lists with empty defaults after a database error. Chat failure does not freeze, reset or disconnect the local gameplay simulation.

## Implementation boundaries and acceptance

The implementation plan should map focused Godot scripts under `godot_client/scripts/social/`, one autoload/overlay integration, narrow `main.gd` input/layout hooks, backend social domain/repository/transport modules and external-output test runners. Reuse existing FantasyUI and account/world adapters. The exact account-backend directory and API come from its approved implementation; do not invent a parallel account scaffold in chat code. Preserve `.uid` files and source import settings.

Required acceptance evidence:

1. **Real clients:** start the actual service and at least three separate Godot clients with distinct authenticated identities. Show Global delivery across areas, Local delivery at 20 tiles and rejection beyond it, separation by world/area/instance, and Private delivery visible only to its two participants. Self echo appears once.
2. **Identity and malformed requests:** reject unauthenticated access, sender/account substitution, stale/revoked sessions, unsupported versions, malformed/oversized packets, nonfinite positions, invalid recipients and rate-limit floods without affecting an innocent client. Verify known secrets and private message bodies are absent from logs.
3. **Social rules:** exercise unilateral friendships, duplicate add/remove, case-normalized lookup, self rejection, list caps, presence, block in either direction for Private, recipient-specific public filtering, friend-to-block atomicity, history filtering and no automatic restoration on unblock. Race message dispatch with block acknowledgment.
4. **Persistence:** restart client and service against the same PostgreSQL test database; lists and revisions remain correct. Test concurrent mutations and failed commits. Test fixture/SQLite-only persistence does not certify production database behavior.
5. **Location and reconnect:** stale/unknown locations prevent Local; Global/Private continue during area travel; production mode rejects client location claims. Exercise heartbeat expiry, old-session updates, forced disconnects, bounded slow-reader queues, reconnect/resnapshot, unavailable recipients and ambiguous sends without automatic duplicate replay.
6. **Visual/input:** inspect rendered UI at 1280 by 720 and a smaller supported window. Verify background transparency, legibility, no fading, tab labels/unread counts, scroll behavior, food-control clearance, click/wheel containment and surviving area changes. Type gameplay shortcut letters while chat, social fields and modal activities own focus; movement, menus and activities must behave as specified.
7. **Runtime regressions:** use the installed engine for editor import/parse and main-scene startup, inspect actual script errors as well as exit codes, and run relevant interaction/food/cooking regressions for touched input paths. Preserve controlled test evidence outside Git. No gameplay-capacity claim follows from a three-client test.
8. **Public integration:** use the real shared account service, PostgreSQL and trusted world-location adapter; verify valid TLS and rejection of invalid certificates/plaintext, logout/session revocation and cross-world relationships. A local fixture result is reported as local validation, not completion of this acceptance item.

Completion requires the agreed working server and UI plus the relevant identity/location integration, reviewed diffs, passing applicable checks, a task-branch commit/push to verified `origin`, and a PR when ready. Report explicitly any unmet dependency or public-integration acceptance item; do not call the whole feature delivered based only on a fixture. No deployment or external messages to real users occur during specification work.

## Technical references

- [Godot 4.5 WebSocketPeer](https://docs.godotengine.org/en/4.5/classes/class_websocketpeer.html): native client transport, regular polling and TLS options.
- [Django Channels authentication](https://channels.readthedocs.io/en/stable/topics/authentication.html): shared Django session authentication for WebSocket connections and adapter boundaries.
- [Django Channels layers](https://channels.readthedocs.io/en/stable/topics/channel_layers.html): production Redis integration and the process-local limitation of in-memory test layers.

## Review handoff

The user approved the conversational feature design. This written specification adds explicit integration constraints from the pre-existing account/world designs and must be reviewed before implementation planning. After approval, prepare the implementation plan with the writing-plans skill, identify the account dependency and have the user select the execution method before product code changes.
