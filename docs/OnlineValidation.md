# Online implementation validation — 2026-10-22

Validated against the installed Godot 4.5.1 Windows engine, PostgreSQL 17.11,
the account HTTP process and a separate headless authoritative world process.
Runtime data, credentials, screenshots and native logs remain outside Git.

| Check | Observed result |
| --- | --- |
| PostgreSQL account suite | 11 tests passed, including concurrent registration, claims and save retries |
| Real account HTTP restart | Identity, session, character state and operation journal restored after process restart |
| Character save codec | 13 checks passed |
| Region authority and online activity panel | Both smoke scenes passed; actual map collision, command rules, staged item transfers and serialized numeric inputs covered |
| Snapshot transport/protocol | 1,401 checks passed: bounded chunks, order, incomplete streams, expiry, integrity and malformed versions |
| Host persistence lifecycle | 54 checks passed: exact operation retries, final release recovery, fencing, replacement actors, movement and queued commands during saves |
| Frozen combat lifecycle | 15 checks passed: paused casts/projectiles/effects and terminal cleanup |
| Actual map travel | 65 checks passed: Outskirts/Golem/Tavern round trips, server markers, shared region ownership and retirement during travel |
| Live two-session round trip | Same character and final server position restored on the next login; forged gold grant rejected |
| Live simultaneous clients | Shared region visibility, duplicate admission rejection, expired lease cleanup and reconnect passed |
| Live durable item transfer | First inventory 30→29, second 30→31; both quantities restored after reconnect |
| Existing gameplay regressions | Nine serial suites passed 7,598 checks; final bronze combat rerun passed 2,995 and orb combat passed 213 |
| Editor import and normal startup | Completed with no parser/runtime errors |
| Login and registration visual inspection | Both 1280×720 renders showed all fields, buttons and messages without clipping |

The final live server log and concurrency client logs contained no errors or
warnings. Reproduce with `tools/test_accounts.ps1 -Integration`,
`tools/test_networking.py`, `tools/test_online.py` and
`tools/test_online_concurrency.py`; see `godot_client/docs/Networking.md`.

Capacity configuration accepts 51, 200 and 4,079 players and rejects fractional
or unsupported limits. These checks validate configuration and data boundaries,
not throughput. Fifty simultaneous players, thousands per world, public
encrypted transport, account-linked social identity, mail recovery, automated
backups and journal retention have not been certified or deployed by this work.
