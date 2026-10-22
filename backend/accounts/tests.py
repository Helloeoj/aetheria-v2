import json
import uuid
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from unittest.mock import patch

from django.db import close_old_connections, connection
from django.test import Client, TestCase, TransactionTestCase, override_settings
from django.utils import timezone


@override_settings()
class AccountApiTests(TestCase):
    password = 'Space rich password 42!'

    def setUp(self):
        self.key = patch.dict('os.environ', {'AETHERIA_SERVER_KEY': 'unit-test-server-key'})
        self.key.start()
        self.addCleanup(self.key.stop)

    def post(self, path, data=None, token=None, internal=False):
        headers = {}
        if token:
            headers['HTTP_AUTHORIZATION'] = 'Bearer ' + token
        if internal:
            headers['HTTP_X_AETHERIA_SERVER_KEY'] = 'unit-test-server-key'
        result = self.client.post(path, json.dumps(data or {}), content_type='application/json', **headers)
        self.assertEqual(result.headers['Content-Type'], 'application/json')
        return result.json()

    def register(self, name='PlayerOne'):
        result = self.post('/api/register', {'username': name, 'password': self.password,
            'password_confirmation': self.password})
        self.assertTrue(result['ok'], result)
        return result

    def login(self, name='PlayerOne'):
        result = self.post('/api/login', {'username': name, 'password': self.password})
        self.assertTrue(result['ok'], result)
        return result

    def claim(self, token, world='world-a'):
        admit = self.post('/api/admit', {'world_id': world}, token)
        self.assertTrue(admit['ok'], admit)
        return self.post('/internal/claim', {'ticket': admit['ticket'], 'world_id': world}, internal=True)

    def save_body(self, claim, state=None):
        return {'lease_token': claim['lease_token'], 'character_id': claim['character_id'],
            'expected_revision': claim['revision'], 'operation_id': str(uuid.uuid4()),
            'state': state or {'version': 1, 'level': 3, 'items': ['wood']}}

    def test_register_login_hash_and_casefold_uniqueness(self):
        created = self.register()
        self.assertEqual(str(uuid.UUID(created['account_id'])), created['account_id'])
        duplicate = self.post('/api/register', {'username': 'playerone', 'password': self.password,
            'password_confirmation': self.password})
        self.assertEqual(duplicate['code'], 'username_unavailable')
        login = self.login('PLAYERONE')
        self.assertEqual(login['character_id'], created['character_id'])
        from backend.accounts.models import Account, Session
        account = Account.objects.get(pk=created['account_id'])
        self.assertTrue(account.password_hash.startswith('argon2$argon2id$'))
        self.assertNotIn(self.password, account.password_hash)
        self.assertIsNone(account.email)
        self.assertIsNone(account.email_verified_at)
        self.assertNotEqual(Session.objects.get().token_hash, login['token'])

    def test_validation_generic_credentials_logout_and_unavailable_email(self):
        self.register()
        self.assertEqual(self.post('/api/register', {'username': 'bad name'})['code'], 'invalid_username')
        missing = self.post('/api/login', {'username': 'Nobody', 'password': self.password})
        bad = self.post('/api/login', {'username': 'PlayerOne', 'password': 'wrong'})
        self.assertEqual(missing, bad)
        login = self.login()
        self.assertTrue(self.post('/api/logout', token=login['token'])['ok'])
        self.assertEqual(self.post('/api/admit', {'world_id': 'a'}, login['token'])['code'], 'unauthorized')
        self.assertEqual(self.post('/api/password-reset', {'email': 'x@y.test'})['code'], 'not_available')

    def test_claim_ticket_single_use_atomic_revision_and_idempotency(self):
        self.register()
        login = self.login()
        admitted = self.post('/api/admit', {'world_id': 'a'}, login['token'])
        self.assertEqual(self.post('/internal/claim', {'ticket': admitted['ticket'], 'world_id': 'wrong'}, internal=True)['code'], 'invalid_ticket')
        claim = self.post('/internal/claim', {'ticket': admitted['ticket'], 'world_id': 'a'}, internal=True)
        self.assertTrue(claim['ok'], claim)
        self.assertEqual(claim['state'], {})
        self.assertEqual(self.post('/internal/claim', {'ticket': admitted['ticket'], 'world_id': 'a'}, internal=True)['code'], 'invalid_ticket')
        body = self.save_body(claim)
        first = self.post('/internal/save', body, internal=True)
        self.assertEqual(first, {'ok': True, 'revision': 1})
        self.assertEqual(self.post('/internal/save', body, internal=True), first)
        body['state']['level'] = 4
        self.assertEqual(self.post('/internal/save', body, internal=True)['code'], 'operation_mismatch')
        body = self.save_body(claim)
        self.assertEqual(self.post('/internal/save', body, internal=True)['code'], 'revision_conflict')
        from backend.accounts.models import Journal
        self.assertEqual(Journal.objects.count(), 1)

    def test_one_active_world_fencing_expiry_release_and_reload(self):
        self.register()
        login = self.login()
        first = self.claim(login['token'])
        self.assertTrue(first['ok'], first)
        self.assertEqual(self.claim(login['token'], 'world-b')['code'], 'character_busy')
        from backend.accounts.models import Character
        Character.objects.filter(pk=first['character_id']).update(lease_expires_at=timezone.now()-timedelta(seconds=1))
        second = self.claim(login['token'], 'world-b')
        self.assertTrue(second['ok'], second)
        self.assertNotEqual(second['lease_token'], first['lease_token'])
        self.assertEqual(self.post('/internal/save', self.save_body(first), internal=True)['code'], 'stale_lease')
        self.assertTrue(self.post('/internal/heartbeat', {'lease_token': second['lease_token'], 'character_id': second['character_id']}, internal=True)['ok'])
        body = self.save_body(second)
        release = self.post('/internal/release', body, internal=True)
        self.assertEqual(release, {'ok': True, 'revision': 1})
        self.assertEqual(self.post('/internal/release', body, internal=True), release)
        third = self.claim(login['token'])
        self.assertEqual(third['state'], body['state'])
        self.assertEqual(third['revision'], 1)

    def test_boundary_authorization_malformed_state_and_ticket_expiry(self):
        self.assertEqual(self.post('/internal/claim', {'ticket': 'anything', 'world_id': 'a'})['code'], 'unauthorized')
        self.register()
        login = self.login()
        admit = self.post('/api/admit', {'world_id': 'a'}, login['token'])
        from backend.accounts.models import Admission
        Admission.objects.update(expires_at=timezone.now()-timedelta(seconds=1))
        self.assertEqual(self.post('/internal/claim', {'ticket': admit['ticket'], 'world_id': 'a'}, internal=True)['code'], 'invalid_ticket')
        claim = self.claim(login['token'])
        body = self.save_body(claim, {'version': 2})
        self.assertEqual(self.post('/internal/save', body, internal=True)['code'], 'invalid_state')
        result = self.client.get('/api/character', HTTP_AUTHORIZATION='Bearer '+login['token']).json()
        self.assertTrue(result['ok'])
        self.assertNotIn('state', result)

    def test_password_nfc_preserves_spaces_and_boundary_lengths(self):
        password = '  A password Cafe\u0301  '
        result = self.post('/api/register', {'username': 'UnicodePass', 'password': password,
            'password_confirmation': '  A password Caf\u00e9  '})
        self.assertTrue(result['ok'], result)
        result = self.post('/api/login', {'username': 'UnicodePass', 'password': '  A password Caf\u00e9  '})
        self.assertTrue(result['ok'], result)
        self.assertEqual(self.post('/api/login', {'username': 'UnicodePass', 'password': password.strip()})['code'], 'bad_credentials')
        for password in ['x'*14, 'x'*129]:
            self.assertEqual(self.post('/api/register', {'username': 'ShortPass', 'password': password,
                'password_confirmation': password})['code'], 'invalid_password')

    def test_throttle_and_bounded_password_hash_slots(self):
        from backend.accounts.views import HASH_SLOTS
        self.assertTrue(HASH_SLOTS.acquire(blocking=False))
        self.assertTrue(HASH_SLOTS.acquire(blocking=False))
        try:
            result = self.post('/api/register', {'username': 'BusyPlayer', 'password': self.password,
                'password_confirmation': self.password})
            self.assertEqual(result['code'], 'busy')
        finally:
            HASH_SLOTS.release()
            HASH_SLOTS.release()
        for _ in range(20):
            result = self.post('/api/login', {'username': 'NoSuchUser', 'password': 'bad'})
        self.assertEqual(result['code'], 'rate_limited')

    def test_oversized_json_and_remote_http_return_json_errors(self):
        result = self.client.post('/api/register', '{"padding":"'+'x'*270000+'"}', content_type='application/json')
        self.assertEqual(result.status_code, 413)
        self.assertEqual(result.json()['code'], 'request_too_large')
        result = self.client.get('/health', REMOTE_ADDR='203.0.113.10')
        self.assertEqual(result.status_code, 403)
        self.assertEqual(result.json()['code'], 'https_required')

    def test_health_checks_storage_availability(self):
        from django.db import OperationalError
        with patch('backend.accounts.models.Character.objects.exists', side_effect=OperationalError('storage unavailable')):
            result = self.client.get('/health')
        self.assertEqual(result.status_code, 503)
        self.assertEqual(result.json()['code'], 'service_unavailable')


