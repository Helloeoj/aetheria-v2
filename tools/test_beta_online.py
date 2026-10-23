"""Isolated beta HTTP -> DTLS world -> PostgreSQL save/reconnect validation.

Run with the installed private account-service Python. No live services are
started/reloaded and no live account rows are read or changed. All credentials,
fixture state and logs stay in the external evidence directory. An optional
exported tester executable runs an external copy of the source fixture against
its own embedded PCK; its installed files are never modified.
"""
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid

REPO = Path(__file__).resolve().parents[1]
if str(REPO) not in sys.path:
    sys.path.insert(0, str(REPO))
RELEASE = 'integration-beta-1'
WORLD = 'integration-beta-world'
HIDDEN = getattr(subprocess, 'CREATE_NO_WINDOW', 0)


def available_port(kind=socket.SOCK_STREAM):
    with socket.socket(socket.AF_INET, kind) as probe:
        probe.bind(('127.0.0.1', 0))
        return probe.getsockname()[1]


def write_json(path, value):
    path.write_text(json.dumps(value), encoding='utf-8')


def wait_for(predicate, process, timeout, label):
    deadline = time.monotonic() + timeout
    while not predicate():
        if process.poll() is not None or time.monotonic() >= deadline:
            raise AssertionError(label + ' did not become ready; inspect external evidence.')
        time.sleep(.1)


