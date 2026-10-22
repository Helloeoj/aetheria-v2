# Player chat and social lists

The active game includes a permanent, mostly transparent chat panel at the bottom-left. It survives area changes and does not fade or close. Local reaches players within 20 tiles in the same area/world/instance; Global reaches everyone connected to the same social service. Private messages are visible only to sender and recipient. All is a transcript filter; the send-channel selector determines where a message goes.

Press Enter to type and submit, and Escape to return to gameplay while keeping a draft. Gameplay continues while typing. Use **Friends** for the saved friends/block lists; Message selects a private recipient, or type a name beside the Private composer. Friendship is one-way. Blocks filter the block owner's public transcript, hide retained messages, remove that target from their friends list and prevent private contact in both directions. Unblocking does not restore friendship. Lists persist on the server; up to 500 messages remain in memory until logout/application exit. Offline private mail is not queued. Restore draft recovers a rejected send without automatically replaying it.

Existing activity controls underneath the transparent HUD retain their clicks when chat is not being edited. Chat's own controls and scrollback otherwise own their mouse/wheel input. Food controls are placed above the panel. Chat failures leave gameplay running.

## Local use

On Windows, launching the source game starts a hidden local server if the default endpoint is unavailable, then connects automatically. The first successful connection creates a random development chat name and saves its credential under Godot `user://social_profiles.cfg`, scoped to that endpoint. **Connect** opens server/name settings and an opacity slider. Changing the name preserves that profile's stable ID and lists; names are unique without case sensitivity. Opening the same saved profile in two games is rejected rather than creating a second active identity.

The launcher uses the installed bundled Python, or `py` when the bundle is unavailable, and the pinned `websockets` dependency. Manual commands from the repository root:

```powershell
./tools/social.ps1 start       # hidden local server, port 8765
./tools/social.ps1 run         # foreground server for operators
```

The default database is `%LOCALAPPDATA%/Aetheria/social.sqlite3`; background server logs are in the same directory. Neither database nor credentials belong in Git. The database contains only SHA-256 digests of random 256-bit bearer credentials, not the credentials themselves or message archives. Protect the local profile file as a credential. Losing that file loses access to this development identity; no account recovery is claimed.

## Other computers and future accounts

The default server listens on `127.0.0.1` only. Other computers need a shared running endpoint configured through Connect. Run `tools/social_server.py` with `--host`, `--port`, `--database`, `--cert` and `--key` using Python with `tools/social-requirements.txt` installed. Remote binds require a certificate/key, and clients require certificate-validating `wss://`; plaintext is accepted only for loopback. Native clients use no browser Origin; browser clients are not enabled. Public hosting, DNS, certificates and router/firewall changes are not provisioned by this feature.

These are **development chat profiles**, separate from the planned shared username/password gameplay accounts. This standalone SQLite service makes communication usable now; its transport-independent social domain and stable IDs provide the integration boundary for that backend. It does not save character progression or implement that separate account project. Current local proximity uses positions reported by each client; it is not authoritative multiplayer movement or an anti-cheat guarantee. Production account/location adapters and a production database migration remain part of the shared-server integration. The configurable 50-connection default is not a measured capacity claim.

## Verification

Use the installed Python and Godot 4.5.1 executables:

```powershell
& $python tools/test_social.py
& $python tools/test_social_network.py --godot $env:GODOT --output <outside-repo-directory>
& $env:GODOT --headless --path godot_client --script res://scripts/dev_tools/social_ui_smoke.gd
& $python tools/test_cooking.py --godot $env:GODOT --output <outside-repo-directory>
& $python tools/test_inventory_items.py --godot $env:GODOT --output <outside-repo-directory>
```

The network test starts the actual service and three separate Godot game clients with disposable credentials; it checks Global, the Local boundary, Private isolation, friend/block updates and reverse-direction blocking. Each peer has separate diagnostics/native logs to avoid concurrent retention conflicts. All generated evidence stays outside the repository. For a rendered UI capture, run the social UI smoke without `--headless` and append `-- --social-no-auto --capture=<absolute-png-path>`.
