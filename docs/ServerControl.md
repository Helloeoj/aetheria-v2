# Local dedicated server control

Open **Aetheria Server** on the desktop, or run `tools/server.ps1` from
PowerShell. The control window runs independently of the client and editor.
Closing it leaves the server running. Commands are also available directly:

```powershell
./tools/server.ps1 start
./tools/server.ps1 status
./tools/server.ps1 stop
./tools/server.ps1 backup
./tools/server.ps1 logs
./tools/server.ps1 build
```

Start ensures the existing account service is available, then starts the latest
dedicated build. Repeated starts reuse the current world. Save / Stop requests
the world's existing final-save shutdown; it does not force-kill the world when
saves cannot complete. The account service and PostgreSQL stay available.
The original client Login can still start this same world through `online.ps1`.

Build uses the installed Godot 4.5.1 editor and matching Windows export templates.
The export preset strips visual resources, retaining references, dimensions and
the existing map geometry/rules. The resulting executable and PCK need no editor
or client to run. Built servers start at WorldServer automatically. Account API
and PostgreSQL remain separate required processes on this PC; this is not a
self-contained database installer or a public Internet deployment.

Builds are versioned under `%LOCALAPPDATA%/Aetheria/online/server-builds`.
The completed build pointer is `server-build.json`. Building does not interrupt
a running world: Save / Stop, then Start to activate the new build. Until a build
is installed, the original development launcher can still use the installed
Godot console executable. Configuration, keys, logs and builds stay outside Git.
The graphical actions run asynchronously; the window waits for an active action
to finish before closing, and displays failure output instead of reporting success.

Backup creates a uniquely named recovery ZIP under the private `backups` folder.
It contains a PostgreSQL custom-format dump, its SHA-256 digest, account config,
server key and optional world config. The dump is checked with `pg_restore --list`
before publishing the ZIP; failed dumps never appear as completed bundles.
These files contain account data and secrets. Keep them private; copy recovery
bundles to private off-PC storage for protection against disk failure.

Backups are consistent database snapshots of committed progress. They do not
capture unsaved in-memory movement or transient ground drops. For a final stopped
checkpoint, use Save / Stop before Backup. Backup has no destructive restore
button. Recovery requires stopping services and restoring the dump into a chosen
PostgreSQL database, with its matching private config/key. An integration test
restores to a uniquely named disposable database and removes only that database.

Validation commands:

```powershell
& "$env:LOCALAPPDATA/Aetheria/online/venv/Scripts/python.exe" tools/test_server_ops.py
$env:AETHERIA_BACKUP_INTEGRATION = '1'
& "$env:LOCALAPPDATA/Aetheria/online/venv/Scripts/python.exe" tools/test_server_ops.py
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/server_panel.ps1 -SmokeTest
& "$env:LOCALAPPDATA/Aetheria/online/venv/Scripts/python.exe" tools/test_server_export.py --server-exe <AetheriaServer.exe> --godot <Godot-4.5.1-console.exe>
```

Large prerequisite downloads for this workflow must be bandwidth capped. The
matching official Godot templates were resumed using curl `--continue-at -`
and `--limit-rate 500000` (500 kB/s, approximately 4 Mbit/s). Do not restart an
unrestricted template download. No DNS, adapter, router or firewall changes are
part of installation. Remote access, supervision and capacity testing remain
separate sections of server development.

The export test uses an isolated runtime directory and a temporary local UDP
port. Two fresh-account sessions verify actual exported map loading, movement,
PostgreSQL saves and reconnect, followed by graceful shutdown. It never restarts
the installed world and keeps credentials/logs outside Git. The regular networking
and movement suites remain applicable to the shared gameplay code.

October 22, 2026 validation: the dedicated Windows release passed two live
sessions (24 checks), with saved identity/progression restored and clean shutdown.
The final stripped PCK is 16,131,020 bytes. Backup failure handling and real
disposable-database restore both passed, as did graphical status, repeated start,
editor import, client startup, the 11-test networking suite and three movement
tests. The normal installed world was gracefully switched to the dedicated EXE;
process identity verification confirmed it no longer uses the editor runtime.
