"""Opt-in public-route probe using one disposable invited account on this PC.

This traverses Cloudflare and Playit from the host's own connection. It does not
establish another ISP's latency or a human gameplay result. Never uses owner saves.
"""
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True, type=Path)
    parser.add_argument('--client-exe', type=Path)
    parser.add_argument('--allow-live-probe', required=True, action='store_true')
    args = parser.parse_args()
    from backend.service import DATA, load_config
    load_config()
    import django
    django.setup()
    from backend.beta import create_invite, invite_digest, set_access
    from backend.accounts.models import Account, Character, BetaInvite
    policy = json.loads((DATA / 'beta.json').read_text(encoding='utf-8-sig'))
    assert policy['enabled'] is True
    output = Path(tempfile.mkdtemp(prefix='aetheria-public-beta-'))
    summary = {'passed': False, 'path': 'host PC through real Cloudflare/Playit services', 'sessions': []}
    base = policy['account_url']

    def request(path, payload=None, token=None):
        headers = {'Content-Type': 'application/json', 'User-Agent': 'AetheriaBetaProbe/1'}
        if token:
            headers['Authorization'] = 'Bearer ' + token
        message = urllib.request.Request(base + path,
            data=None if payload is None else json.dumps(payload).encode(), headers=headers)
        try:
            response = urllib.request.urlopen(message, timeout=15)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            return response.status, json.load(response)

    assert request('/internal/save', {})[0] == 404
    assert request('/admin')[0] == 404
    assert request('/api/release?debug=1')[0] == 404
    _, released = request('/api/release')
    assert released['release_id'] == policy['release_id'] and released['client_sha256'] == policy['client_sha256']
    summary['public_boundary'] = 'private routes/query rejected; exact release/hash served'
    username, password = 'probe_' + secrets.token_hex(5), secrets.token_urlsafe(24)
    invite = create_invite(1)
    account = None
    try:
        _, registered = request('/api/register', {'username': username, 'password': password,
            'password_confirmation': password, 'invite_code': invite})
        assert registered.get('ok'), 'Disposable invited registration failed.'
        account = Account.objects.get(username_key=username.lower())
        fixture_script = output / 'online_session_smoke.gd'
        shutil.copyfile(REPO / 'godot_client/scripts/dev_tools/online_session_smoke.gd', fixture_script)
        fixture_scene = output / 'online_session_smoke.tscn'
        fixture_scene.write_text('[gd_scene load_steps=2 format=3]\n'
            f'[ext_resource type="Script" path="{fixture_script.as_posix()}" id="1"]\n'
            '[node name="PublicBetaProbe" type="Node"]\nscript = ExtResource("1")\n', encoding='utf-8')
        previous = None
        clients = [('source', args.godot), *([('exported', args.client_exe)] if args.client_exe else [])]
        for name, executable in clients:
            _, login = request('/api/login', {'username': username, 'password': password})
            assert login.get('ok')
            _, wrong = request('/api/admit', {'world_id': policy['world_id'], 'release_id': 'old-version'}, login['token'])
            assert wrong.get('code') == 'release_mismatch'
            _, admission = request('/api/admit', {'world_id': policy['world_id'], 'release_id': policy['release_id']}, login['token'])
            assert admission.get('ok')
            session_output = output / (name + '-result.json')
            fixture = {'username': username, 'character_id': registered['character_id'],
                'token': login['token'], 'ticket': admission['ticket'], 'world_id': policy['world_id'],
                'release_id': policy['release_id'], 'account_url': base, 'output': str(session_output),
                'beta_profile': {'world_host': policy['world_host'], 'world_port': policy['world_port'],
                    'tls_name': 'aetheria-beta', 'tls_certificate': str(DATA / 'beta-runtime/world-public.crt')}}
            if previous:
                fixture['expected_state'] = previous['state']
            input_path = output / (name + '-input.json')
            input_path.write_text(json.dumps(fixture), encoding='utf-8')
            command = [str(executable), '--headless']
            if name == 'source':
                command += ['--path', str(REPO / 'godot_client')]
            command += [str(fixture_scene), '--log-file', str(output / (name + '-godot.log')),
                        '--', '--social-no-auto', '--test-input=' + str(input_path)]
            result = subprocess.run(command, cwd=output, capture_output=True, text=True, timeout=100,
                creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0),
                env=dict(os.environ, AETHERIA_DIAGNOSTICS_DIR=str(output / (name + '-adc'))))
            transcript = result.stdout + result.stderr
            (output / (name + '-console.log')).write_text(transcript, encoding='utf-8')
            assert result.returncode == 0 and 'ERROR:' not in transcript, 'Public game session failed; inspect private evidence.'
            previous = json.loads(session_output.read_text(encoding='utf-8'))
            assert previous['failures'] == 0
            saved = Character.objects.get(account=account)
            assert not saved.lease_hash and saved.revision > previous['revision'], 'Logout did not persist and release.'
            summary['sessions'].append({'kind': name,
                'checks': int(re.search(r'\[Online session\] (\d+) checks', transcript)[1]),
                'prediction_ms': float(re.search(r'first rendered response=([\d.]+)ms', transcript)[1]),
                'durable_logout': True})
        set_access(username, False)
        _, denied = request('/api/login', {'username': username, 'password': password})
        assert not denied.get('ok'), 'Revoked probe account still admitted.'
        summary['passed'] = True
    finally:
        if account is not None:
            character = Character.objects.get(account=account)
            if not character.lease_hash:
                account.delete()
                summary['probe_account_removed'] = True
            else:
                set_access(username, False)
                summary['cleanup_blocker'] = 'Probe character still has a lease; preserved for safe save/release.'
        BetaInvite.objects.filter(code_hash=invite_digest(invite)).delete()
        (output / 'summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
    print(json.dumps(summary))
    print('Private evidence:', output)


if __name__ == '__main__':
    main()
