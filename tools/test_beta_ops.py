import os
from pathlib import Path
import unittest
import tempfile
from unittest.mock import patch
import beta_ops


class BetaOperationsTests(unittest.TestCase):
    def test_failed_start_cleans_ingress_without_force_stopping_world(self):
        with tempfile.TemporaryDirectory() as directory:
            data = Path(directory)
            beta_ops.write_json(data / 'beta-processes.json', {'relay': {'pid': 123}})
            with patch.object(beta_ops, 'DATA', data), \
                    patch.object(beta_ops, '_start', side_effect=RuntimeError('not ready')), \
                    patch.object(beta_ops, 'stop_owned') as stop, patch.object(beta_ops, 'online') as online:
                with self.assertRaises(RuntimeError):
                    beta_ops.start({})
                self.assertFalse((data / 'beta-processes.json').exists())
                self.assertEqual(stop.call_count, 3)
                online.assert_not_called()

    def test_quick_tunnel_log_requires_exact_cloudflare_hostname(self):
        self.assertEqual(beta_ops.quick_origin('Visit https://amber-lake.trycloudflare.com now'),
                         'https://amber-lake.trycloudflare.com')
        self.assertIsNone(beta_ops.quick_origin('https://amber.trycloudflare.com.evil.example'))
        self.assertIsNone(beta_ops.quick_origin('http://amber.trycloudflare.com'))
        self.assertIsNone(beta_ops.quick_origin('https://amber.trycloudflare.com@evil.example'))

    def test_process_identity_rejects_reused_pid_or_different_executable(self):
        record = beta_ops.process_identity(os.getpid())
        self.assertTrue(beta_ops.matches(record))
        self.assertFalse(beta_ops.matches(dict(record, created=record['created'] + 1)))
        self.assertFalse(beta_ops.matches(dict(record, exe=str(Path(record['exe']).with_name('other.exe')))))
        self.assertFalse(beta_ops.matches({'pid': 4294967294, 'created': 0, 'exe': record['exe']}))

    def test_public_endpoint_config_stays_separate_from_private_keys(self):
        profile = beta_ops.public_profile({'account_url': 'https://beta.example',
            'world_host': 'game.example', 'world_port': 21777, 'world_id': 'world-1'}, 'beta-1')
        self.assertEqual(set(profile), {'schema', 'release_id', 'world_id', 'account_url',
                                     'world_host', 'world_port', 'tls_name'})
        self.assertEqual(profile['tls_name'], 'aetheria-beta')
        self.assertEqual(profile['world_id'], 'world-1')


if __name__ == '__main__':
    unittest.main()
