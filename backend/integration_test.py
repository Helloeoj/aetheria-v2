"""Real HTTP restart/persistence verification in a disposable PostgreSQL database."""
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid

from backend.service import HIDDEN, ensure_postgres, load_config, serve_app


def main():
    config = load_config()
    if '--serve' in sys.argv:
        config['host'], config['port'] = '127.0.0.1', int(os.environ['AETHERIA_TEST_PORT'])
        serve_app(config)
        return
    ensure_postgres(config)
    if config['database'] != 'postgresql':
        raise SystemExit('Restart integration validation requires PostgreSQL.')
    import psycopg
    from psycopg import sql
    database = 'aetheria_validation_'+uuid.uuid4().hex
    with socket.socket() as available:
        available.bind(('127.0.0.1', 0))
        port = available.getsockname()[1]
    os.environ['AETHERIA_TEST_PORT'] = str(port)
    os.environ['AETHERIA_DB_NAME'] = database
    base = 'http://127.0.0.1:'+str(port)

    def request(path, body=None, token=None, internal=False):
        headers = {'Content-Type': 'application/json'}
        if token:
            headers['Authorization'] = 'Bearer '+token
        if internal:
            headers['X-Aetheria-Server-Key'] = os.environ['AETHERIA_SERVER_KEY']
        payload = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(base+path, data=payload, headers=headers)
        try:
            result = urllib.request.urlopen(req, timeout=10)
        except urllib.error.HTTPError as error:
            result = error
        with result:
            return json.load(result)

    def start():
        process = subprocess.Popen([sys.executable, '-m', 'backend.integration_test', '--serve'],
            creationflags=HIDDEN, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(100):
            if process.poll() is not None:
                raise AssertionError('Integration worker failed to start.')
            try:
                if request('/health')['ok']:
                    return process
            except (OSError, urllib.error.URLError):
                pass
            time.sleep(.1)
        process.terminate()
        raise AssertionError('Integration worker startup timed out.')

    admin = psycopg.connect(host='127.0.0.1', port=config['db_port'], user=config['db_user'],
        password=config['db_password'], dbname='postgres', autocommit=True)
    process = None
    try:
        admin.execute(sql.SQL('CREATE DATABASE {}').format(sql.Identifier(database)))
        import django
        django.setup()
        from django.core.management import call_command
        call_command('migrate', interactive=False, verbosity=0)
        process = start()
        password = secrets.token_urlsafe(24)
        created = request('/api/register', {'username': 'RestartPlayer', 'password': password,
            'password_confirmation': password})
        assert created['ok'], created
        logged_in = request('/api/login', {'username': 'restartplayer', 'password': password})
        assert logged_in['ok'], logged_in
        admission = request('/api/admit', {'world_id': 'validation'}, logged_in['token'])
        claim = request('/internal/claim', {'ticket': admission['ticket'], 'world_id': 'validation'}, internal=True)
        assert claim['ok'] and claim['state'] == {}, claim
        state = {'version': 1, 'level': 8, 'inventory': [{'id': 'wood', 'quantity': 42}], 'position': [12.5, 8.75]}
        body = {'lease_token': claim['lease_token'], 'character_id': claim['character_id'],
            'expected_revision': 0, 'operation_id': str(uuid.uuid4()), 'state': state}
        saved = request('/internal/release', body, internal=True)
        assert saved == {'ok': True, 'revision': 1}, saved
        process.terminate()
        process.wait(timeout=10)
        process = start()
        # Retry the exact operation after a lost reply and a full service restart.
        assert request('/internal/release', body, internal=True) == saved
        assert request('/api/character', token=logged_in['token'])['character_id'] == created['character_id']
        logged_in = request('/api/login', {'username': 'RestartPlayer', 'password': password})
        assert logged_in['account_id'] == created['account_id']
        admission = request('/api/admit', {'world_id': 'validation'}, logged_in['token'])
        claim = request('/internal/claim', {'ticket': admission['ticket'], 'world_id': 'validation'}, internal=True)
        assert claim['state'] == state and claim['revision'] == 1, claim
        assert request('/api/logout', {}, logged_in['token'])['ok']
        assert request('/api/admit', {'world_id': 'validation'}, logged_in['token'])['code'] == 'unauthorized'
        print('PASS: real HTTP registration/login, atomic character save/release, process restart, persisted identity/session/state/journal retry, logout.')
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            process.wait(timeout=10)
        from django.db import connections
        connections.close_all()
        admin.execute(sql.SQL('DROP DATABASE IF EXISTS {} WITH (FORCE)').format(sql.Identifier(database)))
        admin.close()


if __name__ == '__main__':
    main()
