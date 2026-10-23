# Aetheria Windows launcher

Portable x64 WinForms bootstrap built with the installed .NET Framework compiler.
Ship `AetheriaLauncher.exe`, `launcher.json`, pinned `butler.exe` v15.32.0,
its official sibling `7z.dll` and `c7zip.dll`, and
the release's vendor notices together. Players extract the folder and open the
launcher; they never select a source directory or use creator credentials.

Build and run the fake-service, UI-construction, and real-daemon checks:

```powershell
./tools/build_launcher.ps1 -Test -RealDaemonTest
```

Supply a completed JSON config for a distributable bootstrap:

```powershell
./tools/build_launcher.ps1 -ConfigPath C:/private/launcher.json -OutputDirectory C:/private/bootstrap
```

`launcher.example.json` has the registered public game/client identifiers.
Its upload ID and account HTTPS origin deliberately remain incomplete until
the corresponding production resources are ready. A build without `-ConfigPath`
is explicitly a development bootstrap and cannot enable Play. There is no runtime
dependency download. The build checks the bundled butler version; production
packaging must retain the pinned vendor binary and notices.
The build requires both native DLLs from the same official runtime directory,
copies them beside butler, and includes their upstream notices and license texts.
The pinned throttler uses 128 bytes/sec per Kbps unit: the configured 3906 Kbps
rounds down to 499,968 bytes/sec, within the 500,000-byte/sec limit.

Player sign-in uses consumer OAuth PKCE at `https://itch.io/user/oauth`, scope
`profile:me profile:owned game:view:uploads`, with redirect
`aetheria-launcher://oauth-callback`. The launcher registers
this scheme under HKCU when sign-in is selected. A second launcher process sends
only a bounded callback URI through a named pipe restricted to the same Windows
user. State, verifier, code and daemon secret stay in memory. Saved consumer
credentials belong to butler's per-user database; the launcher remembers only
the selected numeric profile ID. There is no API-key/password input, creator
token, client secret, RPC traffic log or token log.

State lives under `%LOCALAPPDATA%/Aetheria/launcher`: `butler.db`,
`profile-id.txt`, fixed `games/` install location and an `update-in-progress`
marker. Only this game's configured upload is fetched, installed or updated.
The launcher authenticates butler before other RPC calls, supports concurrent
response correlation and progress notifications, rejects every interactive
server prompt explicitly, and sets its throttle to 4,000 kilobits/s (500,000
bytes/s). Update requests set `ignoreInstallers: true` and select the fresh
upload build explicitly, allowing butler's wharf incremental updates.

Every startup and every Play attempt requests `<account_url>/api/release` over
validated HTTPS, with a ten-second deadline, a 64-KiB response cap, no redirects,
and no certificate bypass. The response must include:

```json
{"ok":true,"enabled":true,"release_id":"beta-…","client_sha256":"64 hex digits","client_bytes":123}
```

Play also requires fresh itch.io authentication and selected-profile ownership, root
`release.json` with `{ "schema":1, "release_id":"beta-…", "executable":"Aetheria.exe" }`,
and a streaming SHA-256 and byte-size match for the fixed `Aetheria.exe`.
The invited consumer must claim their beta download key on itch.io. Before
startup readiness, OAuth sign-in completion, update and Play, the launcher
refreshes that profile's owned keys with `Fetch.ProfileOwnedKeys(fresh:true)`
and requires `Fetch.GameOwnership(profileId,gameId)` to report a non-stale
`download_key` source and positive key ID. Other saved accounts' keys, bundle
markers and creator edit rights do not supply a consumer beta invitation.
`Fetch.GameUploads` and `Install.Queue` can resolve credentials across saved
profiles, so their success is used only after this independent strict check.
Installation reuses game metadata from that selected profile's freshly refreshed
owned key, matching its owner ID, game ID, nested game ID and the independently
verified download-key ID. It reads bounded additional owned-key pages when needed
and rejects stale or missing metadata. It does not call `Fetch.Game(fresh:true)`,
which requires the broader `game:view` scope beyond the approved consumer grant.
During a pending install the same selected-profile ownership/upload gate runs
every 20 seconds. Failure cancels the operation and retains the repair marker.
These requests also keep the pinned runtime's API connection active, avoiding
its idle-close/shared-throttle starvation during long storage transfers.
Build the game with an embedded PCK so that this EXE hash covers its content.
Launch actions from manifests and butler's general `Launch` method are never
executed. Install paths must remain inside the chosen per-user location and
cannot traverse reparse points. A partial update, failed auth, offline/disabled
release, or mismatched file/version keeps Play disabled. A persistent update
marker clears only after an installed release passes a fresh HTTPS recheck.

Automated checks use synthetic butler/HTTPS boundaries and an isolated real
butler DB; they do not claim a completed consumer OAuth exchange or a private
itch.io download. These two live checks require the final upload/config and an
invited consumer account. The UI smoke check constructs and opens the real form
invisibly and verifies its first-screen controls and disabled Play state.

Official integration reference:
https://itch.io/docs/butler/launcher-integration.html
