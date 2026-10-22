# Aetheria account and character service

Run from the active game checkout on Windows:

```powershell
./tools/accounts.ps1 start
./tools/accounts.ps1 status
./tools/test_accounts.ps1 -Integration
./tools/accounts.ps1 stop
```

`start` creates a private Python environment, installs `backend/requirements.txt`,
and installs the [official EDB PostgreSQL binaries](https://www.enterprisedb.com/download-postgresql-binaries)
if needed. It runs PostgreSQL 17.11 on `127.0.0.1:55432` and the account API on
`http://127.0.0.1:8780`. Both processes run without visible windows. `stop` stops
the API; the local database remains available. Re-running `start` is safe.

The private directory is `%LOCALAPPDATA%/Aetheria/online` (override with
`AETHERIA_ACCOUNT_DATA`). Its Windows ACL grants the current user and SYSTEM
access. It holds `config.json`, `server.key`, the database, runtime and logs.
Never commit or share these files. Back up PostgreSQL with `pg_dump`, including
accounts, characters and their journal. Deleting this private directory loses
local accounts and saved characters. The game server reads `server.key` from
that private directory; the account service uses it as `AETHERIA_SERVER_KEY`.
Clients never receive it.

The public endpoints accept JSON and return `{ok:true,...}` or
`{ok:false,code,message}`. No cookies or email are involved:

| Endpoint | Request / response |
| --- | --- |
| `POST /api/register` | `{username,password,password_confirmation}` → `{ok,account_id,character_id}` |
| `POST /api/login` | `{username,password}` → `{ok,token,account_id,character_id,username}` |
| `POST /api/logout` | Bearer token → `{ok}`; invalidates outstanding admission tickets |
| `GET /api/character` | Bearer token → owner IDs, username, revision, initialized and email_verified; never full save data |
| `POST /api/admit` | Bearer token, `{world_id}` → `{ok,ticket}` |
| `GET /health` | `{ok,service:"aetheria-accounts",schema:1}` |

Usernames contain 3–20 ASCII letters, digits or underscores, with a database
unique lowercase key. Passwords contain 15–128 Unicode codepoints after NFC
normalization; spaces are preserved. Django Argon2id hashes are persisted.
Incorrect and unknown credentials return the same error. Persistent per-IP and
per-name limits allow 20 attempts per minute and only two password hashes may run
concurrently per worker. Sessions last 12 hours. A new login replaces prior login
sessions; it does not steal an active gameplay lease. Password reset and email
verification routes return `not_available`; nullable email and verification
timestamp fields reserve future schema. No outgoing email is implemented.

All internal requests require `X-Aetheria-Server-Key`:

| Endpoint | Request / response |
| --- | --- |
| `POST /internal/claim` | `{ticket,world_id}` → `{ok,lease_token,character_id,account_id,username,revision,state}` |
| `POST /internal/save` | `{lease_token,character_id,expected_revision,operation_id,state}` → `{ok,revision}` |
| `POST /internal/release` | Same as save; atomically saves and releases ownership |
| `POST /internal/heartbeat` | `{lease_token,character_id}` → `{ok}` |

Admission tickets expire after 30 seconds and can be claimed once for their
specified world. A character has one active gameplay owner across worlds.
Claiming an expired lease increments its generation and replaces its opaque
token; old writers are fenced. Leases last 30 seconds; heartbeat every 10 seconds.
Successful saves also renew the lease. Every save locks the character, checks
ownership and expected revision, then commits the new state and immutable journal
entry in one database transaction. A release does the same while clearing the
lease. A retry with the same operation UUID and identical payload/lease returns
its prior revision, including after release or service restart. Reusing an
operation UUID with different data is rejected. Each new save requires a fresh
UUID. A stale lease cannot create a new operation.

A fresh character has state `{}`. The trusted Godot server creates its approved
initial character and saves a state containing integer `version:1` before
acknowledging gameplay admission. Save state is a primitive JSON object bounded
to 128 KiB, 10,000 nodes, depth 12 and string length 4096. Godot owns domain
validation, inventory and progression authority. Client-authored saves are never
accepted. Expected revisions and successful save revision numbers are integers.

Useful recoverable error codes include `bad_credentials`, `unauthorized`,
`username_unavailable`, `invalid_password`, `password_mismatch`, `rate_limited`,
`busy`, `invalid_ticket`, `character_busy`, `stale_lease`, `revision_conflict`,
`operation_mismatch`, `invalid_state` and `service_unavailable`. Clients must not
fall back to an offline character after failed authentication or save recovery.

Loopback plaintext HTTP is for development. Remote requests require HTTPS;
binding outside loopback also requires `AETHERIA_PUBLIC_ORIGIN=https://...` and
PostgreSQL. For deployment, provision a TLS reverse proxy, explicitly configure
`AETHERIA_ALLOWED_HOSTS` and a narrowly trusted proxy, set private server and
Django keys, use a dedicated least-privileged PostgreSQL application role with
separate migration credentials, provision backups, and run a supervised service.
Do not expose the local PostgreSQL bootstrap administrator or port publicly.
The local launcher is not an Internet deployment tool. SQLite can be selected
only explicitly as `database:"sqlite-development"` in private config; that mode
runs one process with one request worker and does not validate PostgreSQL races.

The tests use a separate PostgreSQL test database. Integration verification uses
a uniquely named temporary database and real HTTP across two service processes;
it does not create test users in the installed live account database. Tests
cover registration races, simultaneous cross-world claims, duplicate save races,
hash and token secrecy, NFC passwords, throttling, ticket expiry, fencing,
revision conflicts, atomic release, logout and unavailable email/reset flows.
