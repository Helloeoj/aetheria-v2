"""Real Godot -> authoritative world -> PostgreSQL session round trip.

Uses fresh test accounts in the local development service. Credentials and raw
world state are written only to the external test directory, never stdout/Git.
"""
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import tempfile
import urllib.error
import urllib.request

REPO = Path(__file__).resolve().parents[1]


def api(route, payload=None, token=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = f'Bearer {token}'
    request = urllib.request.Request('http://127.0.0.1:8780' + route,
        data=None if payload is None else json.dumps(payload).encode(), headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        return json.load(error)


def run_client(engine, output, name, password, expected=None):
    login = api('/api/login', {'username': name, 'password': password})
    assert login.get('ok'), f'Login failed: {login.get("code")}'
    ticket = api('/api/admit', {'world_id': 'world-1'}, login['token'])
    assert ticket.get('ok'), f'Admission failed: {ticket.get("code")}'
    output.mkdir(parents=True)
    config = {'username': name, 'character_id': login['character_id'],
        'ticket': ticket['ticket'], 'token': login['token'], 'output': str(output / 'result.json')}
    if expected is not None:
        config['expected_state'] = expected
    input_path = output / 'input.json'
    input_path.write_text(json.dumps(config), encoding='utf-8')
    command = [engine, '--headless', '--path', str(REPO / 'godot_client'),
        'res://scenes/dev_tools/online_session_smoke.tscn', '--log-file', str(output / 'godot.log'),
        '--', '--social-no-auto', '--test-input=' + str(input_path)]
    environment = dict(os.environ, AETHERIA_DIAGNOSTICS_DIR=str(output / 'adc'),
        AETHERIA_NATIVE_LOG=str(output / 'godot.log'))
    result = subprocess.run(command, capture_output=True, text=True, timeout=100, env=environment)
    transcript = result.stdout + result.stderr
    (output / 'validation.log').write_text(transcript, encoding='utf-8')
    print(transcript)
    assert result.returncode == 0 and re.search(r'\[Online session\] \d+ checks, 0 failures', transcript), 'Godot session failed'
    assert 'SCRIPT ERROR:' not in transcript and 'ERROR:' not in transcript, 'Godot runtime reported an error'
    return json.loads((output / 'result.json').read_text(encoding='utf-8'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--output', type=Path)
    arguments = parser.parse_args()
    output = arguments.output or Path(tempfile.mkdtemp(prefix='aetheria-online-'))
    subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', str(REPO / 'tools' / 'online.ps1'), 'start'], cwd=REPO, check=True, timeout=100)
    name = 'test_' + secrets.token_hex(5)
    password = secrets.token_urlsafe(24)
    registered = api('/api/register', {'username': name, 'password': password, 'password_confirmation': password})
    assert registered.get('ok'), f'Registration failed: {registered.get("code")}'
    first = run_client(arguments.godot, output / 'session-one', name, password)
    second = run_client(arguments.godot, output / 'session-two', name, password, first['state'])
    assert first['character_id'] == second['character_id'], 'Character changed after logout'
    print('[Online integration] Same persistent character restored across two real Godot sessions; 0 failures')
    print('Evidence:', output)


if __name__ == '__main__':
    main()