def run(args):
    output = (args.output or Path(tempfile.mkdtemp(prefix='aetheria-beta-online-'))).resolve()
    if output == REPO or REPO in output.parents:
        raise ValueError('Evidence must be outside the repository.')
    output.mkdir(parents=True, exist_ok=True)
    local_data = output / 'local' / 'Aetheria' / 'online'
    local_data.mkdir(parents=True)
    # Read connection details only in memory; never copy the live config/key.
    live_data = Path(os.environ['LOCALAPPDATA']) / 'Aetheria' / 'online'
    config = json.loads((live_data / 'config.json').read_text(encoding='utf-8-sig'))
    if config['database'] != 'postgresql':
        raise ValueError('This validation requires the existing PostgreSQL service.')
    database = 'aetheria_beta_validation_' + uuid.uuid4().hex
    account_port, world_port = available_port(), available_port(socket.SOCK_DGRAM)
    base = 'http://127.0.0.1:' + str(account_port)
    server_key = secrets.token_urlsafe(48)
    (local_data / 'server.key').write_text(server_key, encoding='utf-8')
    write_json(local_data / 'beta.json', {'schema': 1, 'enabled': True, 'release_id': RELEASE})
    environment = dict(os.environ, AETHERIA_ACCOUNT_DATA=str(local_data),
        LOCALAPPDATA=str(output / 'local'), AETHERIA_SERVER_KEY=server_key,
        AETHERIA_DJANGO_SECRET=secrets.token_urlsafe(50), DJANGO_SETTINGS_MODULE='backend.settings',
        AETHERIA_DB_NAME=database, AETHERIA_DB_USER=config['db_user'],
        AETHERIA_DB_PASSWORD=config['db_password'], AETHERIA_DB_PORT=str(config['db_port']),
        AETHERIA_DB_HOST='127.0.0.1', AETHERIA_TEST_PORT=str(account_port),
        AETHERIA_DIAGNOSTICS_DIR=str(output / 'adc'))
    # Defeat any inherited live service proxy/SQLite settings in this process.
    for name in ('AETHERIA_TRUSTED_PROXY', 'AETHERIA_PUBLIC_ORIGIN', 'AETHERIA_SQLITE_PATH'):
        environment.pop(name, None)
    os.environ.update(environment)
    for name in ('AETHERIA_TRUSTED_PROXY', 'AETHERIA_PUBLIC_ORIGIN', 'AETHERIA_SQLITE_PATH'):
        os.environ.pop(name, None)

    def request(route, payload=None, token=None):
        headers = {'Content-Type': 'application/json'}
        if token:
            headers['Authorization'] = 'Bearer ' + token
        req = urllib.request.Request(base + route,
            data=None if payload is None else json.dumps(payload).encode(), headers=headers)
        try:
            response = urllib.request.urlopen(req, timeout=10)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            return json.load(response)

    def healthy():
        try:
            return request('/health').get('ok', False)
        except (OSError, urllib.error.URLError):
            return False

    def source_command(scene, name, input_path=None):
        command = [args.godot, '--headless', '--path', str(REPO / 'godot_client'), scene,
            '--log-file', str(output / (name + '-godot.log')), '--', '--social-no-auto']
        if input_path is not None:
            command.append('--test-input=' + str(input_path))
        return command

    def check_transcript(result, name, session=False):
        transcript = result.stdout + result.stderr
        (output / (name + '-console.log')).write_text(transcript, encoding='utf-8')
        if result.returncode or 'SCRIPT ERROR:' in transcript or 'ERROR:' in transcript:
            raise AssertionError(name + ' reported a runtime error; inspect external evidence.')
        if session and not re.search(r'\[Online session\] \d+ checks, 0 failures', transcript):
            raise AssertionError(name + ' did not pass every gameplay check.')
        return transcript

    import psycopg
    from psycopg import sql
    admin = psycopg.connect(host='127.0.0.1', port=config['db_port'], user=config['db_user'],
        password=config['db_password'], dbname='postgres', autocommit=True)
    account, world = None, None
    handles = []
    created = False
    summary = {'passed': False, 'gameplay_passed': False, 'source_sessions': [], 'exported_sessions': [],
        'evidence': str(output), 'database_dropped': False, 'world_gracefully_stopped': False}
    try:
        admin.execute(sql.SQL('CREATE DATABASE {}').format(sql.Identifier(database)))
        created = True
        import django
        django.setup()
        from django.core.management import call_command
        call_command('migrate', interactive=False, verbosity=0)
        from backend.beta import create_invite
        invite = create_invite(hours=1)
        account_log = (output / 'account-console.log').open('w', encoding='utf-8')
        handles.append(account_log)
        account = subprocess.Popen([sys.executable, '-m', 'tools.test_beta_online', '--serve'],
            cwd=REPO, env=environment, stdout=account_log, stderr=subprocess.STDOUT, creationflags=HIDDEN)
        wait_for(healthy, account, 20, 'Private account service')
        username, password = 'beta_' + secrets.token_hex(5), secrets.token_urlsafe(24)
        registration = {'username': username, 'password': password, 'password_confirmation': password}
        assert request('/api/register', registration).get('code') == 'invalid_invite', 'Missing invite accepted.'
        registered = request('/api/register', dict(registration, invite_code=invite))
        assert registered.get('ok'), 'Invited registration rejected.'
        assert request('/api/register', dict(registration, username='other_' + secrets.token_hex(5),
            invite_code=invite)).get('code') == 'invalid_invite', 'Reused invite accepted.'
        login = request('/api/login', {'username': username, 'password': password})
        assert login.get('ok'), 'Invited account login rejected.'
        assert request('/api/admit', {'world_id': WORLD, 'release_id': 'old-release'},
            login['token']).get('code') == 'release_mismatch', 'Old release admitted.'
        summary['beta_policy'] = 'absent/reused invite and old release rejected; invited account accepted'

        cert_input = output / 'certificate-input.json'
        key, certificate = output / 'world.key', output / 'world.crt'
        write_json(cert_input, {'mode': 'certificate', 'key': str(key), 'certificate': str(certificate)})
        result = subprocess.run(source_command('res://scenes/dev_tools/encrypted_transport_smoke.tscn',
            'certificate', cert_input), env=environment, capture_output=True, text=True, timeout=30)
        check_transcript(result, 'certificate')
        write_json(local_data / 'world.json', {'port': world_port, 'world_id': WORLD,
            'release_id': RELEASE, 'account_url': base, 'tls_key': str(key),
            'tls_certificate': str(certificate), 'tls_name': 'aetheria-beta'})
        world_log = (output / 'world-console.log').open('w', encoding='utf-8')
        handles.append(world_log)
        world_command = source_command('res://scenes/network/WorldServer.tscn', 'world')
        world_command.append('--world-server')
        if args.server_exe:
            world_command = [str(args.server_exe), '--headless']
            if args.server_pack:
                world_command += ['--main-pack', str(args.server_pack)]
            world_command += ['--log-file', str(output / 'world-godot.log'), '--', '--social-no-auto']
        world = subprocess.Popen(world_command, env=environment, stdout=world_log,
            stderr=subprocess.STDOUT, cwd=REPO, creationflags=HIDDEN)
        wait_for(lambda: (local_data / 'world-ready.json').exists(), world, 60, 'Private DTLS world')

        def client(name, executable, previous=None, external_scene=None):
            session_dir = output / name
            session_dir.mkdir()
            login = request('/api/login', {'username': username, 'password': password})
            assert login.get('ok'), name + ': login rejected.'
            admission = request('/api/admit', {'world_id': WORLD, 'release_id': RELEASE}, login['token'])
            assert admission.get('ok'), name + ': admission rejected.'
            fixture = {'username': username, 'character_id': registered['character_id'],
                'token': login['token'], 'ticket': admission['ticket'], 'world_id': WORLD,
                'port': world_port, 'release_id': RELEASE, 'account_url': base,
                'output': str(session_dir / 'result.json'), 'beta_profile': {
                    'world_host': '127.0.0.1', 'world_port': world_port,
                    'tls_name': 'aetheria-beta', 'tls_certificate': str(certificate)}}
            if previous is not None:
                fixture['expected_state'] = previous['state']
            input_path = session_dir / 'input.json'
            write_json(input_path, fixture)
            if external_scene is None:
                command = source_command('res://scenes/dev_tools/online_session_smoke.tscn', name, input_path)
            else:
                command = [str(executable), '--headless', str(external_scene), '--log-file',
                    str(output / (name + '-godot.log')), '--', '--social-no-auto',
                    '--test-input=' + str(input_path)]
            result = subprocess.run(command, env=environment, capture_output=True, text=True,
                timeout=100, cwd=output, creationflags=HIDDEN)
            transcript = check_transcript(result, name, session=True)
            data = json.loads((session_dir / 'result.json').read_text(encoding='utf-8'))
            assert data['character_id'] == registered['character_id'] and data['failures'] == 0
            assert request('/api/character', token=login['token']).get('code') == 'unauthorized', 'Logout session still valid.'
            from backend.accounts.models import Character
            saved = Character.objects.get(pk=registered['character_id'])
            assert saved.revision > data['revision'], 'Logout did not persist a new revision.'
            assert not saved.lease_hash, 'Logout did not release character lease.'
            return data, {'checks': int(re.search(r'\[Online session\] (\d+) checks', transcript)[1]),
                'failures': 0, 'prediction_ms': float(re.search(r'first rendered response=([\d.]+)ms', transcript)[1]),
                'logout_revision_advanced': True, 'lease_released': True}

        previous = None
        for index in (1, 2):
            previous, result = client('source-session-' + str(index), args.godot, previous)
            summary['source_sessions'].append(result)
        if args.client_exe:
            # Runtime resources continue resolving inside the executable's PCK.
            script = output / 'online_session_smoke.gd'
            shutil.copyfile(REPO / 'godot_client/scripts/dev_tools/online_session_smoke.gd', script)
            scene = output / 'online_session_smoke.tscn'
            scene.write_text('[gd_scene load_steps=2 format=3]\n'
                '[ext_resource type="Script" path="' + script.as_posix() + '" id="1"]\n'
                '[node name="ExportedOnlineSessionSmoke" type="Node"]\nscript = ExtResource("1")\n', encoding='utf-8')
            for index in (1, 2):
                previous, result = client('exported-session-' + str(index), args.client_exe, previous, scene)
                summary['exported_sessions'].append(result)
        summary['gameplay_passed'] = True
        summary['passed'] = True
    finally:
        # Keep the account worker/database alive until all pending world saves stop.
        if world is not None and world.poll() is None:
            (local_data / 'world-stop.request').write_text('stop', encoding='utf-8')
            try:
                world.wait(timeout=60)
            except subprocess.TimeoutExpired:
                summary['cleanup_blocker'] = 'World still saving; worker/database preserved for recovery.'
                write_json(output / 'summary.json', summary)
                raise RuntimeError(summary['cleanup_blocker']) from None
        summary['world_gracefully_stopped'] = world is None or world.returncode == 0
        if account is not None and account.poll() is None:
            account.terminate()
            account.wait(timeout=10)
        for handle in handles:
            handle.close()
        try:
            from django.db import connections
            connections.close_all()
        finally:
            if created:
                admin.execute(sql.SQL('DROP DATABASE {}').format(sql.Identifier(database)))
                summary['database_dropped'] = True
            admin.close()
        world_text = (output / 'world-console.log').read_text(encoding='utf-8') if world is not None else ''
        summary['world_runtime_error_count'] = len(re.findall(r'^ERROR:', world_text, re.MULTILINE))
        if 'SCRIPT ERROR:' in world_text or 'ERROR:' in world_text or not summary['world_gracefully_stopped']:
            summary['passed'] = False
            summary['world_error'] = 'Inspect external world log for runtime/stop failure.'
        write_json(output / 'summary.json', summary)
    assert summary['passed'], 'World validation failed; inspect external evidence.'
    print('[Beta online] Invites/release policy, DTLS gameplay, prediction, logout save and reconnect passed.')
    print('Source sessions:', len(summary['source_sessions']), 'Exported sessions:', len(summary['exported_sessions']))
    print('World stopped gracefully; disposable database dropped.')
    print('Evidence:', output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot')
    parser.add_argument('--client-exe', type=Path)
    parser.add_argument('--server-exe', type=Path)
    parser.add_argument('--server-pack', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--serve', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.serve:
        from backend.service import serve_app
        serve_app({'database': 'postgresql', 'host': '127.0.0.1', 'port': int(os.environ['AETHERIA_TEST_PORT'])})
    elif not args.godot:
        parser.error('--godot is required')
    elif args.server_pack and not args.server_exe:
        parser.error('--server-pack requires --server-exe')
    else:
        run(args)


if __name__ == '__main__':
    main()
