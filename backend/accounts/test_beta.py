"""Admission policy tests use temporary private config and isolated test storage."""
import io
import json
import os
import subprocess
import sys
import tempfile
import threading
from concurrent.futures import ThreadPoolExecutor
from contextlib import redirect_stdout
from datetime import timedelta
from pathlib import Path
from unittest.mock import patch

from django.db import close_old_connections, connection
from django.test import Client, SimpleTestCase, TestCase, TransactionTestCase
from django.utils import timezone

from backend.accounts.models import Account, Admission, Character


class BetaFixture:
    password = 'Private beta password 42!'

    def setUp(self):
        super().setUp()
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.data = Path(temporary.name)
        data_patch = patch('backend.service.DATA', self.data)
        data_patch.start()
        self.addCleanup(data_patch.stop)
        key_patch = patch.dict('os.environ', {'AETHERIA_SERVER_KEY': 'beta-test-key'})
        key_patch.start()
        self.addCleanup(key_patch.stop)
        self.configure()

    def configure(self, **changes):
        config = {'schema': 1, 'enabled': True, 'release_id': 'beta-2026.10'}
        config.update(changes)
        (self.data / 'beta.json').write_text(json.dumps(config), encoding='utf-8')

    def post(self, route, body=None, token=None):
        headers = {'HTTP_X_AETHERIA_SERVER_KEY': 'beta-test-key'}
        if token:
            headers['HTTP_AUTHORIZATION'] = 'Bearer ' + token
        return self.client.post(route, json.dumps(body or {}), content_type='application/json', **headers).json()

    def register(self, username='BetaPlayer', invite=None):
        return self.post('/api/register', {'username': username, 'password': self.password,
            'password_confirmation': self.password, 'invite_code': invite})

    def invite(self):
        from backend.beta import create_invite
        return create_invite(hours=1)

    def login(self, username='BetaPlayer'):
        return self.post('/api/login', {'username': username, 'password': self.password})

    def admitted(self):
        self.assertTrue(self.register(invite=self.invite())['ok'])
        token = self.login()['token']
        result = self.post('/api/admit', {'world_id': 'beta-world', 'release_id': 'beta-2026.10'}, token)
        self.assertTrue(result['ok'], result)
        return token, result['ticket']


class BetaApiTests(BetaFixture, TestCase):
    def test_beta_registration_requires_invite(self):
        result = self.register()
        self.assertFalse(result['ok'], result)
        self.assertEqual(result['code'], 'invalid_invite')
        self.assertEqual(Account.objects.count(), 0)

    def test_invite_is_hashed_single_use_and_grants_access(self):
        from backend.accounts.models import BetaAccess, BetaInvite
        code = self.invite()
        self.assertTrue(self.register(invite=code)['ok'])
        stored = BetaInvite.objects.get()
        self.assertNotIn(code, str(stored.__dict__))
        self.assertIsNotNone(stored.consumed_at)
        self.assertTrue(BetaAccess.objects.get().granted)
        self.assertTrue(self.login()['ok'])
        self.assertEqual(self.register('AnotherPlayer', code)['code'], 'invalid_invite')

    def test_invalid_expired_invite_and_failed_registration_do_not_consume(self):
        from backend.accounts.models import BetaInvite
        code = self.invite()
        self.assertEqual(self.register(invite='invalid-code')['code'], 'invalid_invite')
        BetaInvite.objects.update(expires_at=timezone.now()-timedelta(seconds=1))
        self.assertEqual(self.register(invite=code)['code'], 'invalid_invite')
        fresh = self.invite()
        self.assertTrue(self.register(invite=fresh)['ok'])
        unused = self.invite()
        self.assertEqual(self.register(invite=unused)['code'], 'username_unavailable')
        self.assertTrue(self.register('SecondPlayer', unused)['ok'])

    def test_existing_account_grant_revoke_preserves_save_and_rechecks_session(self):
        from backend.beta import set_access
        self.configure(enabled=False)
        created = self.register()
        Character.objects.filter(pk=created['character_id']).update(state={'version': 1, 'gold': 99}, revision=7)
        token = self.login()['token']
        self.configure()
        self.assertEqual(self.login()['code'], 'beta_access_required')
        self.assertEqual(self.post('/api/admit', {'world_id': 'beta-world', 'release_id': 'beta-2026.10'}, token)['code'], 'beta_access_required')
        set_access('BETAPLAYER', True)
        token = self.login()['token']
        self.assertTrue(self.client.get('/api/character', HTTP_AUTHORIZATION='Bearer '+token).json()['ok'])
        set_access('BetaPlayer', False)
        self.assertEqual(self.client.get('/api/character', HTTP_AUTHORIZATION='Bearer '+token).json()['code'], 'beta_access_required')
        character = Character.objects.get(pk=created['character_id'])
        self.assertEqual((character.state, character.revision), ({'version': 1, 'gold': 99}, 7))

    def test_release_bound_admission_and_server_claim(self):
        token, ticket = self.admitted()
        self.assertEqual(Admission.objects.get().release_id, 'beta-2026.10')
        for release in [None, 'old-release']:
            self.assertEqual(self.post('/api/admit', {'world_id': 'beta-world', 'release_id': release}, token)['code'], 'release_mismatch')
            self.assertEqual(self.post('/internal/claim', {'ticket': ticket, 'world_id': 'beta-world', 'release_id': release})['code'], 'release_mismatch')
        result = self.post('/internal/claim', {'ticket': ticket, 'world_id': 'beta-world', 'release_id': 'beta-2026.10'})
        self.assertTrue(result['ok'], result)

    def test_ticket_rejected_after_revocation_or_release_change(self):
        from backend.beta import set_access
        _, ticket = self.admitted()
        body = {'ticket': ticket, 'world_id': 'beta-world', 'release_id': 'beta-2026.10'}
        set_access('BetaPlayer', False)
        self.assertEqual(self.post('/internal/claim', body)['code'], 'beta_access_required')
        set_access('BetaPlayer', True)
        self.configure(release_id='new-release')
        body['release_id'] = 'new-release'
        self.assertEqual(self.post('/internal/claim', body)['code'], 'release_mismatch')
        self.assertFalse(Admission.objects.get().consumed)

    def test_public_release_is_allowlisted_and_validated(self):
        fields = {'account_url': 'https://accounts.example.test', 'world_host': 'play.example.test', 'world_port': 9070, 'world_id': 'beta-world'}
        self.configure(**fields, server_key='private-secret', database={'password': 'private-password'}, path='C:/private')
        response = self.client.get('/api/release')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {'ok': True, 'enabled': True, 'release_id': 'beta-2026.10', **fields})
        invalid = [{'account_url': 'http://example.test'}, {'account_url': 'https://user:password@example.test'},
            {'account_url': 'https://example.test?secret=x'}, {'world_host': '../private'},
            {'world_port': True}, {'world_port': 0}, {'world_port': 65536}, {'world_id': 'bad world'},
            {'release_id': 'a'*81}, {'release_id': 'nonascii-\u00e9'}, {'schema': True}, {'enabled': 'false'}]
        for values in invalid:
            with self.subTest(values=values):
                self.configure(**values)
                response = self.client.get('/api/release')
                self.assertEqual(response.status_code, 503)
                self.assertEqual(response.json()['code'], 'beta_unavailable')
        self.assertEqual(self.client.post('/api/release', '{}', content_type='application/json').status_code, 405)

    def test_malformed_config_fails_closed_and_disabled_missing_are_local(self):
        for content in ['{', '[]', '{}', '{"enabled": false}', '{"schema": 2, "enabled": false}']:
            (self.data / 'beta.json').write_text(content, encoding='utf-8')
            result = self.register()
            self.assertFalse(result['ok'], result)
            self.assertEqual(result['code'], 'beta_unavailable')
        self.configure(enabled=False)
        self.assertTrue(self.register()['ok'])
        (self.data / 'beta.json').unlink()
        token = self.login()['token']
        ticket = self.post('/api/admit', {'world_id': 'local-world'}, token)['ticket']
        self.assertTrue(self.post('/internal/claim', {'ticket': ticket, 'world_id': 'local-world'})['ok'])
        self.assertEqual(self.client.get('/api/release').json(), {'ok': True, 'enabled': False})

    def test_cli_status_and_grants_never_print_invites_or_credentials(self):
        from backend.beta_admin import run
        output = io.StringIO()
        with redirect_stdout(output):
            run(['invite', '--hours', '1'])
        code = output.getvalue().strip()
        self.assertTrue(self.register(invite=code)['ok'])
        for args in [['status'], ['revoke', 'BetaPlayer'], ['grant', 'BetaPlayer']]:
            output = io.StringIO()
            with redirect_stdout(output):
                run(args)
            status = output.getvalue()
            self.assertNotIn(code, status)
            self.assertNotIn('password_hash', status)
            self.assertNotIn(self.password, status)


