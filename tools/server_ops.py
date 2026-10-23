"""Dedicated Windows exports and consistent private PostgreSQL recovery bundles."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import shutil
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
            for filename in ['config.json', 'server.key', 'world.json', 'beta.json', 'ingress.json',
                             'beta-runtime/world-private.key', 'beta-runtime/world-public.crt',
                             'beta-runtime/playit-secret-assignable', 'beta-runtime/hosting.json',
                             'server-runtime.json', 'server-build.json']:
                path = data / filename
                if filename in ['config.json', 'server.key'] or path.exists():
                    archive.write(path, filename)
            archive.writestr('manifest.json', json.dumps({'schema': 1,
                'created_utc': name, 'database_sha256': checksum}))
        target = output / f'aetheria-{name}.zip'
        bundle.replace(target)
    return target


def sha256(path):
    with path.open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()


def candidate_manifest(exe, release_id):
    """Seal an already exported pair without changing the active startup pointer."""
    if not re.fullmatch(r'[A-Za-z0-9_.-]{1,80}', release_id):
        raise ValueError('Invalid release identifier.')
    exe = Path(exe).resolve()
    manifest = exe.parent / 'server-candidate.json'
    candidate = {'schema': 2, 'repo': str(REPO), 'exe': str(exe), 'release_id': release_id,
                 'exe_sha256': sha256(exe), 'pck_sha256': sha256(exe.with_suffix('.pck'))}
    if manifest.exists():
        if json.loads(manifest.read_text(encoding='utf-8-sig')) != candidate:
            raise RuntimeError('The immutable server candidate does not match this release.')
    else:
        with manifest.open('x', encoding='utf-8') as handle:
            json.dump(candidate, handle, indent=2)
    return manifest


def verify_candidate(manifest, release_id):
    manifest = Path(manifest).resolve()
    candidate = json.loads(manifest.read_text(encoding='utf-8-sig'))
    if (candidate.get('schema') != 2 or candidate.get('repo') != str(REPO)
            or candidate.get('release_id') != release_id):
        raise RuntimeError('Server candidate release identity does not match.')
    exe = Path(candidate['exe']).resolve()
    if (manifest != exe.parent / 'server-candidate.json'
            or sha256(exe) != candidate.get('exe_sha256')
            or sha256(exe.with_suffix('.pck')) != candidate.get('pck_sha256')):
        raise RuntimeError('Server candidate integrity verification failed.')
    return candidate


def verify_selection(data):
    """Beta startup must select the sealed server matching both active policies."""
    def read(name):
        path = data / name
        return json.loads(path.read_text(encoding='utf-8-sig')) if path.exists() else {}
    try:
        policy, world, selected = read('beta.json'), read('world.json'), read('server-build.json')
        if policy.get('enabled') is not True and not selected.get('release_id'):
            return
        release = policy.get('release_id')
        if (policy.get('enabled') is not True or not release or world.get('release_id') != release
                or selected.get('release_id') != release):
            raise RuntimeError('Beta release startup requires matching server, world and client policy.')
        candidate_path = Path(selected['exe']).parent / 'server-candidate.json'
        candidate = verify_candidate(candidate_path, release)
        if candidate != selected:
            raise RuntimeError('The selected server differs from the sealed beta release candidate.')
        pair = read('beta-builds/' + release + '-validation/release-candidate.json')
        client = pair.get('client', {})
        if (pair.get('schema') != 1 or pair.get('server_candidate') != str(candidate_path.resolve())
                or client.get('release_id') != release
                or client.get('client_sha256') != policy.get('client_sha256')
                or client.get('client_bytes') != policy.get('client_bytes')):
            raise RuntimeError('The active client policy differs from the sealed beta release pair.')
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        raise RuntimeError('Beta release startup verification failed; repair the active selection.') from error


def validate_startup(data=DATA):
    if (data / 'beta-runtime/activation.pending').exists():
        raise RuntimeError('An interrupted beta release activation requires recovery before startup.')
    verify_selection(data)


def build(godot, data=DATA, release_id=None):
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
    runtime_path = data / 'server-runtime.json'
    if runtime_path.exists():
        runtime = json.loads(runtime_path.read_text(encoding='utf-8-sig'))
        source = Path(runtime['exe'])
        with source.open('rb') as handle:
            checksum = hashlib.file_digest(handle, 'sha256').hexdigest()
        if runtime.get('schema') != 1 or runtime.get('version') != '4.7.2' or checksum != runtime.get('sha256'):
            raise RuntimeError('The pinned standalone server runtime failed verification.')
        # Keep the 4.5.1 client/project exports; the host uses a separately verified
        # official runtime containing the upstream DTLS cookie cleanup fix.
        shutil.copyfile(source, exe)
    if release_id is not None:
        return candidate_manifest(exe, release_id)
    pending = data / ('server-build-' + uuid.uuid4().hex + '.pending')
    pending.write_text(json.dumps({'exe': str(exe), 'repo': str(REPO), 'schema': 1}), encoding='utf-8')
    pending.replace(data / 'server-build.json')
    return exe


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['build', 'backup', 'verify-start'])
    parser.add_argument('--godot')
    args = parser.parse_args()
    if args.action == 'build':
        if not args.godot:
            parser.error('--godot is required for builds')
        print(build(args.godot))
    elif args.action == 'backup':
        print('Recovery bundle (private):', backup())
    else:
        validate_startup()


if __name__ == '__main__':
    main()
