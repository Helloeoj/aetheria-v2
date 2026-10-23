"""Two real clients, duplicate login rejection, expired lease retirement and reconnect.

Requires running local account/world services. Never restarts either service.
Only unique test accounts created by this invocation have their leases expired.
Use the account-service venv Python because lease expiry uses its Django models.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import time
import uuid

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO))
from test_online import api


def read(path):
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError):
        return None


def wait_for(condition, label, processes, seconds=35):
    deadline = time.monotonic()+seconds
    while time.monotonic() < deadline:
        result = condition()
        if result:
            return result
        for process, directory in processes:
            if process.poll() is not None and not (directory/'result.json').exists():
                raise AssertionError(label+': client exited without a result; inspect '+str(directory))
        time.sleep(.1)
    raise AssertionError(label+' timed out')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    output = args.output or Path(tempfile.mkdtemp(prefix='aetheria-online-concurrency-'))
    output.mkdir(parents=True, exist_ok=True)
    assert api('/health').get('ok'), 'Start the account service before running this test.'
    ready_path = Path(os.environ['LOCALAPPDATA'])/'Aetheria/online/world-ready.json'
    assert ready_path.exists(), 'Start the world service before running this test.'
    world = read(ready_path)
    assert world and world['world_id'] == 'world-1' and world['port'] == 24567, 'Test requires default local world configuration.'
    clients = []
    logs = []

    def account():
        username = 'race_'+secrets.token_hex(5)
        password = secrets.token_urlsafe(24)
        result = api('/api/register', {'username': username, 'password': password, 'password_confirmation': password})
        assert result.get('ok'), 'Registration failed: '+str(result.get('code'))
        login = api('/api/login', {'username': username, 'password': password})
        assert login.get('ok'), 'Login failed: '+str(login.get('code'))
        return {'username': username, 'password': password, **login}

    def launch(label, identity, other_id='', **options):
        admitted = api('/api/admit', {'world_id': 'world-1'}, identity['token'])
        assert admitted.get('ok'), 'Admission failed: '+str(admitted.get('code'))
        directory = output/label
        directory.mkdir()
        config = {'username': identity['username'], 'character_id': identity['character_id'],
            'token': identity['token'], 'ticket': admitted['ticket'], 'directory': str(directory),
            'other_id': other_id, **options}
        (directory/'input.json').write_text(json.dumps(config), encoding='utf-8')
        log = (directory/'console.log').open('w', encoding='utf-8')
        logs.append(log)
        process = subprocess.Popen([args.godot, '--headless', '--path', str(REPO/'godot_client'),
            'res://scenes/dev_tools/online_concurrency_smoke.tscn', '--log-file', str(directory/'godot.log'),
            '--', '--social-no-auto', '--test-input='+str(directory/'input.json')],
            stdout=log, stderr=subprocess.STDOUT, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0),
            env=dict(os.environ, AETHERIA_DIAGNOSTICS_DIR=str(directory/'adc')))
        clients.append((process, directory))
        return process, directory

    def completed(client):
        process, directory = client
        result = wait_for(lambda: read(directory/'result.json'), 'Client result', clients)
        assert process.wait(timeout=10) == 0 and result['failures'] == 0, 'Client reported failures: '+str(directory)
        transcript = (directory/'console.log').read_text(encoding='utf-8')
        assert all(marker not in transcript for marker in ['SCRIPT ERROR:', 'ERROR:', 'WARNING:']), 'Godot runtime error/warning: '+str(directory)
        return result

    def action(client, command):
        (client[1]/'action.json').write_text(json.dumps({'id': str(uuid.uuid4()), 'command': command}), encoding='utf-8')

    def inventory(client, amount):
        return wait_for(lambda: (observation := read(client[1]/'observation.json')) and
            observation.get('bait_count') == amount, 'Durable inventory amount '+str(amount), clients)

    try:
        first, second = account(), account()
        a = launch('client-a', first, second['character_id'])
        b = launch('client-b', second, first['character_id'])
        wait_for(lambda: read(a[1]/'ready.json') and read(b[1]/'ready.json'), 'Shared region visibility', clients)
        inventory(a, 30)
        inventory(b, 30)
        previous_drops = {d['drop_id'] for d in read(b[1]/'observation.json').get('drops', [])}
        action(a, {'type': 'drop', 'item_name': 'Low Grade Fish Food', 'quantity': 1})
        inventory(a, 29)

        def transferred_drop():
            for drop in (read(b[1]/'observation.json') or {}).get('drops', []):
                if drop['drop_id'] not in previous_drops and drop.get('item_name') == 'Low Grade Fish Food' and drop.get('quantity') == 1:
                    return drop['drop_id']
            return None

        drop_id = wait_for(transferred_drop, 'Committed drop visible to the second real client', clients)
        action(b, {'type': 'pickup', 'drop_id': drop_id})
        inventory(b, 31)
        wait_for(lambda: all(drop.get('drop_id') != drop_id for drop in
            (read(a[1]/'observation.json') or {}).get('drops', [])), 'Claimed ground drop disappears', clients)
        duplicate = api('/api/login', {'username': first['username'], 'password': first['password']})
        assert duplicate.get('ok'), 'Duplicate account login failed unexpectedly.'
        rejected = launch('duplicate-a', {**first, **duplicate}, expect_rejection=True)
        rejected_result = completed(rejected)
        assert not rejected_result['joined'], 'Duplicate login stole an active world actor.'
        # Explicitly expire only the account made above; no world/account restart.
        (a[1]/'expire.request').write_text('expect-retirement', encoding='utf-8')
        from backend.service import load_config
        load_config()
        import django
        django.setup()
        from django.utils import timezone
        from datetime import timedelta
        from backend.accounts.models import Character
        changed = Character.objects.filter(pk=first['character_id'], account__username=first['username']).update(
            lease_expires_at=timezone.now()-timedelta(seconds=1))
        assert changed == 1, 'Could not expire the isolated test character lease.'
        retired = completed(a)
        assert retired['bait_count'] == 29, 'Source inventory removal was not durably acknowledged.'
        wait_for(lambda: (observed := read(b[1]/'observation.json')) is not None and
            first['character_id'] not in observed.get('ids', []), 'Old region actor retirement', clients)
        reconnect = launch('reconnected-a', {**first, **duplicate}, second['character_id'],
            minimum_revision=retired['first_revision'], expected_bait=29)
        wait_for(lambda: read(reconnect[1]/'ready.json'), 'Same character reconnect visibility', clients)
        wait_for(lambda: first['character_id'] in (read(b[1]/'observation.json') or {}).get('ids', []), 'Peer sees replacement actor', clients)
        observation = read(b[1]/'observation.json')
        assert observation['ids'].count(first['character_id']) == 1, 'Stale duplicate region actor survived reconnect.'
        (b[1]/'stop.request').write_text('logout', encoding='utf-8')
        receiver = completed(b)
        assert receiver['bait_count'] == 31, 'Recipient did not retain transferred item at logout.'
        receiver_login = api('/api/login', {'username': second['username'], 'password': second['password']})
        assert receiver_login.get('ok'), 'Recipient relogin failed.'
        resumed_b = launch('reconnected-b', {**second, **receiver_login}, first['character_id'], expected_bait=31)
        wait_for(lambda: read(resumed_b[1]/'ready.json'), 'Recipient restored after logout/login', clients)
        inventory(resumed_b, 31)
        (resumed_b[1]/'stop.request').write_text('logout', encoding='utf-8')
        completed(resumed_b)
        (reconnect[1]/'stop.request').write_text('logout', encoding='utf-8')
        restored = completed(reconnect)
        assert restored['character_id'] == retired['character_id'], 'Reconnect changed persistent identity.'
        print('[Online concurrency] Shared live region, durable drop/pickup transfer (30->29 / 30->31), duplicate admission rejection, expired lease retirement, both inventories restored after reconnect; 0 failures')
        print('Evidence:', output)
    finally:
        for process, _directory in clients:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
        for log in logs:
            log.close()


if __name__ == '__main__':
    main()