class PostgreSQLRaceTests(TransactionTestCase):
    def setUp(self):
        if connection.vendor != 'postgresql':
            self.skipTest('Requires PostgreSQL row locking; SQLite is development only.')
        self.key = patch.dict('os.environ', {'AETHERIA_SERVER_KEY': 'unit-test-server-key'})
        self.key.start()
        self.addCleanup(self.key.stop)

    def run_race(self, payloads, route):
        barrier = threading.Barrier(len(payloads))

        def submit(body):
            close_old_connections()
            try:
                barrier.wait(timeout=10)
                return Client().post(route, json.dumps(body), content_type='application/json',
                    HTTP_X_AETHERIA_SERVER_KEY='unit-test-server-key').json()
            finally:
                close_old_connections()

        with ThreadPoolExecutor(max_workers=len(payloads)) as executor:
            return list(executor.map(submit, payloads))

    def test_registration_race_enforces_unique_account_and_character(self):
        from backend.accounts.models import Account, Character
        body = {'username': 'Concurrent', 'password': 'A concurrent password 42!',
                'password_confirmation': 'A concurrent password 42!'}
        results = self.run_race([body, {**body, 'username': 'concurrent'}], '/api/register')
        self.assertEqual(sum(bool(r['ok']) for r in results), 1, results)
        self.assertEqual([r['code'] for r in results if not r['ok']], ['username_unavailable'])
        self.assertEqual(Account.objects.count(), 1)
        self.assertEqual(Character.objects.count(), 1)

    def test_world_claim_race_and_duplicate_save_race(self):
        from backend.accounts.models import Account, Admission, Character, Journal, Session
        from backend.accounts.views import digest
        account = Account.objects.create(username='Race', username_key='race', password_hash='unused')
        character = Character.objects.create(account=account)
        session = Session.objects.create(account=account, token_hash=digest('session'), expires_at=timezone.now()+timedelta(hours=1))
        payloads = []
        for world in ['a', 'b']:
            ticket = 'ticket-'+world
            Admission.objects.create(session=session, token_hash=digest(ticket), world_id=world,
                expires_at=timezone.now()+timedelta(seconds=30))
            payloads.append({'ticket': ticket, 'world_id': world})
        results = self.run_race(payloads, '/internal/claim')
        self.assertEqual(sum(bool(r['ok']) for r in results), 1, results)
        self.assertEqual([r['code'] for r in results if not r['ok']], ['character_busy'])
        claim = next(r for r in results if r['ok'])
        body = {'lease_token': claim['lease_token'], 'character_id': claim['character_id'],
            'expected_revision': 0, 'operation_id': str(uuid.uuid4()), 'state': {'version': 1, 'gold': 42}}
        results = self.run_race([body, body], '/internal/save')
        self.assertEqual(results, [{'ok': True, 'revision': 1}, {'ok': True, 'revision': 1}])
        self.assertEqual(Journal.objects.count(), 1)
        character.refresh_from_db()
        self.assertEqual(character.revision, 1)
