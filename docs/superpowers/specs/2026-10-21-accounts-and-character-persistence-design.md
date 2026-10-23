# Accounts and persistent characters

Date: 2026-10-21

Status: Proposed account/persistence design for review. No account service, database, registration UI, email delivery or save implementation exists as a result of this document.

## User requirements and delivery priority

Players create a username/password account and resume their character after logging out or returning in another session. The user also wants optional email linking and email-based password reset in the future. Preserve the previously agreed growth paths: larger populations within a world, additional worlds, and shared character progress across those worlds.

Accounts and persistent characters are required for the first usable online game. They are not deferred until several worlds exist. The movement-only network fixture remains an isolated engineering test. Delivery order is foundation 1A, accounts/persistence 1B, then the complete gameplay migration; no real progression is enabled online before 1B's durability and ownership checks pass. Email linking/recovery is a later, separately enabled feature, with compatible identity/schema boundaries established now.

The initial assumption remains one character per account, with stable separate account and character IDs. Do not use a username, email address, peer ID or world ID as the character's storage key. Usernames identify login; a later display-name change, email link or world move must not replace a character or its saves.

## Approach

Recommended: a shared account/character backend using Django's maintained authentication/password/session facilities and a transactional PostgreSQL database. Gameplay simulation remains in Godot. The backend owns account credentials, world admission, character ownership and durable transactions; Godot worlds own validated gameplay and submit trusted state changes through a narrow service API. This reuses a standard credential implementation without porting gameplay into Python.

A managed identity provider is another workable option, with provider configuration, pricing and account migration dependencies. The recommended self-hosted account backend fits the existing private project and leaves character persistence under the game's control. Do not write custom password cryptography or couple save schemas to an email vendor.

Use a custom Django user model from its first migration so stable IDs and optional verified-email fields do not require swapping the account model later. Pin supported dependencies and choose deployment-compatible versions in the implementation plan; no dependencies or services are installed during this design step. PostgreSQL is the integration-test and production database for ownership, concurrency and transaction behavior; passing only an in-memory or SQLite test does not certify those guarantees.

## Initial player flow

1. **Create account:** enter an available username, password and confirmation. Email is not required. Successful registration atomically creates the account and its initial character using approved server defaults, then returns a clear success response. Repeated clicks or concurrent requests cannot create duplicate usernames or multiple initial characters.
2. **Log in:** authenticate using username/password over HTTPS; show a generic invalid-credentials result for an unknown username or wrong password. The account service rotates the login session and returns the authenticated account's own character summary. The client keeps the session in memory and clears the password input after submission. Initial version has no remembered password or disk-persisted login token.
3. **Enter world:** obtain a short-lived, single-use world-bound admission ticket through the authenticated account service. The world consumes the ticket through an authenticated backend call, obtains exclusive character ownership and loads the latest committed save before creating the actor. Passwords and reusable account-session credentials are never sent through gameplay RPCs.
4. **Play:** the server validates actions, persists durable results, and sends the committed changes to the owner. Clients cannot upload a character save, choose an account/character to mutate, or override saved item/skill values.
5. **Log out:** stop accepting gameplay commands, neutralize movement, finish or transactionally cancel pending activities, flush the final checkpoint, then remove the actor and release ownership. Show logout success only after durable completion. A persistence failure yields an explicit retry/recovery state, never a false successful save.
6. **Return:** authentication and world admission load the same character ID and committed progress. An already active character needs the defined authenticated reconnect flow; logging in again cannot create a second active copy or reset its resources/cooldowns.

The registration/login forms do not expose framework, database or worker details. Account errors offer an actionable status without printing backend traces, secrets or other players' information.

## Credential and session rules

- Username policy for the initial version: 3-20 ASCII letters, digits or underscores. Trim username input, preserve chosen display casing and enforce a unique lowercase login key in the database. Username case never creates a second account. Usernames remain separate from future email login/recovery policy.
- Password policy: 15-128 Unicode code points after NFC normalization, with spaces allowed. Do not trim, truncate, require arbitrary symbol mixtures or impose periodic changes. Reject commonly used/compromised passwords using a locally available validator/blocklist; never send a submitted password to a third party. Password confirmation uses the same normalization.
- Store only Django-managed salted Argon2id password hashes, including their algorithm/work-factor metadata; never plaintext or reversible password encryption. Use the maintained hasher, keep upgrade support, and benchmark its cost under bounded login concurrency. Meet at least the OWASP 19 MiB / 2 iterations / parallelism 1 Argon2id profile, or a stronger reviewed profile; do not lower the cost to make load tests pass.
- Implementation ruling: the native Godot adapter uses opaque bearer sessions, with only their digests stored in PostgreSQL. It does not use browser cookies or a cookie/CSRF exchange. A new login rotates the session, expiry is enforced, and logout revokes it. Remote account requests require HTTPS. Gameplay ownership is separately limited to one active account/character session across all worlds. See `backend/README.md` and `godot_client/docs/Networking.md` for the installed behavior and current development-only transport boundary.
- Bound registration/login attempts per account key and source, with shared enforcement across backend replicas and bounded password-hash workers. No indefinite account lock triggered solely by unauthenticated requests. Use comparable authentication work for unknown usernames and wrong passwords. Exact windows/concurrency limits are pinned and tested in the implementation plan.
- Account/client and service/world communication require authenticated TLS outside isolated loopback tests. For Internet ENet, use Godot's certificate-validated DTLS transport before any real admission ticket or private gameplay state is exchanged. Test unsupported DTLS, wrong certificates and plaintext peers explicitly; no insecure fallback. The foundation fixture's plaintext loopback transport cannot be promoted to production by changing only its bind address.
- Never log passwords, hashes, session cookies, CSRF secrets, admission tickets, reset tokens, email bodies or complete save payloads. Audit operation/result and opaque IDs only, with protected access and retention. Passwords/hashes/email addresses never appear in world snapshots or character summaries sent to other players.

