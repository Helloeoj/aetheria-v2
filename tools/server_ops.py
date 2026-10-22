"""Dedicated Windows exports and consistent private PostgreSQL recovery bundles."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import uuid
import zipfile

REPO = Path(__file__).resolve().parents[1]
DATA = Path(os.environ['LOCALAPPDATA']) / 'Aetheria/online'
HIDDEN = getattr(subprocess, 'CREATE_NO_WINDOW', 0)


def pg_environment(config):
    return dict(os.environ, PGPASSWORD=config['db_password'])


def dump_database(config, target, data):
    binary = Path(os.environ.get('AETHERIA_POSTGRES_BIN', data / 'postgresql-runtime/pgsql/bin'))
    result = subprocess.run([str(binary / 'pg_dump.exe'), '-h', '127.0.0.1',
                             '-p', str(config['db_port']), '-U', config['db_user'],
                             '-d', config['db_name'], '-Fc', '-f', str(target)],
                            env=pg_environment(config), capture_output=True, creationflags=HIDDEN)
    if result.returncode:
        raise RuntimeError('Database backup failed; no recovery bundle published.')
    verified = subprocess.run([str(binary / 'pg_restore.exe'), '--list', str(target)],
                              capture_output=True, creationflags=HIDDEN)
    if verified.returncode:
        raise RuntimeError('Database archive verification failed.')


def backup(data=DATA):
    config = json.loads((data / 'config.json').read_text(encoding='utf-8-sig'))
    if config['database'] != 'postgresql':
        raise RuntimeError('Recovery bundles require the installed PostgreSQL service.')
    output = data / 'backups'
    output.mkdir(exist_ok=True)
    name = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8]
    # Temporary output is private and never presented as a completed backup.
    with tempfile.TemporaryDirectory(dir=output) as temporary:
        dump = Path(temporary) / 'database.dump'
        dump_database(config, dump, data)
        with dump.open('rb') as handle:
            checksum = hashlib.file_digest(handle, 'sha256').hexdigest()
        bundle = Path(temporary) / 'recovery.zip'
        with zipfile.ZipFile(bundle, 'w', zipfile.ZIP_STORED) as archive:
            archive.write(dump, 'database.dump')
            for filename in ['config.json', 'server.key', 'world.json']:
                path = data / filename
                if filename != 'world.json' or path.exists():
                    archive.write(path, filename)
            archive.writestr('manifest.json', json.dumps({'schema': 1,
                'created_utc': name, 'database_sha256': checksum}))
        target = output / f'aetheria-{name}.zip'
        bundle.replace(target)
    return target


def build(godot, data=DATA):
    builds = data / 'server-builds'
    builds.mkdir(parents=True, exist_ok=True)
    destination = builds / (datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8])
    destination.mkdir()
    exe = destination / 'AetheriaServer.exe'
    log = destination / 'export.log'
    with log.open('w', encoding='utf-8') as transcript:
        result = subprocess.run([str(godot), '--headless', '--path', str(REPO / 'godot_client'),
            '--export-release', 'Windows Dedicated Server', str(exe)],
            stdout=transcript, stderr=subprocess.STDOUT, creationflags=HIDDEN, timeout=600)
    text = log.read_text(encoding='utf-8')
    if result.returncode or 'SCRIPT ERROR:' in text or 'ERROR:' in text or not exe.exists() or not exe.with_suffix('.pck').exists():
        raise RuntimeError(f'Export failed. Inspect {log}. Install Godot 4.5.1 Windows export templates if missing.')
    pending = data / ('server-build-' + uuid.uuid4().hex + '.pending')
    pending.write_text(json.dumps({'exe': str(exe), 'repo': str(REPO), 'schema': 1}), encoding='utf-8')
    pending.replace(data / 'server-build.json')
    return exe


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['build', 'backup'])
    parser.add_argument('--godot')
    args = parser.parse_args()
    if args.action == 'build':
        if not args.godot:
            parser.error('--godot is required for builds')
        print(build(args.godot))
    else:
        print('Recovery bundle (private):', backup())


if __name__ == '__main__':
    main()
