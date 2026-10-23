"""Ingress cannot reach privileged routes or trust unauthenticated proxy headers."""
import unittest
from backend.public_gateway import gateway


class GatewayTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self.status = None
        self.token = 'x' * 48
        self.app = gateway(lambda env, start: self.calls.append(env) or [b'ok'],
                           self.token, lambda: {'enabled': True})

    def request(self, **changes):
        env = {'REMOTE_ADDR': '127.0.0.1', 'HTTP_X_AETHERIA_INGRESS': self.token,
               'HTTP_X_AETHERIA_CLIENT_IP': '203.0.113.5', 'PATH_INFO': '/api/login',
               'REQUEST_METHOD': 'POST', 'CONTENT_LENGTH': '12', 'QUERY_STRING': '',
               'HTTP_X_AETHERIA_SERVER_KEY': 'do-not-forward', 'HTTP_X_FORWARDED_PROTO': 'http',
               'HTTP_AUTHORIZATION': 'Bearer test', 'HTTP_HOST': 'attacker.invalid'}
        env.update(changes)
        self.app(env, lambda status, headers: setattr(self, 'status', status))

    def test_verified_public_route_gets_real_ip_and_https_without_internal_headers(self):
        self.request()
        self.assertEqual(len(self.calls), 1)
        env = self.calls[0]
        self.assertEqual(env['REMOTE_ADDR'], '203.0.113.5')
        self.assertEqual(env['wsgi.url_scheme'], 'https')
        self.assertEqual(env['HTTP_HOST'], '127.0.0.1')
        self.assertEqual(env['HTTP_AUTHORIZATION'], 'Bearer test')
        self.assertNotIn('HTTP_X_AETHERIA_SERVER_KEY', env)
        self.assertNotIn('HTTP_X_FORWARDED_PROTO', env)

    def test_blocked_paths_methods_spoofing_and_large_body(self):
        for changes in [
            {'PATH_INFO': '/internal/claim'}, {'PATH_INFO': '/api/login/'},
            {'PATH_INFO': '/api/../internal/save'}, {'QUERY_STRING': 'route=internal'},
            {'REQUEST_METHOD': 'GET'}, {'HTTP_X_AETHERIA_INGRESS': 'wrong'},
            {'HTTP_X_AETHERIA_CLIENT_IP': 'not-an-ip'}, {'REMOTE_ADDR': '203.0.113.2'},
            {'CONTENT_LENGTH': '262145'}, {'CONTENT_LENGTH': '-1'},
        ]:
            self.request(**changes)
            self.assertEqual(self.status, '404 Not Found', changes)
        self.assertFalse(self.calls)

    def test_disabled_or_broken_policy_never_exposes_account_api(self):
        for policy in [lambda: {'enabled': False}, lambda: (_ for _ in ()).throw(ValueError())]:
            self.app = gateway(lambda env, start: self.calls.append(env), self.token, policy)
            self.request()
        self.assertFalse(self.calls)
