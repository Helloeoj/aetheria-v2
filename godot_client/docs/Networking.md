# Online accounts and authoritative worlds

The normal game starts at `scenes/Login.tscn`. Create a username and password,
then log in to resume the same character. On this Windows development checkout,
the login screen starts the local account service and world in hidden processes.
Wait for startup before submitting credentials. No password is stored by the
client. Email linking and password reset are reserved for a later release.

## Run and storage

From the repository root:

```powershell
./tools/online.ps1 start
./tools/online.ps1 status
./tools/online.ps1 stop
```

`stop` saves characters and releases their ownership before stopping the world;
it refuses to force-kill a world whose saves cannot complete. Account storage
remains running. See `backend/README.md` for database setup, backups and tests.
Private runtime data lives outside Git in `%LOCALAPPDATA%/Aetheria/online`.
The local development API uses port 8780, PostgreSQL 55432, and the world 24567.

Progress is stored in PostgreSQL, keyed by stable account and character UUIDs.
The server initializes new characters, validates versioned saves, and records
inventory, equipment, experience, health, mana, gold, fishing pale, cooldowns,
region and position. Login restores these values. Invalid saves are rejected
without replacing them with a new character. Normal saves checkpoint transient
state every five seconds; economy/progression changes save promptly, and clean
logout atomically saves the final state and releases ownership. A machine or
process crash can lose recent movement/health within the checkpoint interval.

## Developer testing

Choose **Developer sandbox — unsaved testing** on Login to use the original
local map and its F5 monster menu, F6 item menu, F7 sprite viewer, K skill panel
and P fishing practice. F near an authored fishing spot opens fishing normally.
The sandbox uses a separate local character and never saves to an online account.
Its **Online login** button returns to Login. Save/log out before switching from
an authenticated online character; active online state cannot enter the sandbox.
Real online worlds retain server authority and never accept client debug grants.
Region startup does not automatically add monsters; combat regression encounters
exist only in explicit developer test fixtures.

## Authority and recovery

Clients send intents through `Network`: movement, targeting, attacks, spells,
equipment, food, crafting, purchases, fishing, cooking, item pickup/drop and
portal use. The server validates identity, payload bounds, sequence, inventory,
range, map collision, skill requirements and server timing. Client maps display
snapshots and send input; they do not advance the online simulation. Debug
grants and practice controls are disabled online. Directly opening development
map/test scenes still runs the existing offline sandbox, with no online saves.

`world_host.gd` owns admission, persistence and the shared region registry.
`authoritative_region.gd` owns gameplay and server map geometry;
`region_activities.gd` owns fishing/cooking sessions. `character_codec.gd`
translates approved domain state to/from primitive save data.
`network_manager.gd` handles transport and `online_world_view.gd` projects it.
The account API uses revocable bearer sessions and single-use world tickets;
password hashing uses Django Argon2id. It does not use browser cookie sessions.

Each character has one renewable, fenced ownership lease across all worlds.
Saves use expected revisions and idempotent operation UUIDs. Uncertain responses
retry the same payload and endpoint. An old pending save must finish before a
fresh final release captures current state. Saving failures pause gameplay;
expired ownership removes the old actor so reconnect cannot use stale state.
Disconnect keeps the actor in the world for 30 seconds before finalization.
Logout during combat is rejected. Voluntary ground drops become public only
after the source removal is saved; pickups reserve drops until the receiving
character is saved. Ground drops are transient world state and are not restored
after a world process crash.

## Capacity and expansion

The initial configured admission target is **50 players in one shared world**.
This is a test target, not a measured performance guarantee. Private
`world.json` can configure `max_players`, `port`, `snapshot_hz`, `interest_radius` and
`world_id`; example:

```json
{"world_id":"world-1","max_players":200,"snapshot_hz":10,"interest_radius":32}
```

Admission and actor registries use stable IDs and dictionaries. The current
ENet adapter supports 1–4079 admitted players plus bounded pending connections;
there are no fifty-slot gameplay arrays. Simulation runs at 30Hz, snapshots at
10Hz by default. Public actors are indexed spatially once per region, then
filtered around each player. Snapshots are compressed and sent in bounded
packets with incomplete/old assemblies discarded. Each hosted region has its
own collision world and multiple players share its monsters and drops.

Increasing capacity still requires measurement of tick time, latency, network
bandwidth, database load and hot spots. Thousands of simultaneous players have
**not** been demonstrated. Multiple public world discovery/selection,
supervised deployment, world-process orchestration and distributing busy
regions across workers remain expansion work. Stable world/region/character
IDs and fenced database ownership provide the boundaries for that work.
The current login adapter joins `world-1` on port 24567; an adapter for a custom
world must use its matching ID/port. A world selector is not implemented yet.

## Current deployment boundary

The installed world deliberately binds to loopback. The client refuses remote
plaintext gameplay connections. This build is usable for local development;
it is not an Internet multiplayer deployment. Public play requires validated
encrypted gameplay transport, HTTPS account hosting, backups and operational
configuration. No production hosting or outgoing email was provisioned.

The previously installed social service still uses its separate development
profile credential and location channel. Linking chat identity and proximity
to the authenticated account/world authority remains integration work; it does
not grant access to character saves or gameplay commands.

## Validation

```powershell
./tools/test_accounts.ps1 -Integration
python ./tools/test_networking.py --godot <installed-Godot-console.exe>
python ./tools/test_online.py --godot <installed-Godot-console.exe>
& "$env:LOCALAPPDATA/Aetheria/online/venv/Scripts/python.exe" ./tools/test_online_concurrency.py --godot <installed-Godot-console.exe>
```

Godot developer scenes cover character serialization, authoritative regions,
activity input, snapshot packet assembly and persistence lifecycle recovery.
The live session runner uses fresh local test accounts and verifies the actual
Godot client → world → PostgreSQL → logout → login path. Credentials and test
evidence are written outside Git. The concurrency runner requires already running
local services and never restarts them. It checks two real clients sharing a
region, a committed item drop and pickup between them, duplicate login rejection,
forced expiry of its own test character's lease, actor retirement, and both
inventories restored on reconnect. It uses fresh test accounts and expires only
their leases. Keep machine logs, private configuration and tokens out of Git.
Recorded results and untested boundaries are in `docs/OnlineValidation.md` at
the repository root.
