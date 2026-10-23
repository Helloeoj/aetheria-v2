# Closed beta on this PC

Players use the Aetheria Launcher. It signs into itch.io, checks the approved game
release, installs the matching build, and verifies the executable before Play.
Their existing Aetheria game login and character saves remain separate.

The project is restricted at https://helloeoj.itch.io/aetheria-beta. The stable
account/version address is https://aetheria-beta.helloeoj.workers.dev. Encrypted
game traffic uses the free Playit relay; only this PC runs its host agent.
Testers need no VPN, router setup, server files, source checkout, or Sentinel.

## Host controls

Open **Aetheria Server** on the desktop. **Start** starts the world and private
ingress helpers, refreshes the HTTPS tunnel origin, and checks the public release
endpoint. **Save / Stop** closes public ingress and lets the world save before
stopping. The database stays running. Closing the panel leaves hosting running.
Keep the PC awake and online while people play.

Once beta mode is enabled, **Build** builds and audits a new tester executable,
builds the standalone host, uploads a capped incremental update, waits for that
exact version to finish processing, makes a private recovery backup, and activates
the matching server/client version. Builds may take several minutes. A failed
upload is never reported as an activated release. Testers click **Check / update**
in their launcher before Play; outdated, incomplete, offline, or modified builds
cannot pass its launch check. Already connected sessions end during activation.

Beta exports remain candidates until the exact upload finishes processing and
the world saves, stops, and receives a private recovery backup. Build-only runs,
failed uploads and failed stop/backup operations keep the active server selection.
Each candidate records its release ID and executable/package hashes. Start checks
that the selected candidate, world release, and approved client hash match the
sealed release pair. An interrupted activation leaves `beta-runtime/activation.pending`
and blocks Start; recover the three active files (`server-build.json`, `world.json`,
`beta.json`) together from the pre-activation recovery bundle, verify the original
candidate artifacts remain present, then remove the marker after inspection.

An operator can retry an already validated pair without exporting it again:

```powershell
$betaPython = "$env:LOCALAPPDATA/Aetheria/online/venv/Scripts/python.exe"
& $betaPython tools/beta_release.py --release beta-EXISTING --reuse-server-build 'C:/private/matching-server-manifest.json' --publish --activate
```

This rechecks the existing client release metadata, hash, size, resource audit and
boot evidence, plus the matching server candidate and pinned runtime. Each
reuse request also boots the exact packaged client again and requires a zero
exit status without script/runtime errors before sealing or publishing it.
Supplying a legacy schema-1 server manifest explicitly attests that it was built and validated
with this client; timestamps cannot establish that historical pairing. The first
reuse seals that pairing and later retries reject a different server or client.
Keep the saved manifest and private `beta-builds/<release>-validation` evidence.
The flags still require verified publication before activation. The normal
development-only Build behavior remains unchanged.

Private installation settings and credentials live under
`%LOCALAPPDATA%/Aetheria/online`, protected for this Windows user. Do not share
that folder, its recovery backups, publisher credential, database, or server key.
The launcher application and its consumer state are separate from server files.

## Invite one tester

1. In itch.io's project **Distribute → Download keys**, create one key. Give it a
   private tester label and select **Require key to be claimed**. Send the personal
   link only to that tester. They claim it with their own itch.io account.
2. Create an expiring Aetheria registration code using the local administrative
   command below. Send that code privately with their link. It is single-use.
3. They download and extract the complete launcher package, run
   `AetheriaLauncher.exe`, sign into their invited itch.io account, update, and
   Play. In the game's original login screen they create an account using the
   registration code, or use an existing account you explicitly granted access.

Operator commands, run from the active repository:

```powershell
$betaPython = "$env:LOCALAPPDATA/Aetheria/online/venv/Scripts/python.exe"
& $betaPython -m backend.beta_admin invite --hours 72
& $betaPython -m backend.beta_admin grant PlayerName
& $betaPython -m backend.beta_admin revoke PlayerName
& $betaPython -m backend.beta_admin status
```

Revoking game access blocks further admissions and reuse of previously issued
admission tickets. An existing live lease can still save and release safely.
Revoke their itch.io download key too to remove future download access.
No testers are automatically granted Sentinel access.

## Boundaries and portability

The distributed Godot executable embeds compiled client scripts and game assets.
The export audit rejects raw GDScript, host implementation, developer tools,
Sentinel, and private key formats. A computer running a game necessarily holds
its runtime and assets; packaging cannot make those impossible to inspect.
Inventory, bait, catches, XP, admission decisions, and durable saves are server
authority. Running an extracted client outside the launcher does not grant an
account invitation or bypass the server's version check.

Cloudflare handles only the narrow player account API; `/internal/*`, database
ports, source directories and file-manipulation tools are never routed. The
Worker authenticates to the loopback gateway and supplies the real client IP.
The account service and world listen on loopback; the world uses pinned DTLS
through Playit. No router port forwarding is needed.

These free services suit small closed tests, with availability and routing limits.
Cloudflare's [free Worker quota](https://developers.cloudflare.com/workers/platform/limits/)
is 100,000 requests/day; gameplay snapshots do not traverse the Worker.
[Quick Tunnels](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/)
are intended for temporary development/testing and have no production uptime
guarantee. Their changing origin is refreshed behind the stable Worker address.
Free Playit routing may add latency. A good Ethernet connection alone does not
establish low latency to every tester. Outside-network play still needs testing.

For a future server provider, deploy the same private backend/world services,
keep PostgreSQL backups and account data, replace the public endpoint profile
and TLS certificate as appropriate, and publish a matching client release.
The game rules do not depend on this PC's public address.

## Validation tools

`tools/test_networking.py` covers movement, persistence and original online
minigames. `tools/test_beta_online.py` exercises disposable PostgreSQL accounts,
real DTLS gameplay and save/reconnect with source and exported clients.
`tools/test_launcher_live.ps1` is an opt-in operator probe for real consumer
OAuth/install/launch; it is excluded from distributed packages. Unit checks cover
ownership isolation, failed updates, integrity/version checks and proxy boundaries.
Generated reports and credentials stay outside Git.