## Data boundaries and expansion

| Record | Required information and invariants |
| --- | --- |
| Account | Stable UUID; unique canonical username; Django credential hash; account status/authentication version; nullable future email and verification timestamp; creation/update timestamps |
| Character | Stable UUID; account foreign key unique for the first release; monotonic save revision; save/content schema versions; approved initial state; last durable-save timestamp |
| Character state | Location/world/region/instance, HP/mana and relevant restrictions; inventory and equipment using canonical item IDs; currency; skill levels/XP; existing activity containers such as fishing pale/quiver and quick-food selection |
| Progress components | Individually versioned, validated state sections keyed by character and component ID; allows future quests/unlocks/regions without replacing identity or blindly accepting arbitrary JSON |
| Gameplay ownership | Unique account/character owner, world/region identity, lease deadline and monotonic fencing generation; every save validates owner and expected revision |
| Operation journal | Unique server-issued operation ID and durable result together with character revision; retrying one operation cannot issue another reward or consumption |
| Account sessions/admission | Revocable session state and short-lived, world-bound ticket digests/nonces; purpose/expiry and atomic single-use checks; no raw reusable secrets in public state |

Use typed models/constraints for identity, ownership, revisions, inventory counts and currency. Extensible state components have server-defined schemas and migrations; an unknown component or invalid/negative/overflowing quantity is rejected. Protect foreign keys and unique constraints in the database, not only in request handlers. A server-owned initial character is created exactly once; missing/corrupt saves cannot silently overwrite an established character with starter defaults.

The client-facing account API exposes registration, authentication, the owner's character summary, world admission and logout. Durable save/load, ownership and gameplay transaction endpoints are service-only, authenticated and scoped to the owning world/character/generation. Keep account authentication, character repositories, transaction validation, mail delivery and Godot rendering separate. Changing the mail provider or adding another world must not change gameplay save keys or password handling.

## Save policy and failure behavior

**Durable results:** item/currency/XP gains and costs, equipment changes, skill changes and other progression updates are one database transaction with an idempotency key and expected revision. Committing a reward and its deduplication record is one operation. The server confirms success only after the transaction commits; local UI animation or an RPC acknowledgment is not a durable result. Configure normal durable database commits; do not disable durability to improve benchmark numbers.

**Checkpoints:** default interval is 5 seconds of active play for server-owned position and transient HP/mana/cooldown/activity restrictions, plus region transitions, orderly logout and clean server shutdown. Checkpoints validate the same save revision and ownership generation as progression transactions. Persist remaining durations/restrictions with defined offline semantics; reconnect cannot refresh health, clear a combat restriction or duplicate reserved ingredients. A sudden server failure may restore movement/transient state to the last checkpoint; it must not discard a progression operation already confirmed as committed.

The world serializes each character's pending mutations through one authoritative queue. A stale checkpoint must not overwrite a newer inventory/XP transaction. On ambiguous commit timeout, freeze dependent mutations and query/retry the same operation ID; do not assume failure, consume twice, refund twice, or release ownership to another writer. Save workers use bounded queues and batched/coalesced transient checkpoints while preserving transaction order. Database latency does not block the Godot simulation thread or permit unbounded queued gameplay.

**Connection loss:** neutralize input, retain exclusive ownership for a configured reconnect grace period and persist authoritative cleanup. If the client never returns, finalize the saved character before release. If storage is unavailable or the final outcome is unresolved, quarantine that character from new admission until recovery establishes the committed state. Do not grant a new world's writer a stale starter/save copy just to make reconnect work.

**Process failure:** the shared backend fences old worlds, restores the last committed revision and resolves unfinished operations before admitting a replacement. Old world processes cannot later overwrite recovery state. Recovery must work after server and backend restarts, not only after graceful client logout.