class BetaRaceTests(BetaFixture, TransactionTestCase):
    def test_concurrent_registration_consumes_invite_once(self):
        if connection.vendor != 'postgresql':
            self.skipTest('Requires PostgreSQL row locking.')
        code = self.invite()
        barrier = threading.Barrier(2)

        def submit(name):
            close_old_connections()
            try:
                barrier.wait(timeout=10)
                return Client().post('/api/register', json.dumps({'username': name, 'password': self.password,
                    'password_confirmation': self.password, 'invite_code': code}), content_type='application/json').json()
            finally:
                close_old_connections()

        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(submit, ['FirstPlayer', 'SecondPlayer']))
        self.assertEqual(sum(result['ok'] for result in results), 1, results)
        self.assertEqual([result['code'] for result in results if not result['ok']], ['invalid_invite'])
        self.assertEqual(Account.objects.count(), 1)
        self.assertEqual(Character.objects.count(), 1)


class BetaAdminCommandTests(SimpleTestCase):
    def test_data_option_uses_only_selected_private_directory(self):
        # Separate SQLite-development database validates the real CLI's bootstrap,
        # without connecting its child processes to this test or the live database.
        with tempfile.TemporaryDirectory() as temporary:
            data = Path(temporary) / 'selected'
            data.mkdir()
            decoy = Path(temporary) / 'unselected'
            (data / 'config.json').write_text(json.dumps({'database': 'sqlite-development',
                'django_secret': 'isolated-cli-fixture-secret', 'host': '127.0.0.1', 'port': 8780}), encoding='utf-8')
            env = {key: value for key, value in os.environ.items()
                   if not key.startswith('AETHERIA_DB_') and key != 'AETHERIA_SQLITE_PATH'}
            env['AETHERIA_ACCOUNT_DATA'] = str(data)
            repo = Path(__file__).resolve().parents[2]
            prepare = subprocess.run([sys.executable, '-c',
                "from backend.service import load_config; load_config(); import django; django.setup(); "
                "from django.core.management import call_command; call_command('migrate', verbosity=0)"],
                env=env, cwd=repo, capture_output=True, text=True, timeout=30)
            self.assertEqual(prepare.returncode, 0, prepare.stderr)
            env['AETHERIA_ACCOUNT_DATA'] = str(decoy)
            result = subprocess.run([sys.executable, '-m', 'backend.beta_admin', '--data', str(data), 'status'],
                env=env, cwd=repo, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout), {'accounts': [], 'invites': {'available': 0, 'expired': 0, 'consumed': 0}})
            self.assertFalse(decoy.exists())
