# Closed beta delivery

Spec and implementation plan. Authorized by the user to complete on the active PC.

## Global constraints

Preserve the game, login, saves, original minigames and unrelated local work.
Leave Sentinel unchanged. No secrets, server implementation or developer tools in
tester packages. Client runtime files necessarily remain inspectable; never promise
perfect client secrecy. Use only free services. Downloads are capped at 500000 B/s.
Keep public endpoints configurable for moving to a provider later. Do not expose
unencrypted admission tickets, internal account routes, database or source folders.

## Task 1: Admission and invitations

Implement backend closed-beta policy using private config `beta.json` under account
DATA, loaded on each request: schema=1, enabled=true, release_id (1..80 ASCII
letters/digits/._-), public connection fields optional. Disabled/missing retains
existing local development behavior. Invalid enabled config fails closed.
Add hashed single-use expiring invite codes; registration body `invite_code` consumes
one atomically when beta enabled. Existing accounts require an explicit access grant
when beta enabled; do not delete or alter their saves. Local admin CLI creates invites,
grants/revokes accounts, lists non-secret status. Never print stored credentials.
`api/admit` requires `release_id` matching active release; store it on Admission.
`internal/claim` requires same `release_id` from server and admission, rechecks grant
to reject revoked tickets. `/api/release` GET returns only approved public connection
metadata and release_id, no paths/secrets. Existing API contracts work disabled.
Tests: valid/invalid/expired/reused invite, concurrent consumption, granted/revoked
existing user, old release and revoked ticket rejection, local regression.

## Task 2: Encrypted game connections and client profile

Add fail-closed pinned DTLS remote support to ENet, retain loopback development.
Private server key/certificate are outside repo. Public certificate ships in profile.
Profile res://data/beta_client.json schema=1, release_id, account_url HTTPS,
world_host, world_port, world_id, tls_name, tls_certificate (resource path).
Server world.json optionally uses tls_key/tls_certificate private file paths and
release_id. Server forwards its own release_id on claim. Client forwards profile
release_id on admit. Tester feature forbids sandbox/local-service startup. Registration
adds invite field only for tester builds. Preserve original UI/controls otherwise.
Validate real DTLS client/server, invalid cert failure, existing local suite.

## Task 3: Distribution and launcher

Use restricted itch.io project and revocable download keys. Sanitize a temporary
staging Godot project, export Windows tester executable with compiled scripts and
embedded PCK; exclude server scripts, tests, tools, Sentinel and raw source. Audit
artifact contents and boot it. Build a standalone launcher with version preflight,
mandatory updates, integrity verification and atomic installation; prefer official
butlerd for authenticated private itch downloads and incremental updates. No creator
token in launcher. Failed/partial updates must not launch mismatched clients.

## Task 4: Public service installation

Free Playit UDP relay to loopback encrypted world, host agent only. HTTPS account
ingress through narrow allowlisted proxy and Cloudflare tunnel. Stable free HTTPS
bootstrap via Workers if required. Use own invite enforcement and per-client rate
limits. Accounts may require human CAPTCHA/email/terms confirmation; continue all
independent implementation while pending. Install one-click operations and document
invite/update/stop flows without requiring networking expertise.

## Task 5: Integration and completion

Review security boundaries, run backend and networking regression, package audit,
real public-endpoint smoke tests, update mismatch/failure tests, and verify durable
saves. Clearly distinguish same-PC public relay testing from outside-network testing.
Install local result preserving saves. Selectively stage only task changes, review,
commit and push to verified Helloeoj/aetheria-v2 origin on codex/closed-beta-launcher.
Do not describe section 3 as complete while external setup or required tests remain.