**Storage operations:** establish encrypted automated backups and a tested restore procedure before hosting persistent real-player progress. Keep account secrets and backups out of Git. Backups address storage loss; ordinary gameplay/session correctness must not rely on restoring the entire database. Report the actual backup retention/recovery interval in deployment documentation rather than promising zero loss under every infrastructure failure.

## Optional verified email and later password recovery

At launch, reserve nullable email/verified-at fields and a separate mail-delivery interface; registration works with neither. No mail is sent and no SMTP/provider credentials are required for 1B. A future schema migration may add pending-email and token records without altering account/character identity or existing saves.

Later flow:

1. An authenticated player adds an email address through account settings after recent password reauthentication. Send a purpose-bound, single-use verification link to the proposed address. A pending/unverified address cannot authorize password recovery.
2. Verification activates that recovery address. An email change requires reauthentication and verification of the replacement; do not silently replace established recovery information. Notify established addresses of relevant changes and define compromised-account recovery separately.
3. A forgotten-password request accepts a username or verified recovery address and gives the same generic response whether an eligible account exists or not. Bound per-account and per-source requests and queue mail delivery independently so response behavior does not enumerate accounts.
4. Use a cryptographically random reset token with at least 256 bits of entropy, store its digest with purpose/account/expiry, expire it after 30 minutes and consume it atomically on use. Use an allowlisted HTTPS reset origin; no request-controlled host or redirect may receive the token. Avoid token leakage through logs, analytics or referrers.
5. A valid token sets a new password using the same policy/hasher. Revoke prior account sessions, unused admission/reset tokens and active gameplay authentication, safely persist/terminate existing gameplay ownership, then require normal login. Do not email a password or automatically log the requester in after reset. Send a reset-completion notice without the password.

An account without a verified recovery address cannot use email password reset. The launch UI must not imply an unimplemented recovery feature is available. Linking an email later preserves every existing save.

## Milestone 1B acceptance and implementation handoff

Plan this subsystem separately from the six-task networking foundation, with an explicit backend/admission adapter connecting them. Approval of this written addition is followed by a concrete 1B implementation plan; it does not authorize skipping tests or claiming the whole gameplay migration is complete.

- Register, log in, create the default character once, update its authoritative fixture state, log out and return to exactly the same committed character data. Restart Godot/backend processes and repeat using persistent database storage.
- Cover username case collisions, concurrent registration, invalid/long input, normalized Unicode passwords, correct/incorrect credentials, rate limits, session expiry/revocation and absent-email registration. Check hashes through the maintained framework; ensure known test secrets do not appear in logs/replication.
- Round-trip every existing durable character field, including nested containers/equipment/progression, with schema validation. Client-supplied save/account/character overrides fail without changing database rows. Corrupt/unknown schemas yield recoverable errors rather than default overwrites.
- Inject failure before commit, after commit but before response, during checkpoint/progression overlap, client loss, world death and ownership transfer. Results are committed exactly once, stale writes are rejected, and retries cannot duplicate or discard confirmed progress.
- Exercise real PostgreSQL transaction/concurrency tests and two attempted world sessions for one account. Mocked repositories and in-memory state alone do not demonstrate persistent or exclusive ownership.
- Verify HTTPS/DTLS admission and invalid-certificate/plaintext rejection before public access. Test backup restoration in a separate database without overwriting real progress. Preserve existing offline gameplay checks.
- Keep mail/token verification behavior specified for future work; implement and run replay/expiry/generic-response/session-revocation tests before enabling email recovery. Do not send real external email during this design step.

No permanent database/deployment, mail provider or credentials are provisioned in this change. The implementation plan must identify an existing PostgreSQL service or provision a local development database through the normal development workflow, without claiming that a database has already been installed or tested.

## Sources

- [Django authentication](https://docs.djangoproject.com/en/5.2/topics/auth/default/) and [password management](https://docs.djangoproject.com/en/5.2/topics/auth/passwords/): maintained account/session/password interfaces and Argon2id configuration.
- [Django custom users](https://docs.djangoproject.com/en/5.2/topics/auth/customizing/): establish the custom account model in its first migration.
- [OWASP password storage](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html): adaptive salted password hashing and Argon2id profiles.
- [NIST SP 800-63B password verifiers](https://pages.nist.gov/800-63-4/sp800-63b.html): password length/normalization/blocklist policy; this game design does not claim certification.
- [OWASP password recovery](https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html): generic responses, bounded requests, secure single-use tokens and session invalidation.
- [PostgreSQL transactions](https://www.postgresql.org/docs/current/tutorial-transactions.html): atomic changes to related state.
- [Godot 4.5 ENetConnection](https://docs.godotengine.org/en/4.5/classes/class_enetconnection.html): certificate-validated DTLS support and setup ordering.
